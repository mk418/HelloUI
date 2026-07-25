local ADDON_NAME, ns = ...

ns.Bars = {}
local Bars = ns.Bars

local Config = ns.Config

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
-- Only ever written to turn a bar OFF, and only after remembering what the
-- player had. The earlier version wrote `not wantOff` for every bar, which
-- meant any bar the player had switched off in Blizzard's own Action Bars
-- options got switched back on at the next login - HelloUI silently
-- overwriting a setting it does not own, in a module whose whole argument is
-- that Blizzard's setting is the right mechanism.
--
-- The remembered value lives in saved variables rather than a file-local,
-- because a /reload between hiding and un-hiding would otherwise lose it and
-- restore a guess.
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

local function setProxy(def, wantOff)
    if not (Settings and Settings.SetValue) then return end

    local store = proxyStore()
    local current = getProxy(def)
    if current == nil then return end

    if wantOff then
        if store[def.id] == nil then store[def.id] = current end
        if current ~= false then pcall(Settings.SetValue, def.proxy, false) end
    else
        -- Restore only what we changed. A bar we never hid is none of our
        -- business, and store[def.id] == false means the player already had it
        -- off before we arrived, so it stays off.
        local original = store[def.id]
        store[def.id] = nil
        if original ~= nil and current ~= original then
            pcall(Settings.SetValue, def.proxy, original)
        end
    end
end

function Bars:Apply()
    local off = Config:GetTable("barsOff")
    local enabled = Config:Get("enabled")

    for _, def in ipairs(BARS) do
        -- With the addon switched off every bar goes back to whatever the
        -- player had, so `/hui off` is a real off rather than a freeze.
        local wantOff = enabled and off[def.id] and true or false

        ns:WhenSafe("Bars:" .. def.id, function()
            if def.proxy then
                setProxy(def, wantOff)
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
    if #list == 0 then
        ns:Print("bars: all shown")
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
