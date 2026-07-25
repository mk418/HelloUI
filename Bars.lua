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

local function eachButton(def, fn)
    for i = 1, def.count do
        local btn = _G[def.buttons .. i]
        if btn then fn(btn) end
    end
end

local function suppress(def, on)
    local frame = _G[def.frame]
    if not frame then return end

    if on then
        if not suppressed[def.id] then
            suppressed[def.id] = { alpha = frame:GetAlpha() }
        end
        frame:SetAlpha(0)
        -- An alpha-0 frame still takes the mouse, so invisible buttons would
        -- stay clickable. EnableMouse is not a protected method, but the
        -- buttons are secure, so this only runs out of combat.
        frame:EnableMouse(false)
        eachButton(def, function(btn) btn:EnableMouse(false) end)
    else
        local saved = suppressed[def.id]
        frame:SetAlpha(saved and saved.alpha or 1)
        frame:EnableMouse(true)
        eachButton(def, function(btn) btn:EnableMouse(true) end)
        suppressed[def.id] = nil
    end
end

local function setProxy(def, shown)
    if not (Settings and Settings.SetValue and Settings.GetValue) then return false end

    -- Reading first keeps this idempotent: Settings.SetValue fires the whole
    -- SetActionBarToggles round trip to the server, and this runs on every
    -- zone change.
    local ok, current = pcall(Settings.GetValue, def.proxy)
    if ok and current == shown then return true end

    return pcall(Settings.SetValue, def.proxy, shown)
end

function Bars:Apply()
    local off = Config:GetTable("barsOff")
    local enabled = Config:Get("enabled")

    for _, def in ipairs(BARS) do
        -- With the addon switched off every bar goes back on, so `/hui off`
        -- is a real off rather than a freeze.
        local wantOff = enabled and off[def.id] and true or false

        if def.proxy then
            ns:WhenSafe("Bars:" .. def.id, function()
                setProxy(def, not wantOff)
            end)
        else
            ns:WhenSafe("Bars:" .. def.id, function()
                suppress(def, wantOff)
            end)
        end
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
