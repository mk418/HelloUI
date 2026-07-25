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
_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) _G._lastPrint = msg end }
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
for i = 0, 3 do _G["MainMenuBarTexture" .. i] = _G.UIParent:CreateTexture("MainMenuBarTexture" .. i) end
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
local friendsList = Frame.new("FriendsListFrame", _G.UIParent)
friendsList.ScrollFrame = Frame.new(nil, friendsList)
friendsList.ScrollFrame.buttons = {}
for i = 1, 2 do
    local b = Frame.new(nil, friendsList)
    b.index = i
    b.id = i
    b.buttonType = _G.FRIENDS_BUTTON_TYPE_WOW
    b.name = b:CreateFontString()
    b.gameIcon = Frame.new(nil, b)
    friendsList.ScrollFrame.buttons[i] = b
end

----------------------------------------------------------------------
-- Load the addon in TOC order
----------------------------------------------------------------------

local ns = {}
local FILES = {
    "Core.lua", "Config.lua", "Buttons.lua", "Bars.lua", "StatusBars.lua",
    "Player.lua", "Darkmode.lua", "Minimap.lua", "Chat.lua", "Friends.lua",
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

----------------------------------------------------------------------
-- Assertions: bars
--
-- The default switches off the physical bar the old profile had off, which is
-- MultiBarLeft. Blizzard calls that bar 5, so the proxy touched must be
-- PROXY_SHOW_ACTIONBAR_5 and every other proxy must be untouched.
----------------------------------------------------------------------

print("\nbars")
eq(settingValues["PROXY_SHOW_ACTIONBAR_5"], false, "bar5 (MultiBarLeft) switched off natively")
eq(settingValues["PROXY_SHOW_ACTIONBAR_4"], true, "bar4 (MultiBarRight) left alone")
eq(settingValues["PROXY_SHOW_ACTIONBAR_2"], true, "bar2 left alone")
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

print("\nchat")
local p, _, rp, cx, cy = chat:GetPoint(1)
eq(p, "BOTTOMLEFT", "chat anchored BOTTOMLEFT")
eq(rp, "BOTTOMLEFT", "chat anchored to UIParent BOTTOMLEFT")
eq(cx, 42, "chat x")
eq(cy, 35, "chat y")
eq(chat:GetWidth(), 460, "chat width")
eq(chat:GetHeight(), 207, "chat height")

print("\ndarkmode")
eq(_G.PlayerFrameTexture._desat, true, "player frame art desaturated")
local dr, dg, db = _G.PlayerFrameTexture:GetVertexColor()
ok(dr == 0.4 and dg == 0.4 and db == 0.4, "player frame art tinted 0.4 grey")
eq(_G.MainMenuBarTexture0._desat, true, "action bar art desaturated")
eq(cluster.BorderTop._desat, true, "minimap header art desaturated")

print("\nfriends")
ns.Friends:Refresh()
local aliceColor = friendsList.ScrollFrame.buttons[1].name._color
ok(aliceColor and aliceColor[1] == 0.41, "online mage friend class-coloured")
ok(friendsList.ScrollFrame.buttons[1].HelloUIHeart ~= nil, "heart created for a <3 note")
eq(friendsList.ScrollFrame.buttons[1].HelloUIHeart:IsShown(), true, "heart shown")
ok(friendsList.ScrollFrame.buttons[2].HelloUIHeart == nil
   or friendsList.ScrollFrame.buttons[2].HelloUIHeart:IsShown() == false,
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

_G.SlashCmdList["HELLOUI"]("on")
eq(ns.Config:Get("enabled"), true, "/hui on re-enables")
eq(_G.ActionButton1.HotKey._alpha, 0, "keybind text hidden again")

print("\nslash commands")
for _, cmd in ipairs({ "", "status", "apply", "char", "char clear", "chat", "help", "reset" }) do
    local success, err = pcall(_G.SlashCmdList["HELLOUI"], cmd)
    ok(success, ("/hui %s runs without error%s"):format(cmd, success and "" or ": " .. tostring(err)))
end

-- chat save must capture wherever the frame currently is
chat:ClearAllPoints()
chat:SetPoint("BOTTOMLEFT", _G.UIParent, "BOTTOMLEFT", 99, 88)
chat:SetSize(500, 250)
_G.SlashCmdList["HELLOUI"]("chat save")
eq(ns.Config:Get("chatX"), 99, "chat save captured x")
eq(ns.Config:Get("chatHeight"), 250, "chat save captured height")

print("\nper-character overrides")
ns.Config:SetChar("hideKeybindText", false)
ns:ApplyAll()
eq(_G.ActionButton1.HotKey._alpha, 1, "character override beats the account setting")
ok(ns.Config:HasAnyCharOverride(), "override recorded")
ns.Config:ResetChar()
ns:ApplyAll()
eq(_G.ActionButton1.HotKey._alpha, 0, "clearing overrides falls back to the account setting")

----------------------------------------------------------------------

print(("\n%d checks, %d failures"):format(checks, failures))
os.exit(failures == 0 and 0 or 1)
