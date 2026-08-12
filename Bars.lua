local ADDON_NAME, ns = ...

ns.Bars = {}
local Bars = ns.Bars

local Config = ns.Config

--------------------------------------------------------------------------
-- Optional sibling-addon integration
--
-- The sibling addons remain standalone and never touch Blizzard's bars. They
-- register their top-level cluster here; HelloUI then owns both sides of the
-- accommodation: suppressing the redundant stock bars and lending an anchor
-- that follows MainActionBar when Edit Mode moves it.
--------------------------------------------------------------------------

local CLASS_BAR_SETS = {
    HelloWarrior = { bar1 = true, bar2 = true, bar3 = true },
    HelloDruid   = { bar1 = true, bar2 = true, bar3 = true },
    HelloRogue   = { bar1 = true, bar2 = true, bar3 = true },
    -- The Mage utility bank occupies the right-hand block when bottom-aligned.
    HelloMage    = { bar1 = true, bar2 = true, bar3 = true, bar4 = true },
}

local classClusters = {}

-- HelloHealer only creates its secure header on classes it actually supports.
-- Checking the frame rather than IsAddOnLoaded therefore leaves an
-- installed-but-inert copy alone on Warriors, Rogues, and other non-healers.
-- Its default position occupies the same lower-left strip as bar 5 and chat.
-- Read the frame but never hook or otherwise modify it: SecureGroupHeaderTemplate
-- is exactly the kind of taint surface this integration must stay away from.
local function helloHealerFrame()
    return _G["HelloHealerMainHeader1"]
end

local function integrationEnabled()
    return HelloUIDB ~= nil and Config:Enabled()
end

local function notifyLayout(entry, integrated)
    integrated = integrated and true or false
    if entry.integrated == integrated then return end
    entry.integrated = integrated
    if entry.layoutCallback then
        ns:WhenSafe("Bars:ClassLayout:" .. entry.addonName, function()
            entry.layoutCallback(integrated)
        end)
    end
end

local function effectiveSiblingBars()
    local off, active = {}, {}
    if not integrationEnabled() then return off, active end

    for addonName, entry in pairs(classClusters) do
        if entry.frame and entry.frame.IsShown and entry.frame:IsShown() then
            active[#active + 1] = addonName
            for barID in pairs(CLASS_BAR_SETS[addonName]) do off[barID] = true end
        end
    end

    if helloHealerFrame() then
        active[#active + 1] = "HelloHealer"
        off.bar5 = true
    end

    table.sort(active)
    return off, active
end

local function refreshClassBars()
    ns:WhenSafe("Bars:ClassIntegration", function() Bars:Apply() end)
end

local function registerClassCluster(addonName, frame, layoutCallback)
    if not CLASS_BAR_SETS[addonName] or not frame then return false end

    local entry = {
        addonName = addonName,
        frame = frame,
        layoutCallback = layoutCallback,
    }
    classClusters[addonName] = entry

    if frame.HookScript then
        frame:HookScript("OnShow", refreshClassBars)
        frame:HookScript("OnHide", refreshClassBars)
    end

    notifyLayout(entry, integrationEnabled())
    refreshClassBars()
    return true
end

HelloUIClassBarAPI = {
    Register = registerClassCluster,
    GetAnchor = function()
        local mainBar = _G["MainActionBar"]
        if not integrationEnabled() or not mainBar then return nil end
        return "BOTTOM", mainBar, "BOTTOM", 0, 0
    end,
}

--------------------------------------------------------------------------
-- The bar table
--
-- Blizzard's numbering, not DragonflightUI's. This matters: DragonflightUI
-- bound its "bar4" to MultiBarLeftButton and its "bar5" to
-- MultiBarRightButton (DragonflightUI/Modules/Actionbar/Actionbar.lua:2240-41),
-- which is the other way round from the game. Blizzard's own map is
-- PROXY_SHOW_ACTIONBAR_4 -> MultiBarRight and _5 -> MultiBarLeft
-- (Blizzard_ActionBar/Shared/MultiActionBars.lua, IsMultibarVisible).
--
-- So the old profile's `bar4 = off` was MultiBarLeft, which the game calls
-- bar 5 - and that is what the default in Config.lua switches off. The
-- numbers here match the labels in Blizzard's own Options > Action Bars
-- panel, because that is what the user reads.
--
-- `proxy` is Blizzard's settings variable where one exists. Bars 2-8 have
-- one; bar 1, the stance bar and the pet bar do not.
--------------------------------------------------------------------------

local BARS = {
    { id = "bar1",   frame = "MainActionBar",       buttons = "ActionButton",              count = 12 },
    { id = "bar2",   frame = "MultiBarBottomLeft",  buttons = "MultiBarBottomLeftButton",  count = 12, proxy = "PROXY_SHOW_ACTIONBAR_2" },
    { id = "bar3",   frame = "MultiBarBottomRight", buttons = "MultiBarBottomRightButton", count = 12, proxy = "PROXY_SHOW_ACTIONBAR_3" },
    { id = "bar4",   frame = "MultiBarRight",       buttons = "MultiBarRightButton",       count = 12, proxy = "PROXY_SHOW_ACTIONBAR_4" },
    { id = "bar5",   frame = "MultiBarLeft",        buttons = "MultiBarLeftButton",        count = 12, proxy = "PROXY_SHOW_ACTIONBAR_5" },
    { id = "bar6",   frame = "MultiBar5",           buttons = "MultiBar5Button",           count = 12, proxy = "PROXY_SHOW_ACTIONBAR_6" },
    { id = "bar7",   frame = "MultiBar6",           buttons = "MultiBar6Button",           count = 12, proxy = "PROXY_SHOW_ACTIONBAR_7" },
    { id = "bar8",   frame = "MultiBar7",           buttons = "MultiBar7Button",           count = 12, proxy = "PROXY_SHOW_ACTIONBAR_8" },
    { id = "stance", frame = "StanceBar",           buttons = "StanceButton",              count = 10 },
    { id = "pet",    frame = "PetActionBar",        buttons = "PetActionButton",           count = 10 },
}

ns.BARS = BARS

function Bars:Get(id)
    for _, def in ipairs(BARS) do
        if def.id == id then return def end
    end
end

--------------------------------------------------------------------------
-- Hiding a bar
--
-- Two mechanisms, because Blizzard only provides one of them.
--
-- Bars 2-8: drive Blizzard's own setting. Settings.SetValue on the proxy is
-- exactly what the checkbox in Options > Action Bars does, so it is
-- persistent, per-character, taint-free and needs no re-asserting. Nothing
-- to invent.
--
-- Bar 1, stance, pet: no native hide exists (no VisibleSetting in either
-- Edit Mode preset map, and Blizzard's checkbox list starts at bar 2). So
-- these are made invisible and non-interactive instead of hidden - and that
-- is a deliberate choice, not laziness:
--
--   IsNormalActionBarState() is literally `return MainActionBar:IsShown()`
--   (MultiActionBars.lua), and UpdateMultiActionBar gates EVERY multibar on
--   it. Hide MainActionBar and the next MultiActionBar_Update() takes bars
--   2-8 down with it. That is precisely the case this addon exists to serve
--   - the warrior who wants bar 1 gone but keeps bars 2 and 5 - so hiding
--   the frame is the one thing we must not do.
--
--   MainActionBar.visibility stays nil forever (it is only ever assigned
--   from a VisibleSetting the main bar does not have), so IsShown() reports
--   the real state and there is no override to hide behind.
--
-- The other route considered and rejected: RegisterStateDriver(bar,
-- "visibility", "hide"). It works and it self-heals every 0.2s, but each
-- evaluation runs HideOverride -> UpdateVisibility ->
-- UpdateActionBarLayout, and for a bottom-anchored bar that ends in an
-- unconditional UIParent_ManageFramePositions(). A permanent driver would
-- run that whole pass five times a second forever.
--
-- What alpha 0 does not do is give the space back; the bar still occupies
-- its slot in Blizzard's layout. Position is Edit Mode's job, and the class
-- addons draw their own bars wherever they like, so this has no practical
-- cost here.
--------------------------------------------------------------------------

local suppressed = {}

-- Every mouse-enabled thing under a suppressed bar, not just its action
-- buttons. MainActionBar also owns ActionBarPageNumber (which carries the
-- page-scroll arrows) and EndCaps, and alpha 0 makes them invisible without
-- making them unclickable - so a hidden bar 1 would leave two invisible
-- arrows that still page your bar when you clicked where they used to be.
--
-- Walking the bar's own children is safe in a way that walking Minimap's
-- children is not: nothing outside Blizzard parents anything to an action
-- bar. The class addons all parent to UIParent, and Masque re-skins buttons
-- in place rather than reparenting them.
local function eachMouseTarget(def, fn)
    local frame = _G[def.frame]
    if not frame then return end

    fn(frame)
    for i = 1, def.count do
        local btn = _G[def.buttons .. i]
        if btn then fn(btn) end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            fn(child)
        end
    end
end

local function suppress(def, on)
    local frame = _G[def.frame]
    if not frame then return end

    if on then
        if not suppressed[def.id] then
            local mouse = {}
            eachMouseTarget(def, function(f)
                if f.IsMouseEnabled then mouse[f] = f:IsMouseEnabled() end
            end)
            suppressed[def.id] = { alpha = frame:GetAlpha(), mouse = mouse }
        end
        frame:SetAlpha(0)
        -- EnableMouse IS a protected function on this build (the client's own
        -- API documentation flags it), which is why every call here runs
        -- through the out-of-combat queue. Keybinds are untouched by design -
        -- HelloWarrior takes over 1-7 with override bindings and still needs
        -- the underlying buttons live.
        eachMouseTarget(def, function(f) f:EnableMouse(false) end)
    else
        local saved = suppressed[def.id]
        if not saved then return end
        frame:SetAlpha(saved.alpha or 1)
        eachMouseTarget(def, function(f)
            local was = saved.mouse[f]
            -- Anything that was mouse-disabled before we touched it stays that
            -- way; blanket EnableMouse(true) would enable frames Blizzard had
            -- deliberately left off. But `nil` here means we never managed to
            -- read the original - restore to enabled rather than leaving an
            -- action bar permanently dead, which is the worse failure.
            if was == nil then was = true end
            f:EnableMouse(was)
        end)
        suppressed[def.id] = nil
    end
end

--------------------------------------------------------------------------
-- The native proxies
--
-- `barsOff` is the authoritative statement of which bars are shown: anything
-- in it is hidden, anything not in it is shown. That is a deliberate reversal
-- of an earlier, more timid version which would only ever turn a bar OFF, on
-- the grounds that Blizzard's own setting was not ours to overwrite.
--
-- The reversal is the point of the feature now. Reproducing DragonflightUI's
-- base action bar UI means deciding which bars are up, and a rule that can
-- only ever hide cannot do that - it left bar 5 dark forever because the
-- player's stored Blizzard setting happened to have it off.
--
-- What made the old behaviour a bug was that it was silent and unasked-for.
-- What makes this acceptable: it is the documented job of the feature, every
-- bar is individually switchable, the pre-existing value is remembered so
-- `/hui off` puts it back, and that memory lives in saved variables rather
-- than a file-local so a /reload between hiding and restoring cannot lose it.
--------------------------------------------------------------------------

local function proxyStore()
    HelloUIDB = HelloUIDB or {}
    HelloUIDB.proxyOriginals = HelloUIDB.proxyOriginals or {}
    return HelloUIDB.proxyOriginals
end

local function getProxy(def)
    if not (Settings and Settings.GetValue) then return nil end
    local ok, current = pcall(Settings.GetValue, def.proxy)
    if not ok then return nil end
    return current
end

local function setProxy(def, wantOff, enabled)
    if not (Settings and Settings.SetValue) then return end

    local store = proxyStore()
    local current = getProxy(def)
    if current == nil then return end

    if enabled then
        -- Remember what the player had, once, before we first change it.
        if store[def.id] == nil then store[def.id] = current end
        local want = not wantOff
        if current ~= want then pcall(Settings.SetValue, def.proxy, want) end
    else
        -- Addon switched off: hand every bar back to whatever it was.
        local original = store[def.id]
        store[def.id] = nil
        if original ~= nil and current ~= original then
            pcall(Settings.SetValue, def.proxy, original)
        end
    end
end

--------------------------------------------------------------------------
-- Main bar art: the gryphons and the backdrop
--
-- The old profile asked for both gone - `gryphons = 'NONE'` and
-- `hideArt = true` - and the design first read those as "nothing to do",
-- because in DragonflightUI they were telling DFUI not to draw art of its
-- own. True, and beside the point: on a stock client Blizzard's gryphons are
-- right there, and the intent was plainly to be rid of them.
--
-- This is appearance, not position, so it is HelloUI's job. The
-- delegate-to-Edit-Mode rule is about anchors; philosophy #1 is explicitly
-- "keep Blizzard's frames, change their appearance".
--
-- Blizzard's own HideBarArt setting drives exactly these two frames through
-- MainActionBarMixin:UpdateEndCaps, so this hides what that hides:
-- MainMenuBar - the backdrop, its end caps and the max-level bar - and
-- MainActionBar.EndCaps, the compact gryphons used once the bar has been
-- moved off its default spot.
--
-- Deliberately NOT routed through EditModeManagerFrame:OnSystemSettingChange.
-- That writes manager state in our taint context and persists into the
-- player's saved layout; hiding two unprotected art frames does neither and
-- is trivially reversible.
--
-- One casualty, and it is the same one Blizzard's own setting has:
-- MainMenuBarPerformanceBarFrame, the latency strip, lives inside MainMenuBar
-- and goes with it. The micro menu and the bag bar do not - both are children
-- of UIParent on this build, so they stay put.
--------------------------------------------------------------------------

local function artFrames()
    local bar = _G["MainActionBar"]
    return _G["MainMenuBar"], bar and bar.EndCaps
end

local function hideArt()
    local menuBar, endCaps = artFrames()
    if menuBar then menuBar:SetShown(false) end
    if endCaps then endCaps:SetShown(false) end
end

local function applyBarArt()
    if Config:Enabled() then
        hideArt()
        return
    end

    -- Restoring asks Blizzard which of the two belongs on screen rather than
    -- showing both: that choice depends on whether the bar is still in its
    -- default position, and UpdateEndCaps already knows the rule.
    local bar = _G["MainActionBar"]
    if bar and bar.UpdateEndCaps then
        pcall(bar.UpdateEndCaps, bar, false)
        return
    end

    local menuBar, endCaps = artFrames()
    if menuBar then menuBar:SetShown(true) end
    if endCaps then endCaps:SetShown(true) end
end

function Bars:Init()
    local bar = _G["MainActionBar"]
    if bar and bar.UpdateEndCaps then
        -- Hooking the INSTANCE, not MainActionBarMixin. Mixin() copies the
        -- function onto the frame when it is created, so hooking the mixin
        -- table afterwards reaches no existing frame - the mistake that made
        -- the old UpdateHotkeys hook silently inert.
        hooksecurefunc(bar, "UpdateEndCaps", function()
            if Config:Enabled() then hideArt() end
        end)
        Bars.hookedEndCaps = true
    end
end

function Bars:Apply()
    local off = Config:GetTable("barsOff")
    local enabled = Config:Get("enabled")
    local siblingOff = effectiveSiblingBars()

    for _, entry in pairs(classClusters) do
        notifyLayout(entry, enabled)
    end

    applyBarArt()

    for _, def in ipairs(BARS) do
        -- With the addon switched off every bar goes back to whatever the
        -- player had, so `/hui off` is a real off rather than a freeze.
        local wantOff = enabled and (off[def.id] or siblingOff[def.id]) and true or false

        ns:WhenSafe("Bars:" .. def.id, function()
            if def.proxy then
                setProxy(def, wantOff, enabled)
            else
                suppress(def, wantOff)
            end
        end)
    end
end

function Bars:StatusText()
    local missing = {}
    for _, def in ipairs(BARS) do
        if not _G[def.frame] then missing[#missing + 1] = def.id end
    end
    if #missing == 0 then return nil end
    return "bars missing: |cffff8080" .. table.concat(missing, ",") .. "|r"
end

function Bars:Status()
    local off = Config:GetTable("barsOff")
    local siblingOff, activeSiblings = effectiveSiblingBars()
    local list, native, forced = {}, {}, {}
    for _, def in ipairs(BARS) do
        if off[def.id] then
            list[#list + 1] = def.id
            if def.proxy then
                native[#native + 1] = def.id
            else
                forced[#forced + 1] = def.id
            end
        end
    end
    local menuBar, endCaps = artFrames()
    ns:Print("bar art: %s |cff808080(MainMenuBar=%s, EndCaps=%s, hook=%s)|r",
        Config:Enabled() and "hidden" or "shown",
        menuBar and tostring(menuBar:IsShown()) or "missing",
        endCaps and tostring(endCaps:IsShown()) or "missing",
        tostring(Bars.hookedEndCaps or false))

    if #activeSiblings > 0 then
        local automatic = {}
        for _, def in ipairs(BARS) do
            if siblingOff[def.id] then automatic[#automatic + 1] = def.id end
        end
        ns:Print("sibling integration: %s |cff808080(automatically off: %s)|r",
            table.concat(activeSiblings, ", "), table.concat(automatic, ", "))
    end

    if #list == 0 then
        if #activeSiblings > 0 then ns:Print("bars configured off: none")
        else ns:Print("bars: all shown") end
        return
    end
    ns:Print("bars off: %s", table.concat(list, ", "))
    if #native > 0 then
        ns:Print("  |cff808080via Blizzard's own setting: %s|r", table.concat(native, ", "))
    end
    if #forced > 0 then
        ns:Print("  |cff808080no native toggle, made invisible instead: %s|r", table.concat(forced, ", "))
    end
end
