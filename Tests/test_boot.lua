-- Offline boot harness for HelloUI.
--
-- Stubs enough of the 1.15.9 API to load every file in TOC order, drive the
-- real login sequence, and then assert that each feature did what it claims.
-- This is the only verification available without the game, so it deliberately
-- checks observable end state (alpha values, cvars, anchors) rather than
-- whether a function was called.
--
-- Run from the addon root:  lua Tests/test_boot.lua

local failures = 0
local checks = 0

local function ok(cond, what)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print(("  FAIL  %s"):format(what))
    end
end

local function eq(got, want, what)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print(("  FAIL  %s  (got %s, want %s)"):format(what, tostring(got), tostring(want)))
    end
end

----------------------------------------------------------------------
-- Frame mock
--
-- Permissive by design: unknown methods are no-ops so the harness does not
-- have to model all of FrameXML, but everything the addon reads back is real
-- state.
----------------------------------------------------------------------

local Frame = {}

-- Widget methods the addon calls but whose behaviour nothing asserts on.
-- These are explicitly enumerated rather than caught by a permissive
-- __index, because a metatable that answers every key with a function makes
-- `if frame.SomeField then` true for fields that do not exist - and that
-- pattern is load-bearing throughout the addon.
local NOOP_METHODS = {
    "SetFrameStrata", "SetFrameLevel", "SetJustifyH", "SetJustifyV", "SetWidth",
    "SetHeight", "SetSpacing", "SetMinMaxValues", "SetValueStep", "SetValue",
    "SetObeyStepOnDrag", "SetOwner", "AddLine", "SetTexCoord", "SetDrawLayer",
    "RegisterForClicks", "RegisterForDrag", "SetMovable", "SetClampedToScreen",
    "SetUserPlaced", "SetToplevel", "SetScale", "SetFont", "GetFont",
    "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture",
    "SetAttribute", "SetID", "GetID", "Raise", "Lower", "SetParent",
    "SetHitRectInsets", "SetIgnoreParentAlpha", "SetPropagateMouseClicks",
}
for _, name in ipairs(NOOP_METHODS) do
    Frame[name] = function() end
end

Frame.__index = Frame

function Frame.new(name, parent)
    local f = setmetatable({}, Frame)
    f._name = name
    f._parent = parent
    f._alpha = 1
    f._shown = true
    f._mouse = true
    f._points = {}
    f._w, f._h = 100, 20
    f._scripts = {}
    f._events = {}
    f._regions = {}
    f._children = {}
    if parent and parent._children then parent._children[#parent._children + 1] = f end
    if name then _G[name] = f end
    return f
end

-- Buttons (UIPanelButtonTemplate) and font strings both carry these.
function Frame:SetText(t) self._text = t end
function Frame:GetText() return self._text end
function Frame:SetTextColor(r, g, b) self._color = { r, g, b } end

function Frame:GetName() return self._name end
function Frame:GetParent() return self._parent end
function Frame:SetAlpha(a) self._alpha = a end
function Frame:GetAlpha() return self._alpha end
function Frame:Show() self._shown = true end
function Frame:Hide() self._shown = false end
function Frame:IsShown() return self._shown end
function Frame:IsVisible() return self._shown end
function Frame:SetShown(v) self._shown = v and true or false end
function Frame:EnableMouse(v) self._mouse = v and true or false end
function Frame:IsMouseEnabled() return self._mouse end
-- rawget rather than table.unpack: this harness runs on whatever `lua` is
-- installed, and luacheck lints it as 5.1 where that field does not exist.
local unpackf = rawget(table, "unpack") or unpack
function Frame:GetChildren() return unpackf(self._children or {}) end
function Frame:SetSize(w, h) self._w, self._h = w, h end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetLeft() return 0 end
function Frame:GetBottom() return 0 end
function Frame:ClearAllPoints() self._points = {} end
function Frame:SetPoint(p, rel, relPoint, x, y)
    self._points = { { p = p, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 } }
end
function Frame:GetPoint(i)
    local pt = self._points[i or 1]
    if not pt then return nil end
    return pt.p, pt.rel, pt.relPoint, pt.x, pt.y
end
function Frame:SetScript(k, fn) self._scripts[k] = fn end
function Frame:GetScript(k) return self._scripts[k] end
function Frame:HookScript(k, fn) self._scripts[k .. "_hook"] = fn end
function Frame:RegisterEvent(e)
    -- The one event this build genuinely rejects. Mirrors the real client's
    -- `Attempt to register unknown event` so the harness exercises the guard.
    if e == "MINIMAP_PING" then error("Attempt to register unknown event \"MINIMAP_PING\"") end
    self._events[e] = true
end
function Frame:UnregisterAllEvents() self._events = {} end
function Frame:RegisterEventCallback(e, cb) self._events[e] = cb; return true end

function Frame:CreateFontString(name)
    local fs = Frame.new(name, self)
    fs.SetText = function(s, t) s._text = t end
    fs.GetText = function(s) return s._text end
    fs.SetTextColor = function(s, r, g, b) s._color = { r, g, b } end
    return fs
end

function Frame:CreateTexture(name)
    local t = Frame.new(name, self)
    t._vertex = { 1, 1, 1, 1 }
    t._desat = false
    t.SetVertexColor = function(s, r, g, b, a) s._vertex = { r, g, b, a or 1 } end
    t.GetVertexColor = function(s) return s._vertex[1], s._vertex[2], s._vertex[3], s._vertex[4] end
    t.SetDesaturated = function(s, v) s._desat = v and true or false; return true end
    t.SetTexture = function(s, tex) s._tex = tex end
    self._regions[#self._regions + 1] = t
    return t
end

-- StatusBar extras
local function makeStatusBar(name, parent)
    local b = Frame.new(name, parent)
    b._color = { 0, 1, 0, 1 }
    b.SetStatusBarColor = function(s, r, g, b2, a) s._color = { r, g, b2, a or 1 } end
    b.GetStatusBarColor = function(s) return s._color[1], s._color[2], s._color[3], s._color[4] end
    return b
end

----------------------------------------------------------------------
-- Global API stubs
----------------------------------------------------------------------

_G.UIParent = Frame.new("UIParent")
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg)
    _G._lastPrint = msg
    -- The addon contains its errors with pcall and reports them once. A
    -- contained error must still fail the harness, or the tests pass while the
    -- feature quietly does nothing.
    if tostring(msg):find("error in") then
        print("  FAIL  addon reported an internal error: " .. tostring(msg))
        _G._addonErrors = (_G._addonErrors or 0) + 1
    end
end }
_G.GameTooltip = Frame.new("GameTooltip")
_G.SlashCmdList = {}

local inCombat = false
_G.InCombatLockdown = function() return inCombat end

_G.CreateFrame = function(kind, name, parent, template)
    if kind == "StatusBar" then return makeStatusBar(name, parent) end
    local f = Frame.new(name, parent)
    if template and template:find("CheckButton") or kind == "CheckButton" then
        f.SetChecked = function(s, v) s._checked = v and true or false end
        f.GetChecked = function(s) return s._checked end
        -- UICheckButtonTemplate exposes its label as <name>Text
        if name then Frame.new(name .. "Text", f).SetText = function(s, t) s._text = t end end
    end
    return f
end

local hooks = {}
_G.hooksecurefunc = function(a, b, c)
    if type(a) == "string" then
        local orig = _G[a]
        assert(type(orig) == "function", "hooksecurefunc on non-function " .. tostring(a))
        _G[a] = function(...) local r = orig(...) b(...) return r end
        hooks[a] = true
    else
        local orig = a[b]
        assert(type(orig) == "function", "hooksecurefunc on non-function method " .. tostring(b))
        a[b] = function(...) local r = orig(...) c(...) return r end
        hooks[tostring(b)] = true
    end
end

-- CVars
local cvars = { xpBarText = "0" }
_G.C_CVar = {
    GetCVar = function(k) return cvars[k] end,
    SetCVar = function(k, v) cvars[k] = tostring(v); return true end,
}
_G.GetCVar = _G.C_CVar.GetCVar
_G.SetCVar = _G.C_CVar.SetCVar
_G.GetCVarBool = function(k) return cvars[k] == "1" end

_G.C_EventUtils = {
    IsEventValid = function(e) return e ~= "TOTALLY_NOT_AN_EVENT" end,
    IsCallbackEvent = function(e) return e == "MINIMAP_PING" end,
}

_G.C_AddOns = { IsAddOnLoaded = function() return false end }

-- Settings (the action bar visibility proxies)
local settingValues = {}
for i = 2, 8 do settingValues["PROXY_SHOW_ACTIONBAR_" .. i] = true end
_G.Settings = {
    GetValue = function(k) return settingValues[k] end,
    SetValue = function(k, v) settingValues[k] = v end,
    RegisterCanvasLayoutCategory = function() return { GetID = function() return 42 end } end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() _G._openedCategory = true end,
}

-- Class colours
_G.UnitClass = function() return "Warrior", "WARRIOR" end
_G.UnitName = function() return "Elouan" end

-- StaticPopup: record which dialog was raised so the prompt can be asserted
-- on and then answered, rather than silently never firing.
_G.StaticPopupDialogs = {}
_G._shownPopup = nil
_G.StaticPopup_Show = function(which) _G._shownPopup = which end
_G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.41, g = 0.8, b = 0.94 } }
_G.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", MAGE = "Mage" }
_G.LOCALIZED_CLASS_NAMES_FEMALE = { WARRIOR = "Warrior", MAGE = "Mage" }

-- Friends list
_G.FRIENDS_BUTTON_TYPE_BNET = 2
_G.FRIENDS_BUTTON_TYPE_WOW = 3
_G.FRIENDS_WOW_NAME_COLOR = { r = 0.11, g = 0.75, b = 0.95 }
_G.BNET_CLIENT_WOW = "WoW"
_G.C_FriendList = {
    GetFriendInfoByIndex = function(i)
        if i == 1 then
            return { name = "Alice", className = "Mage", level = 60, connected = true, notes = "raid lead <3" }
        end
        return { name = "Bob", className = "Warrior", level = 60, connected = false, notes = nil }
    end,
}
_G.BNGetFriendInfo = function() return nil end
_G.BNGetGameAccountInfo = function() return nil end
_G.FriendsFrame_UpdateFriendButton = function() end

_G.UnitFrameHealthBar_Update = function() end
_G.CopyTable = function(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = _G.CopyTable(v) end
    return out
end

----------------------------------------------------------------------
-- Edit Mode
--
-- Modelled on the real shapes: settings is an ARRAY of {setting,value}
-- pairs (not a map), anchorInfo.relativeTo is a frame NAME string, and the
-- preset manager hands back layouts already in that form.
----------------------------------------------------------------------

_G.Enum = _G.Enum or {}
_G.Enum.EditModeSystem = { ActionBar = 1, UnitFrame = 2, Minimap = 3, StatusTrackingBar = 4, CastBar = 5 }
_G.Enum.EditModeStatusTrackingBarSystemIndices = { StatusTrackingBar1 = 1, StatusTrackingBar2 = 2 }
_G.Enum.EditModeStatusTrackingBarSetting = { Size = 0 }
_G.Enum.EditModeCastBarSetting = { BarSize = 0, LockToPlayerFrame = 1 }
_G.Enum.ActionBarOrientation = { Horizontal = 0, Vertical = 1 }
_G.Enum.EditModeActionBarSystemIndices = {
    MainBar = 1, Bar2 = 2, Bar3 = 3, RightBar1 = 4, RightBar2 = 5,
    ExtraBar1 = 6, ExtraBar2 = 7, ExtraBar3 = 8,
    StanceBar = 11, PetActionBar = 12, PossessActionBar = 13,
}
_G.Enum.EditModeActionBarSetting = {
    Orientation = 0, NumRows = 1, NumIcons = 2, IconSize = 3, IconPadding = 4,
    VisibleSetting = 5, HideBarArt = 6, HideBarScrolling = 8, AlwaysShowButtons = 9,
}
_G.Enum.EditModeLayoutType = { Preset = 0, Account = 1, Character = 2 }
_G.Enum.EditModePresetLayouts = { Modern = 1, Classic = 2 }

local function presetSystem(index)
    return {
        system = 1, systemIndex = index,
        anchorInfo = { point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", offsetX = 0, offsetY = 0 },
        settings = { { setting = 1, value = 1 }, { setting = 3, value = 5 }, { setting = 4, value = 6 } },
        isInDefaultPosition = true,
    }
end

-- TWO presets, as the real client has (Modern + Classic). The count matters:
-- GetLayouts returns only the SAVED layouts while activeLayout indexes
-- presets-then-saved, and getting that offset wrong is what silently
-- activated a Blizzard preset instead of ours.
_G.EditModePresetLayoutManager = {
    GetCopyOfPresetLayouts = function()
        local function preset(name, idx)
            local systems = {}
            for _, i in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13 }) do
                table.insert(systems, presetSystem(i))
            end
            for _, sidx in ipairs({ 1, 2 }) do
                table.insert(systems, { system = 4, systemIndex = sidx,
                    anchorInfo = { point = "BOTTOM", relativeTo = "StatusTrackingBarManager", relativePoint = "BOTTOM", offsetX = 0, offsetY = 0 },
                    settings = { { setting = 0, value = 10 } }, isInDefaultPosition = true })
            end
            -- CastBar: a system with settings directly, so systemIndex nil.
            table.insert(systems, { system = 5, systemIndex = nil,
                anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 },
                settings = { { setting = 1, value = 0 } }, isInDefaultPosition = true })
            table.insert(systems, { system = 3, systemIndex = nil,
                anchorInfo = { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", offsetX = 0, offsetY = 0 },
                settings = {}, isInDefaultPosition = true })
            return { layoutIndex = idx, layoutName = name, layoutType = 0, systems = systems }
        end
        return { preset("Modern", 1), preset("Classic", 2) }
    end,
}

_G.EditModeManagerFrame = Frame.new("EditModeManagerFrame", _G.UIParent)
_G.EditModeManagerFrame.accountSettings = {}
_G.ShowUIPanel = function() _G._editModeKicked = (_G._editModeKicked or 0) + 1 end
_G.HideUIPanel = function() end

-- savedLayouts is what the client stores and what GetLayouts hands back.
local savedLayouts = {}
local activeIndex = 1

_G.C_EditMode = {
    GetLayouts = function()
        return { layouts = _G.CopyTable(savedLayouts), activeLayout = activeIndex }
    end,
    SaveLayouts = function(info)
        _G._lastSavedCount = #info.layouts
        -- The client keeps only the non-preset entries.
        local kept = {}
        for _, l in ipairs(info.layouts) do
            if l.layoutType ~= 0 then kept[#kept + 1] = l end
        end
        savedLayouts = kept
        if info.activeLayout then activeIndex = info.activeLayout end
    end,
    IsValidLayoutName = function() return true end,
    SetActiveLayout = function(i) activeIndex = i end,
}

-- What the player would actually be looking at. The client re-derives the
-- combined list as presets-then-saved and indexes THAT with activeLayout, so
-- the lookup has to do the same - otherwise this stub cannot catch the very
-- off-by-number-of-presets bug it exists for.
_G._activeLayoutName = function()
    local combined = {}
    for _, l in ipairs(_G.EditModePresetLayoutManager.GetCopyOfPresetLayouts()) do
        combined[#combined + 1] = l
    end
    for _, l in ipairs(savedLayouts) do combined[#combined + 1] = l end
    local l = combined[activeIndex]
    return l and l.layoutName
end
_G._savedLayouts = function() return savedLayouts end
_G.ToggleMinimap = function()
    -- Real behaviour: hides the map and the dial, then shows both again.
    if _G.GameTimeFrame then _G.GameTimeFrame:Show() end
end

----------------------------------------------------------------------
-- Blizzard frames the addon reaches for
----------------------------------------------------------------------

-- Action bars and buttons, exactly as ActionButtonTemplate builds them:
-- `Name` is a direct child (so the global resolves) and `HotKey` lives in an
-- unnamed TextOverlayContainer but is aliased onto the button.
local BARS = {
    { "MainActionBar", "ActionButton", 12 },
    { "MultiBarBottomLeft", "MultiBarBottomLeftButton", 12 },
    { "MultiBarBottomRight", "MultiBarBottomRightButton", 12 },
    { "MultiBarRight", "MultiBarRightButton", 12 },
    { "MultiBarLeft", "MultiBarLeftButton", 12 },
    { "MultiBar5", "MultiBar5Button", 12 },
    { "MultiBar6", "MultiBar6Button", 12 },
    { "MultiBar7", "MultiBar7Button", 12 },
    { "StanceBar", "StanceButton", 10 },
    { "PetActionBar", "PetActionButton", 10 },
}

for _, def in ipairs(BARS) do
    local bar = Frame.new(def[1], _G.UIParent)
    for i = 1, def[3] do
        local btn = Frame.new(def[2] .. i, bar)
        btn.Name = btn:CreateFontString(def[2] .. i .. "Name")
        local container = Frame.new(nil, btn)
        btn.HotKey = container:CreateFontString(def[2] .. i .. "HotKey")
        btn.HotKey.SetAlpha = function(s, a) s._alpha = a end
        btn.Name.SetAlpha = function(s, a) s._alpha = a end
        -- ActionButtonTemplate ships NormalTexture (UI-Quickslot2) at alpha 0.5.
        local normal = btn:CreateTexture()
        normal._alpha = 0.5
        normal.SetAlpha = function(s, a) s._alpha = a end
        normal.GetAlpha = function(s) return s._alpha end
        btn.GetNormalTexture = function() return normal end
    end
end

_G.ActionBarActionButtonMixin = { UpdateHotkeys = function() end }

-- Status tracking
_G.StatusTrackingBarManager = Frame.new("StatusTrackingBarManager")
_G.StatusTrackingBarManager.UpdateBarTextVisibility = function() _G._barTextRefreshed = true end

-- Player frame
local playerFrame = Frame.new("PlayerFrame", _G.UIParent)
local healthBar = makeStatusBar("PlayerFrameHealthBar", playerFrame)
playerFrame.HealthBar = healthBar

-- Minimap
local cluster = Frame.new("MinimapCluster", _G.UIParent)
local minimap = Frame.new("Minimap", cluster)
cluster.BorderTop = cluster:CreateTexture("MinimapClusterBorderTop")
Frame.new("MinimapBorder", minimap):CreateTexture()
_G.MinimapBorder = cluster:CreateTexture("MinimapBorder")
local zoomIn = Frame.new("MinimapZoomIn", minimap)
local zoomOut = Frame.new("MinimapZoomOut", minimap)
for _, b in ipairs({ zoomIn, zoomOut }) do
    local n, d = b:CreateTexture(), b:CreateTexture()
    b.GetNormalTexture = function() return n end
    b.GetDisabledTexture = function() return d end
end
Frame.new("GameTimeFrame", cluster)

-- Action bar art + cast bars
local mainMenuBar = Frame.new("MainMenuBar", _G.UIParent)
for i = 0, 3 do _G["MainMenuBarTexture" .. i] = mainMenuBar:CreateTexture("MainMenuBarTexture" .. i) end
-- MainActionBar.EndCaps and the mixin method Blizzard copies onto the frame.
_G.MainActionBar.EndCaps = Frame.new(nil, _G.MainActionBar)
_G.MainActionBar.UpdateEndCaps = function(self, forceHide)
    -- Mirrors MainActionBarMixin:UpdateEndCaps closely enough to test against.
    if forceHide then
        mainMenuBar:SetShown(false)
        self.EndCaps:SetShown(false)
    else
        mainMenuBar:SetShown(true)
        self.EndCaps:SetShown(false)
    end
end
local pcb = Frame.new("PlayerCastingBarFrame", _G.UIParent)
pcb.Border = pcb:CreateTexture()
local petcb = Frame.new("PetCastingBarFrame", _G.UIParent)
petcb.Border = petcb:CreateTexture()

-- Unit frame art
_G.PlayerFrameTexture = playerFrame:CreateTexture("PlayerFrameTexture")
_G.TargetFrameTextureFrameTexture = _G.UIParent:CreateTexture("TargetFrameTextureFrameTexture")
_G.PetFrameTexture = _G.UIParent:CreateTexture("PetFrameTexture")

-- Chat
local chat = Frame.new("ChatFrame1", _G.UIParent)
chat:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 10, 10)
chat:SetSize(400, 180)

-- Friends list scroll frame with two recycled buttons
-- The real client declares this as a GLOBAL child of FriendsListFrame with no
-- parentKey, so FriendsListFrame.ScrollFrame is nil in game. The stub models
-- the real shape; an earlier version invented the parentKey and hid a bug.
local friendsList = Frame.new("FriendsListFrame", _G.UIParent)
local friendsScroll = Frame.new("FriendsFrameFriendsScrollFrame", friendsList)
friendsScroll.buttons = {}
for i = 1, 2 do
    local b = Frame.new(nil, friendsList)
    b.index = i
    b.id = i
    b.buttonType = _G.FRIENDS_BUTTON_TYPE_WOW
    b.name = b:CreateFontString()
    b.gameIcon = Frame.new(nil, b)
    friendsScroll.buttons[i] = b
end

----------------------------------------------------------------------
-- Load the addon in TOC order
----------------------------------------------------------------------

local ns = {}
local FILES = {
    "Core.lua", "Config.lua", "Buttons.lua", "Bars.lua", "StatusBars.lua",
    "Player.lua", "Darkmode.lua", "Minimap.lua", "Friends.lua", "Layout.lua",
    "Options.lua",
}

print("HelloUI boot harness")

for _, file in ipairs(FILES) do
    local chunk, err = loadfile(file)
    if not chunk then
        print(("  FAIL  could not load %s: %s"):format(file, err))
        failures = failures + 1
    else
        local success, runErr = pcall(chunk, "HelloUI", ns)
        if not success then
            print(("  FAIL  error running %s: %s"):format(file, runErr))
            failures = failures + 1
        end
    end
end

ok(ns.Config ~= nil, "Config module loaded")
ok(ns.Options ~= nil, "Options module loaded")

----------------------------------------------------------------------
-- Drive the login sequence
----------------------------------------------------------------------

local function fire(event, ...)
    local handlers = ns.eventHandlers[event]
    if not handlers then return end
    for i = 1, #handlers do handlers[i](...) end
end

fire("ADDON_LOADED", "HelloUI")
ok(_G.HelloUIDB ~= nil, "saved variables created")
eq(ns.Config:Get("enabled"), true, "enabled by default")

fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD")

----------------------------------------------------------------------
-- Assertions: the guarded event registration
----------------------------------------------------------------------

print("\nevents")
ok(ns:On("TOTALLY_NOT_AN_EVENT", function() end) == false,
    "ns:On refuses an invalid event")
-- MINIMAP_PING throws on RegisterEvent but is a callback event, so it must
-- still register rather than taking the addon down.
ok(ns:On("MINIMAP_PING", function() end) == true,
    "ns:On falls back to RegisterEventCallback for MINIMAP_PING")

----------------------------------------------------------------------
-- Assertions: buttons
----------------------------------------------------------------------

print("\nbuttons")
eq(_G.ActionButton1.HotKey._alpha, 0, "bar1 keybind text hidden")
eq(_G.ActionButton1.Name._alpha, 0, "bar1 macro text hidden")
eq(_G.StanceButton1.HotKey._alpha, 0, "stance keybind text hidden")
eq(_G.PetActionButton10.Name._alpha, 0, "pet macro text hidden")
eq(_G.MultiBar7Button12.HotKey._alpha, 0, "bar8 keybind text hidden")
eq(_G.ActionButton1:GetNormalTexture()._alpha, 1, "button border taken to full alpha")
eq(_G.StanceButton1:GetNormalTexture()._alpha, 1, "including the stance bar")

----------------------------------------------------------------------
-- Assertions: bars
--
-- The default switches off the physical bar the old profile had off, which is
-- MultiBarLeft. Blizzard calls that bar 5, so the proxy touched must be
-- PROXY_SHOW_ACTIONBAR_5 and every other proxy must be untouched.
----------------------------------------------------------------------

print("\nbars")
-- DragonflightUI's base set: 1-5 up, 6-8 down.
eq(settingValues["PROXY_SHOW_ACTIONBAR_2"], true, "bar2 shown")
eq(settingValues["PROXY_SHOW_ACTIONBAR_4"], true, "bar4 shown")
eq(settingValues["PROXY_SHOW_ACTIONBAR_5"], true, "bar5 shown - part of the base UI")
eq(settingValues["PROXY_SHOW_ACTIONBAR_6"], false, "bar6 hidden")
eq(settingValues["PROXY_SHOW_ACTIONBAR_8"], false, "bar8 hidden")
eq(_G.MainActionBar._alpha, 1, "bar1 untouched by default")
-- Hiding bar1 must never Hide() the frame: IsNormalActionBarState() reads
-- MainActionBar:IsShown() and would drag bars 2-8 down with it.
ns.Config:SetChar("barsOff", { bar1 = true })
ns:ApplyAll()
eq(_G.MainActionBar._alpha, 0, "bar1 made invisible when switched off")
eq(_G.MainActionBar:IsShown(), true, "bar1 frame stays SHOWN (bars 2-8 depend on it)")
eq(_G.ActionButton1._mouse, false, "bar1 buttons made non-interactive")
ns.Config:ClearChar("barsOff")
ns:ApplyAll()
eq(_G.MainActionBar._alpha, 1, "bar1 restored")
eq(_G.ActionButton1._mouse, true, "bar1 buttons interactive again")

----------------------------------------------------------------------
-- Assertions: status bars, player, minimap, chat, darkmode
----------------------------------------------------------------------

print("\nstatus bars")
eq(cvars.xpBarText, "1", "xpBarText set")

print("\nplayer")
eq(healthBar.lockColor, true, "lockColor set so Blizzard stops resetting the colour")
local r, g, b = healthBar:GetStatusBarColor()
eq(r, 0.78, "health bar red channel is the warrior class colour")
eq(g, 0.61, "health bar green channel is the warrior class colour")
eq(b, 0.43, "health bar blue channel is the warrior class colour")

print("\nminimap")
eq(_G.GameTimeFrame:IsShown(), false, "time-of-day dial hidden")
_G.ToggleMinimap()
eq(_G.GameTimeFrame:IsShown(), false, "still hidden after ToggleMinimap re-shows it")

print("\nlayout")
-- Nothing is applied behind the player's back: login raises a prompt and
-- otherwise leaves Edit Mode alone.
eq(#_G._savedLayouts(), 0, "login does not silently write a layout")
eq(_G._shownPopup, "HELLOUI_USE_LAYOUT", "login asks instead")

_G.StaticPopupDialogs["HELLOUI_USE_LAYOUT"].OnAccept()
eq(#_G._savedLayouts(), 1, "accepting creates the layout")
eq(_G._savedLayouts()[1].layoutName, "HelloUI", "named HelloUI")

-- THE regression. activeLayout indexes presets-then-saved, so an index
-- computed against the saved-only list points at a Blizzard preset and the
-- player watches their UI switch to Classic.
eq(_G._activeLayoutName(), "HelloUI", "the ACTIVE layout is ours, not a preset")
ok((_G._editModeKicked or 0) > 0, "Edit Mode was nudged into applying it")

-- Once it is the active layout the question is retired for good.
_G._shownPopup = nil
ns.Layout.MaybeAsk(ns.Layout)
eq(_G._shownPopup, nil, "no prompt once the layout is already active")

do
    local sys, bars, moved = _G._savedLayouts()[1].systems, 0, 0
    local mainBar, minimapSystem
    for _, e in ipairs(sys) do
        if e.system == 1 then
            bars = bars + 1
            if not e.isInDefaultPosition then moved = moved + 1 end
            if e.systemIndex == 1 then mainBar = e end
        elseif e.system == 3 then
            minimapSystem = e
        end
    end
    eq(bars, 11, "every action bar system carried over from the preset")
    eq(moved, 7, "the seven action bars we position are flagged as moved")
    ok(minimapSystem ~= nil and minimapSystem.isInDefaultPosition == true,
        "systems we do not touch are left exactly as Blizzard had them")

    local size, pad, rows
    local wellFormed = true
    for _, st in ipairs(mainBar.settings) do
        if type(st) ~= "table" or st.setting == nil then
            wellFormed = false
        else
            if st.setting == 3 then size = st.value end
            if st.setting == 4 then pad = st.value end
            if st.setting == 1 then rows = st.value end
        end
    end
    ok(wellFormed, "settings stayed an array of {setting,value} pairs")
    eq(size, 5, "icon size raw 5 (= 100%)")
    eq(pad, 0, "icon padding raw 0 (= 2px)")
    eq(rows, 1, "main bar is one row")
    eq(mainBar.anchorInfo.relativeTo, "UIParent", "main bar pinned to UIParent")
    eq(mainBar.anchorInfo.offsetY, 24, "main bar sits above the status bars")

    -- The XP/reputation bars must be re-pinned under the stack. Left on
    -- Blizzard's preset they anchor to StatusTrackingBarManager and end up
    -- stranded among the button rows once the bar art is hidden.
    local statusBars = 0
    for _, e in ipairs(sys) do
        if e.system == 4 then
            statusBars = statusBars + 1
            eq(e.anchorInfo.relativeTo, "UIParent", "status bar re-pinned to UIParent")
            eq(e.isInDefaultPosition, false, "status bar flagged as moved")
            ok(e.anchorInfo.offsetY < 24, "status bar sits below the bottom action bar")
            -- Only action bars take NumRows/IconSize; a status bar must not.
            for _, st in ipairs(e.settings) do
                ok(st.setting ~= 1 and st.setting ~= 3 and st.setting ~= 4,
                    "no action bar settings written onto a status bar")
            end
        end
    end
    eq(statusBars, 2, "both status tracking slots positioned")

    -- The status bars ship 1024 wide; Size is a SCALE, and raw 0 is the
    -- slider's floor of 50% - the narrowest Edit Mode allows, 512 against the
    -- 454 stack.
    for _, e in ipairs(sys) do
        if e.system == 4 then
            local statusSize
            for _, st in ipairs(e.settings) do
                if st.setting == 0 then statusSize = st.value end
            end
            eq(statusSize, 0, "status bar narrowed to the slider's 50% floor")
        end
    end

    -- The cast bar is parked above the bars, not at screen centre, and is
    -- explicitly unlocked from the player frame so the anchor is honoured.
    local cast
    for _, e in ipairs(sys) do
        if e.system == 5 then cast = e end
    end
    ok(cast ~= nil, "cast bar found")
    eq(cast and cast.anchorInfo.relativePoint, "BOTTOM", "cast bar measured from the screen bottom")
    eq(cast and cast.anchorInfo.offsetY, 245, "cast bar sits above the action bars")
    eq(cast and cast.isInDefaultPosition, false, "cast bar flagged as moved")
    do
        local lock
        for _, st in ipairs(cast.settings) do
            if st.setting == 1 then lock = st.value end
        end
        eq(lock, 0, "cast bar not locked to the player frame")
    end

    -- Chaining bar-to-bar overlapped on screen, because an Edit Mode bar
    -- frame is shorter than its buttons. Everything is UIParent-relative now
    -- and the stacked bars must clear a 36px icon.
    local ys, allUIParent = {}, true
    for _, e in ipairs(sys) do
        if e.system == 1 and not e.isInDefaultPosition then
            if e.anchorInfo.relativeTo ~= "UIParent" then allUIParent = false end
            if e.systemIndex == 1 or e.systemIndex == 2 or e.systemIndex == 3 then
                ys[#ys + 1] = e.anchorInfo.offsetY
            end
        end
    end
    ok(allUIParent, "no bar is anchored to another bar")
    table.sort(ys)
    local minGap = math.huge
    for i = 2, #ys do
        if ys[i] ~= ys[i - 1] then minGap = math.min(minGap, ys[i] - ys[i - 1]) end
    end
    -- Snug, not spaced: the pitch must clear a 36px button so the rows never
    -- overlap, and must not exceed button+padding or a visible gap opens up
    -- and the three bars stop reading as one grid.
    ok(minGap >= 36, ("rows never overlap a 36px button (gap %s)"):format(tostring(minGap)))
    ok(minGap <= 38, ("rows are snug, not spaced (gap %s)"):format(tostring(minGap)))

    -- The side blocks must be 4 wide x 3 tall. Blizzard's preset has both
    -- side bars Vertical, where NumRows counts COLUMNS and rows=3 yields a
    -- 3x4 block instead - so orientation has to be stated, not inherited.
    local sideChecked = 0
    for _, e in ipairs(sys) do
        if e.system == 1 and (e.systemIndex == 4 or e.systemIndex == 5) then
            local orient, sideRows
            for _, st in ipairs(e.settings) do
                if st.setting == 0 then orient = st.value end
                if st.setting == 1 then sideRows = st.value end
            end
            eq(orient, 0, "side bar forced Horizontal, not the preset's Vertical")
            eq(sideRows, 3, "3 rows of 4, not 3 columns of 4")
            sideChecked = sideChecked + 1
        end
    end
    eq(sideChecked, 2, "both side blocks checked")
end

-- Re-applying refreshes rather than duplicating, and stays active.
ns.Layout:Apply(true)
eq(#_G._savedLayouts(), 1, "re-applying refreshes rather than duplicating")
eq(_G._activeLayoutName(), "HelloUI", "still active after a refresh")

-- Reset: Edit Mode saves dragging into the layout, so re-applying must
-- overwrite whatever is there with the shipped geometry.
do
    local live = _G._savedLayouts()
    for _, e in ipairs(live[1].systems) do
        if e.system == 1 and e.systemIndex == 1 then
            e.anchorInfo.offsetY = 999
            for _, st in ipairs(e.settings) do
                if st.setting == 3 then st.value = 9 end
            end
        end
    end
    ns.Layout:Reset()
    local mainBar
    for _, e in ipairs(_G._savedLayouts()[1].systems) do
        if e.system == 1 and e.systemIndex == 1 then mainBar = e end
    end
    eq(mainBar.anchorInfo.offsetY, 24, "reset restores the shipped position")
    local size
    for _, st in ipairs(mainBar.settings) do
        if st.setting == 3 then size = st.value end
    end
    eq(size, 5, "reset restores the shipped icon size")
end

-- Per-character mode: a separate, character-typed, character-named layout.
ns.Config:SetChar("layoutPerCharacter", true)
ns.Layout:Apply(true)
do
    local live = _G._savedLayouts()
    eq(#live, 2, "per-character mode adds a second layout")
    local mine
    for _, l in ipairs(live) do
        if l.layoutName == "HelloUI - Elouan" then mine = l end
    end
    ok(mine ~= nil, "named for the character")
    eq(mine and mine.layoutType, 2, "typed Character so other characters never see it")
    eq(_G._activeLayoutName(), "HelloUI - Elouan", "and it is the active one")
end
ns.Layout:Apply(true)
eq(#_G._savedLayouts(), 2, "per-character re-apply refreshes too")
ns.Config:ClearChar("layoutPerCharacter")

print("\nbar art")
eq(mainMenuBar:IsShown(), false, "main bar backdrop hidden")
eq(_G.MainActionBar.EndCaps:IsShown(), false, "gryphon end caps hidden")
-- Blizzard re-running its own end-cap logic must not bring them back.
_G.MainActionBar:UpdateEndCaps(false)
eq(mainMenuBar:IsShown(), false, "still hidden after Blizzard recomputes end caps")
ok(ns.Bars.hookedEndCaps, "UpdateEndCaps hooked on the instance")

print("\nchat")
-- ChatFrame1 inherits EditModeChatFrameSystemTemplate on 1.15.9, so the addon
-- deliberately owns nothing here. Assert it stays hands-off.
eq(chat:GetWidth(), 400, "chat width left alone")
eq(chat:GetHeight(), 180, "chat height left alone")
local _, _, _, ccx, ccy = chat:GetPoint(1)
ok(ccx == 10 and ccy == 10, "chat position left alone")

print("\ndarkmode")
eq(_G.PlayerFrameTexture._desat, true, "player frame art desaturated")
local dr, dg, db = _G.PlayerFrameTexture:GetVertexColor()
ok(dr == 0.4 and dg == 0.4 and db == 0.4, "player frame art tinted 0.4 grey")
eq(_G.MainMenuBarTexture0._desat, true, "action bar art desaturated")
eq(cluster.BorderTop._desat, true, "minimap header art desaturated")

print("\nfriends")
ns.Friends:Refresh()
local aliceColor = friendsScroll.buttons[1].name._color
ok(aliceColor and aliceColor[1] == 0.41, "online mage friend class-coloured")
ok(friendsScroll.buttons[1].HelloUIHeart ~= nil, "heart created for a <3 note")
eq(friendsScroll.buttons[1].HelloUIHeart:IsShown(), true, "heart shown")
ok(friendsScroll.buttons[2].HelloUIHeart == nil
   or friendsScroll.buttons[2].HelloUIHeart:IsShown() == false,
   "no heart on a friend without <3")

----------------------------------------------------------------------
-- Combat deferral
----------------------------------------------------------------------

print("\ncombat deferral")
inCombat = true
ns.Config:SetChar("barsOff", { bar1 = true })
ns:ApplyAllWhenSafe()
eq(_G.MainActionBar._alpha, 1, "protected work deferred while in combat")
inCombat = false
fire("PLAYER_REGEN_ENABLED")
eq(_G.MainActionBar._alpha, 0, "deferred work drained after combat")
ns.Config:ClearChar("barsOff")
ns:ApplyAll()

----------------------------------------------------------------------
-- Master switch and slash commands
----------------------------------------------------------------------

print("\nmaster switch")
_G.SlashCmdList["HELLOUI"]("off")
eq(ns.Config:Get("enabled"), false, "/hui off disables")
eq(_G.ActionButton1.HotKey._alpha, 1, "keybind text restored when disabled")
eq(cvars.xpBarText, "0", "xpBarText restored to its original value when disabled")
eq(healthBar.lockColor, nil, "lockColor handed back to Blizzard when disabled")
eq(_G.GameTimeFrame:IsShown(), true, "time-of-day dial shown again when disabled")
eq(_G.PlayerFrameTexture._desat, false, "darkmode restored when disabled")
eq(_G.ActionButton1:GetNormalTexture()._alpha, 0.5, "button border back to Blizzard's 0.5")
eq(mainMenuBar:IsShown(), true, "bar art restored when disabled")
eq(chat:GetWidth(), 400, "chat still untouched")

_G.SlashCmdList["HELLOUI"]("on")
eq(ns.Config:Get("enabled"), true, "/hui on re-enables")
eq(_G.ActionButton1.HotKey._alpha, 0, "keybind text hidden again")

print("\nslash commands")
for _, cmd in ipairs({ "", "status", "apply", "char", "char clear", "char barsoff bar3", "char barsoff nonsense", "help", "reset" }) do
    local success, err = pcall(_G.SlashCmdList["HELLOUI"], cmd)
    ok(success, ("/hui %s runs without error%s"):format(cmd, success and "" or ": " .. tostring(err)))
end

print("\nper-character overrides")
ns.Config:SetChar("hideKeybindText", false)
ns:ApplyAll()
eq(_G.ActionButton1.HotKey._alpha, 1, "character override beats the account setting")
ok(ns.Config:HasAnyCharOverride(), "override recorded")
ns.Config:ResetChar()
ns:ApplyAll()
eq(_G.ActionButton1.HotKey._alpha, 0, "clearing overrides falls back to the account setting")

----------------------------------------------------------------------
-- Regressions
--
-- One case per bug found in review. Each of these failed on the code as it
-- was first written, so they are the reason this section exists rather than
-- decoration.
----------------------------------------------------------------------

print("\nregressions")

-- The hooks the addon claims to install are actually installed.
ok(hooks["ToggleMinimap"], "ToggleMinimap hooked (re-hides the dial after a toggle)")
ok(hooks["FriendsFrame_UpdateFriendButton"], "friends list update hooked")
ok(hooks["Show"], "GameTimeFrame:Show hooked (catches other addons showing it)")

-- barsOff is authoritative now: a bar absent from it is shown, even if the
-- player's own Blizzard setting had it hidden. That reversal is only
-- acceptable because the original is remembered and handed back, so this is
-- the test that matters.
settingValues["PROXY_SHOW_ACTIONBAR_3"] = false
HelloUIDB.proxyOriginals = {}
ns:ApplyAll()
eq(settingValues["PROXY_SHOW_ACTIONBAR_3"], true,
    "barsOff is authoritative - an absent bar is shown")
eq(HelloUIDB.proxyOriginals.bar3, false, "and the player's original value is remembered")

-- ...and switching the addon off hands it straight back.
ns.Config:Set("enabled", false)
ns:ApplyAll()
eq(settingValues["PROXY_SHOW_ACTIONBAR_3"], false,
    "/hui off restores the player's own bar visibility")
ns.Config:Set("enabled", true)
ns:ApplyAll()
eq(settingValues["PROXY_SHOW_ACTIONBAR_3"], true, "and re-enabling re-applies")
settingValues["PROXY_SHOW_ACTIONBAR_3"] = true

-- Unticking a nested checkbox must store false, not delete the key: Config's
-- applyDefaults recurses into these tables and would resurrect the default on
-- the next login.
local barBox = _G["HelloUIOptBarOffbar5"]
barBox:SetChecked(false)
barBox:GetScript("OnClick")(barBox)
eq(HelloUIDB.barsOff.bar5, false, "unticking stores a real false")
ns.Config:Init()  -- stands in for the next login
eq(HelloUIDB.barsOff.bar5, false, "and it survives applyDefaults on the next login")
barBox:SetChecked(true)
barBox:GetScript("OnClick")(barBox)
eq(HelloUIDB.barsOff.bar5, true, "re-ticking stores true")

-- An existing install carries the OLD profile-derived bar set. applyDefaults
-- only fills in missing keys, so changing the default could not remove a
-- saved `bar5 = true` - it just added 6/7/8 on top and the player watched
-- bars 5 through 8 all go dark. This is that exact database.
do
    HelloUIDB = { barsOff = { bar5 = true } }
    ns.Config:Init()
    eq(HelloUIDB.barsOff.bar5, nil, "migration clears the old profile-derived bar5")
    eq(HelloUIDB.barsOff.bar6, true, "and installs the base set")
    ok(HelloUIDB.barsBaseV2 == true, "latched so it runs once")

    -- Second login must not touch a deliberate change made since.
    HelloUIDB.barsOff.bar5 = true
    ns.Config:Init()
    eq(HelloUIDB.barsOff.bar5, true, "a later change is not re-migrated away")
    ns.Config:ResetAccount()
end

-- The bar-set migration must not re-run after /hui reset, or it wipes any
-- bar the player changed since.
do
    ns.Config:ResetAccount()
    ok(HelloUIDB.barsBaseV2 == true, "reset marks the bar migration done")
    HelloUIDB.barsOff.bar2 = true
    ns.Config:Init()
    eq(HelloUIDB.barsOff.bar2, true, "a bar hidden after a reset survives the next login")
    HelloUIDB.barsOff.bar2 = nil
end

-- The remembered xpBarText must live in saved variables, or a /reload makes
-- the addon restore its own value instead of the player's.
cvars.xpBarText = "0"
HelloUIDB.xpBarTextOriginal = nil
ns:ApplyAll()
eq(cvars.xpBarText, "1", "xpBarText set")
eq(HelloUIDB.xpBarTextOriginal, "0", "the player's original is persisted")
-- Simulate a reload: file-locals are gone, saved variables are not.
ns.Config:Init()
ns:ApplyAll()
eq(HelloUIDB.xpBarTextOriginal, "0", "the original survives a reload")
ns.Config:Set("alwaysShowBarText", false)
ns:ApplyAll()
eq(cvars.xpBarText, "0", "disabling restores the player's value, not ours")
ns.Config:Set("alwaysShowBarText", true)
ns:ApplyAll()

-- The time-of-day dial must not be Shown while the minimap itself is hidden.
_G.Minimap:Hide()
ns.Config:Set("hideTimeOfDay", false)
ns:ApplyAll()
eq(_G.GameTimeFrame:IsShown(), false, "dial stays hidden while the minimap is toggled away")
_G.Minimap:Show()
ns:ApplyAll()
eq(_G.GameTimeFrame:IsShown(), true, "dial comes back with the minimap")
ns.Config:Set("hideTimeOfDay", true)
ns:ApplyAll()

-- Friends: the scroll frame is reached by its global name. If this regresses
-- to FriendsListFrame.ScrollFrame the repaint silently does nothing.
friendsScroll.buttons[1].name._color = nil
ns.Friends:Refresh()
ok(friendsScroll.buttons[1].name._color ~= nil, "Friends:Refresh reaches the visible rows")

-- An offline friend must keep Blizzard's grey, not be repainted blue.
ok(friendsScroll.buttons[2].name._color == nil,
    "an offline friend is left with Blizzard's own colour")

-- Bar 1's page-scroll arrows live in a child frame, not in ActionButton1..12,
-- and alpha 0 does not stop them taking clicks.
local pageNumber = Frame.new(nil, _G.MainActionBar)
ns.Config:SetChar("barsOff", { bar1 = true })
ns:ApplyAll()
eq(pageNumber._mouse, false, "bar1's child frames are made non-interactive too")
ns.Config:ClearChar("barsOff")
ns:ApplyAll()
eq(pageNumber._mouse, true, "and interactive again afterwards")

----------------------------------------------------------------------

failures = failures + (_G._addonErrors or 0)
print(("\n%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
