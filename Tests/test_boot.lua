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
    "SetFrameStrata", "SetFrameLevel", "SetJustifyV", "SetSpacing", "SetMinMaxValues", "SetValueStep", "SetValue",
    "SetObeyStepOnDrag", "SetOwner", "AddLine", "SetTexCoord", "SetDrawLayer",
    "RegisterForClicks", "RegisterForDrag", "SetMovable", "SetClampedToScreen",
    "SetUserPlaced", "SetToplevel", "SetFont", "GetFont",
    "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture",
    "SetAttribute", "SetID", "GetID", "Raise", "Lower",
    "SetHitRectInsets", "SetIgnoreParentAlpha", "SetPropagateMouseClicks",
}
for _, name in ipairs(NOOP_METHODS) do
    Frame[name] = function() end
end

-- Recorded rather than no-op'd. SetAllPoints is how the cast bar's backdrop
-- covers its frame, and a no-op version would let "the backdrop exists" pass for
-- a texture covering nothing; SetColorTexture is the only thing that
-- distinguishes it from an unpainted region.
function Frame:SetAllPoints(rel)
    self._points = { { p = "ALLPOINTS", rel = rel or self._parent } }
end
function Frame:SetColorTexture(r, g, b, a) self._color = { r, g, b, a } end
-- Real, because "is this widget inside the scroll frame" is the assertion that
-- keeps the options panel from overflowing the Settings canvas again.
function Frame:SetScrollChild(c) self._scrollChild = c end
function Frame:GetScrollChild() return self._scrollChild end
function Frame:GetJustifyH() return self._justify end
-- Recorded: the cast bar's spell name is shrunk to stop its ink standing proud
-- of a 13px bar, so "which font object" is the whole assertion.
function Frame:SetFontObject(f) self._font = f end
function Frame:GetFontObject() return self._font end
function Frame:SetWordWrap(v) self._wrap = v and true or false end
function Frame:SetMaxLines(n) self._maxLines = n end
function Frame:SetJustifyH(v) self._justify = v end

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
-- Real, and it exists to make a rule enforceable rather than because the addon
-- calls it. Darkmode is forbidden from enumerating Minimap's children; without
-- GetRegions a sweep that walked them would reach no textures in the harness
-- and the regression test for that rule could not fail.
function Frame:GetRegions() return unpackf(self._regions or {}) end
function Frame:GetNumRegions() return #(self._regions or {}) end
function Frame:SetSize(w, h) self._w, self._h = w, h end
-- Real, not no-ops: the status bar width and tracking-icon features read
-- these back. Anything stubbed here can let a feature "pass" while doing
-- nothing at all, which has happened twice.
function Frame:SetWidth(w) self._w = w end
function Frame:SetHeight(h) self._h = h end
function Frame:SetParent(p) self._parent = p end
function Frame:GetWidth() return self._w end
function Frame:GetHeight() return self._h end
function Frame:SetScale(sc) self._scale = sc end
function Frame:GetScale() return self._scale or 1 end
function Frame:GetEffectiveScale()
    -- Effective scale is own scale times the parent chain's.
    local sc = self._scale or 1
    local p = self._parent
    while p do sc = sc * (p._scale or 1); p = p._parent end
    return sc
end
-- Real screen rects for the frames whose geometry a feature actually reads
-- back. The tracking-button fix is polar - it measures how far the LFG eye
-- sits from the map's centre - so a GetLeft that answers 0 for everything
-- would put every frame at the same point and let any placement pass.
function Frame:SetRect(l, b, w, h) self._left, self._bottom, self._w, self._h = l, b, w, h end
function Frame:GetLeft() return self._left or 0 end
function Frame:GetBottom() return self._bottom or 0 end
function Frame:GetCentre()
    return (self._left or 0) + (self._w or 0) / 2, (self._bottom or 0) + (self._h or 0) / 2
end
function Frame:ClearAllPoints() self._points = {} end
-- Accumulates, like the real one. It used to replace, which is wrong in a way
-- that matters: a frame anchored LEFT and then RIGHT (how the cast bar's spell
-- name is stretched across its bar) reported only the RIGHT point, and
-- GetPoint(1) is documented to return the FIRST anchor set. Every call site in
-- the addon clears before it re-anchors, so accumulating is also what they mean.
function Frame:SetPoint(p, rel, relPoint, x, y)
    self._points[#self._points + 1] =
        { p = p, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
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
    t.GetTexture = function(s) return s._tex end
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
_G.Enum.EditModeSystem = { ActionBar = 1, UnitFrame = 2, Minimap = 3, StatusTrackingBar = 4, CastBar = 5, ChatFrame = 6 }
_G.Enum.EditModeMinimapSetting = { HeaderUnderneath = 0, RotateMinimap = 1, Size = 2 }
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
            -- A system HelloUI never positions, as the control for "we leave
            -- everything else exactly as Blizzard had it".
            table.insert(systems, { system = 2, systemIndex = nil,
                anchorInfo = { point = "TOPLEFT", relativeTo = "UIParent", relativePoint = "TOPLEFT", offsetX = 0, offsetY = 0 },
                settings = {}, isInDefaultPosition = true })
            -- ChatFrame and Minimap: systems with settings directly.
            table.insert(systems, { system = 6, systemIndex = nil,
                anchorInfo = { point = "BOTTOMLEFT", relativeTo = "UIParent", relativePoint = "BOTTOMLEFT", offsetX = 0, offsetY = 0 },
                settings = {}, isInDefaultPosition = true })
            -- CastBar: a system with settings directly, so systemIndex nil.
            table.insert(systems, { system = 5, systemIndex = nil,
                anchorInfo = { point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", offsetX = 0, offsetY = 0 },
                settings = { { setting = 1, value = 0 } }, isInDefaultPosition = true })
            table.insert(systems, { system = 3, systemIndex = nil,
                anchorInfo = { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", offsetX = 0, offsetY = 0 },
                settings = { { setting = 2, value = 5 } }, isInDefaultPosition = true })
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
    -- Twelve buttons at a 38px pitch, less the trailing padding.
    bar:SetSize(454, 36)
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
-- Container plus its two inner bars, shaped like the real thing: the inner
-- StatusBar carries its own explicit width and does NOT follow its parent.
do
    local container = Frame.new(nil, _G.StatusTrackingBarManager)
    container:SetSize(1024, 13)
    -- The border art: a fixed chain anchored left-to-right that does NOT
    -- follow the frame. Standalone is 16+240+256+256+256 = 1024.
    for key, w in pairs({ StandaloneFrameTexture1 = 16, StandaloneFrameTexture2 = 240,
                          StandaloneFrameTexture3 = 256, StandaloneFrameTexture4 = 256,
                          StandaloneFrameTexture5 = 256 }) do
        local t = container:CreateTexture()
        t:SetSize(w, 13)
        container[key] = t
    end
    container.bars = {}
    for _, idx in ipairs({ 1, 4 }) do
        local bar = Frame.new(nil, container)
        bar:SetSize(1024, 13)
        bar.StatusBar = Frame.new(nil, bar)
        bar.StatusBar:SetSize(1024, 8)
        container.bars[idx] = bar
    end
    _G.StatusTrackingBarManager.barContainers = { container }
    _G.StatusTrackingBarManager.UpdateBarVisuals = function() end
    _G._statusContainer = container
end

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

-- MinimapBackdrop and its occupants, as the client has them. MiniMapTracking
-- is declared with NO parent in the vanilla file - that is the bug - and
-- LFGMinimapFrame sits at TOPLEFT (25,-28), which the naive fix collides with.
local backdrop = Frame.new("MinimapBackdrop", minimap)
local lfg = Frame.new("LFGMinimapFrame", backdrop)
lfg:SetSize(33, 33)
lfg:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 25, -28)

-- The rects `/hui minimapprobe` printed in game, so the placement arithmetic is
-- tested against what the client really reports rather than against the numbers
-- the XML implies. The map is 140 wide, so its rim is 70 out from the centre,
-- and the LFG eye rides that rim at 75.
--
-- The SIZES here are the XML's, not the probe's: the probe prints with %d, which
-- truncated the eye's 33 to 32 and the backdrop's 192 to 191. Carrying the
-- truncation into the stub would make "the tracking button has the same hit rect
-- as the eye" - which is true in the client, both are 33x33 - unassertable.
minimap:SetRect(1220, 613, 140, 140)
backdrop:SetRect(1194, 587, 192, 192)
lfg:SetRect(1219, 718, 33, 33)

-- The eye's ring. 52x52 at TOPLEFT (1,-1), which is also what MiniMapMailBorder,
-- MiniMapBattlefieldBorder and MiniMapWorldBorder declare - the house size for a
-- minimap button ring on a 33x33 frame.
local lfgBorder = lfg:CreateTexture("LFGMinimapFrameBorder")
lfgBorder:SetSize(52, 52)
lfgBorder:SetPoint("TOPLEFT", lfg, "TOPLEFT", 1, -1)

-- The rest of Blizzard's gold on the rim and in the header. Mail and
-- battlefield are hidden until mail arrives or a queue starts, which is exactly
-- why their textures have to be tintable while hidden.
local mailFrame = Frame.new("MiniMapMailFrame", backdrop)
mailFrame:Hide()
local mailBorder = mailFrame:CreateTexture("MiniMapMailBorder")
local bfFrame = Frame.new("MiniMapBattlefieldFrame", backdrop)
bfFrame:Hide()
local bfBorder = bfFrame:CreateTexture("MiniMapBattlefieldBorder")
local northTag = backdrop:CreateTexture("MinimapNorthTag")
local compass = backdrop:CreateTexture("MinimapCompassTexture")
local toggleButton = Frame.new("MinimapToggleButton", cluster)
do
    local n, p = toggleButton:CreateTexture(), toggleButton:CreateTexture()
    toggleButton.GetNormalTexture = function() return n end
    toggleButton.GetPushedTexture = function() return p end
    toggleButton._normal, toggleButton._pushed = n, p
end

-- A sibling addon's minimap button, as HelloGear/HelloLog/HelloStock/
-- HelloWorldBuffs really build one: a named Button parented to Minimap whose
-- gold ring is an ANONYMOUS texture. Present so the "never enumerate" rule has
-- something to be broken against - a children sweep would reach this ring, and
-- greying four siblings' buttons is the regression the rule exists to prevent.
local siblingButton = Frame.new("HelloGearMinimapButton", minimap)
local siblingRing = siblingButton:CreateTexture()

-- And a live-state texture of the kind HelloWarrior and HelloTotems keep on
-- their own buttons: desaturation here is a signal (out of range, empty slot),
-- so a second pass over it corrupts something read mid-fight.
local liveStateIcon = Frame.new("HelloTotemsSlot1", _G.UIParent):CreateTexture()
liveStateIcon:SetDesaturated(true)
liveStateIcon:SetVertexColor(1, 0.4, 0.4, 1)
-- Deliberately given a parent already. A guard that skipped the fix when the
-- frame "looked parented" is what made the icon vanish a second time, so the
-- reparent has to happen regardless of what it is attached to.
local strayParent = Frame.new("SomeOtherFrame", _G.UIParent)
local tracking = Frame.new("MiniMapTracking", strayParent)
tracking:SetSize(33, 33)
tracking:SetPoint("TOPLEFT", strayParent, "TOPLEFT", 11, -26)
-- Blizzard's XML default: hidden, and only ever shown from
-- MINIMAP_UPDATE_TRACKING - which does not fire for tracking that was already
-- active at login.
tracking:Hide()

-- Both of its regions, at their real declared geometry, so the test starts from
-- the bug rather than from a blank frame. The ring is the same texture file as
-- the eye's at 64x64 instead of 52x52, which is the whole defect; the icon is
-- 24x24 with a CENTER (2,-2) nudge that exists only to cancel where a 64 ring
-- anchored flush at (0,0) puts the hole.
--
-- Real CreateTexture regions, not Frame.new: an un-sized stub reports the
-- Frame.new default 100x20, so a fix deriving the icon from the live size would
-- compute 81.25 here and 19.5 in game, and the restore path would record 100x20
-- as "Blizzard's original".
local trackingBorder = tracking:CreateTexture("MiniMapTrackingBorder")
trackingBorder:SetSize(64, 64)
trackingBorder:SetPoint("TOPLEFT", tracking, "TOPLEFT", 0, 0)
local trackingIcon = tracking:CreateTexture("MiniMapTrackingIcon")
trackingIcon:SetSize(24, 24)
trackingIcon:SetPoint("CENTER", tracking, "CENTER", 2, -2)
_G.GetTrackingTexture = function() return 135725 end

-- The clock, inside a minimap subtree scaled to 110% - which is what makes
-- its text render soft, and what rounding the anchor alone cannot fix.
minimap:SetScale(1.1)
local clockBtn = Frame.new("TimeManagerClockButton", backdrop)
local clockText = Frame.new("TimeManagerClockTicker", clockBtn)
clockText:SetPoint("CENTER", clockBtn, "CENTER", 3, 1.5)

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
-- Blizzard's own switch for "another bar is replacing this one". ShouldShowCastBar
-- is `self.showCastbar and self.unit ~= nil`, and every path that would show the
-- bar goes through it, so the flag IS the behaviour - modelling it as a flag is
-- faithful rather than a simplification.
pcb:SetSize(195, 13)
pcb.Text = pcb:CreateFontString("PlayerCastingBarFrameText")
-- Blizzard's declared state: GameFontHighlight in a region 185x16, inside a bar
-- that is 13 tall. That mismatch IS the overspill bug.
pcb.Text:SetFontObject("GameFontHighlight")
pcb.Text:SetSize(185, 16)
pcb.Text:SetPoint("CENTER", pcb, "CENTER", 0, 0)
pcb.Flash = pcb:CreateTexture()
pcb.BorderShield = pcb:CreateTexture()
pcb.BorderShield:Hide()
-- The declared files, because blanking a texture is how the border art is
-- suppressed and putting it back means knowing what it was.
pcb.Border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border")
pcb.BorderShield:SetTexture("Interface\\CastingBar\\UI-CastingBar-Small-Shield")
pcb.Flash:SetTexture("Interface\\CastingBar\\UI-CastingBar-Flash")
-- The mixin re-applies a per-bar-type colour on every cast and state change,
-- which is the one thing here that fights a tint set once.
pcb._barColor = { 1, 0.7, 0 }
pcb.SetStatusBarColor = function(self, r, g, b) self._barColor = { r, g, b } end
pcb.GetStatusBarColor = function(self) return self._barColor[1], self._barColor[2], self._barColor[3] end
pcb.UpdateBarFillTexture = function(self) self:SetStatusBarColor(1, 0.7, 0) end
-- CastingBarMixin:SetLook("CLASSIC") rebuilds the appearance from scratch and is
-- run from PlayerFrame_DetachCastBar on every Edit Mode layout update. Modelled
-- faithfully, because it undoes three separate parts of the style at once and
-- that is exactly the bug this stub exists to catch.
pcb.SetLook = function(self)
    self.Border:SetTexture("Interface\\CastingBar\\UI-CastingBar-Border")
    self.Text:ClearAllPoints()
    self.Text:SetWidth(185)
    self.Text:SetHeight(16)
    self.Text:SetPoint("TOP", self, "TOP", 0, 5)
    self.Text:SetFontObject("GameFontHighlight")
end
pcb.showCastbar = true
pcb.SetAndUpdateShowCastbar = function(self, show) self.showCastbar = show and true or false end
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
    "Player.lua", "Darkmode.lua", "Minimap.lua", "CastBar.lua", "Friends.lua",
    "Layout.lua", "Options.lua",
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

-- The list above must BE the TOC, not merely resemble it. A file added to the
-- addon and forgotten here loads in game and is never exercised offline - the
-- suite stays green while a whole module goes untested, which is exactly what
-- happened when CastBar.lua was added.
do
    local toc, missing = io.open("HelloUI.toc"), {}
    if not toc then
        ok(false, "HelloUI.toc readable")
    else
        local listed = {}
        for _, f in ipairs(FILES) do listed[f] = true end
        for line in toc:lines() do
            local file = line:match("^%s*([%w_]+%.lua)%s*$")
            if file and not listed[file] then missing[#missing + 1] = file end
        end
        toc:close()
        ok(#missing == 0, ("every file in the TOC is loaded by the harness%s"):format(
            #missing > 0 and (" - missing " .. table.concat(missing, ", ")) or ""))
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

print("\nstatus bar width")
do
    local c = _G._statusContainer
    eq(c:GetWidth(), 454, "container narrowed to the action bar stack width")

    -- The frame alone is not enough: the border art is a separate fixed chain
    -- and leaving it at 1024 is what made Edit Mode look right while the bar
    -- on screen was still full width.
    local artTotal = 0
    for _, key in ipairs({ "StandaloneFrameTexture1", "StandaloneFrameTexture2",
                           "StandaloneFrameTexture3", "StandaloneFrameTexture4",
                           "StandaloneFrameTexture5" }) do
        artTotal = artTotal + c[key]:GetWidth()
    end
    ok(math.abs(artTotal - 454) < 1,
        ("border art spans the frame, not 1024 (got %.1f)"):format(artTotal))
    -- Proportions preserved: the 16px left cap stays 16/1024 of the total.
    ok(math.abs(c.StandaloneFrameTexture1:GetWidth() - 454 * 16 / 1024) < 0.5,
        "art segments scaled proportionally, not stretched unevenly")
    for _, bar in pairs(c.bars) do
        eq(bar:GetWidth(), 454, "inner bar narrowed")
        -- The inner StatusBar has its own explicit width and is anchored only
        -- at RIGHT, so it does not follow the parent and must be set too.
        eq(bar.StatusBar:GetWidth(), 454, "inner StatusBar narrowed")
        eq(bar.StatusBar:GetHeight(), 8, "height untouched - this is not a scale")
    end
    ok(ns.StatusBars.hookedVisuals, "UpdateBarVisuals hooked so Blizzard cannot undo it")

    -- Scale awareness. UpdateBarVisuals calls SetScale on the manager, so a
    -- width in the container's own coordinate space is not that many screen
    -- pixels: at 1.4 a naive 454 draws 636 wide and overshoots the stack.
    -- The width must convert through effective scales.
    c.GetEffectiveScale = function() return 1.4 end
    ns.StatusBars:Apply()
    local want = 454 / 1.4
    ok(math.abs(c:GetWidth() - want) < 0.5,
        ("scaled container asks for %.1f, not a naive 454 (got %.1f)"):format(want, c:GetWidth()))
    ok(math.abs(c:GetWidth() * 1.4 - 454) < 1,
        "so it renders the same screen width as the stack")
    c.GetEffectiveScale = function() return 1 end
    ns.StatusBars:Apply()
    eq(c:GetWidth(), 454, "and back to 454 at scale 1")
    -- Blizzard re-running its own pass must not widen them again.
    _G.StatusTrackingBarManager:UpdateBarVisuals()
    eq(c:GetWidth(), 454, "still narrow after Blizzard refreshes the bars")
end

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
        elseif e.system == 2 then
            minimapSystem = e
        end
    end
    eq(bars, 11, "every action bar system carried over from the preset")
    eq(moved, 10, "every action bar we position is flagged as moved")
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

    -- Bars 6-8 ship switched off, but must still be positioned: Blizzard's
    -- preset parks them in the middle of the screen, so an unpositioned bar
    -- lands across the player's view the moment it is enabled.
    for _, idx in ipairs({ 6, 7, 8 }) do
        local e
        for _, entry in ipairs(sys) do
            if entry.system == 1 and entry.systemIndex == idx then e = entry end
        end
        ok(e ~= nil and e.anchorInfo.relativeTo == "UIParent",
            ("bar %d positioned even though it ships off"):format(idx))
        ok(e ~= nil and e.anchorInfo.relativePoint == "BOTTOM",
            ("bar %d anchored to the bottom, not screen centre"):format(idx))
    end

    -- Size stays at 100%: it is a SCALE, so using it to narrow the bar
    -- squashed the height too. Width is set directly instead - see the
    -- status bar width regression below.
    for _, e in ipairs(sys) do
        if e.system == 4 then
            local statusSize
            for _, st in ipairs(e.settings) do
                if st.setting == 0 then statusSize = st.value end
            end
            eq(statusSize, 10, "status bar left at 100% scale, so full height")
        end
    end

    -- The cast bar is parked above the bars, not at screen centre, and is
    -- explicitly unlocked from the player frame so the anchor is honoured.
    local cast
    for _, e in ipairs(sys) do
        if e.system == 5 then cast = e end
    end
    ok(cast ~= nil, "cast bar found")

    -- The chat frame is lifted clear of the bottom-left flank block, which
    -- occupies exactly where Blizzard parks chat once bar 5 is switched on.
    local chat6
    for _, e in ipairs(sys) do
        if e.system == 6 then chat6 = e end
    end
    ok(chat6 ~= nil, "chat frame positioned in the layout")
    ok(chat6 and chat6.anchorInfo.offsetY > 24 + 38 * 3,
        "chat sits above the flank block, not underneath it")

    -- The minimap is nudged one slider step larger: raw 5 is 100%, raw 6 110%.
    local map
    for _, e in ipairs(sys) do
        if e.system == 3 then map = e end
    end
    do
        local msize
        for _, st in ipairs((map and map.settings) or {}) do
            if st.setting == 2 then msize = st.value end
        end
        eq(msize, 6, "minimap one step larger than the preset's 100%")
    end

    -- The bar-1 paging arrows, via Blizzard's own HideBarScrolling, and only
    -- on the main bar since it is the only one carrying that setting.
    local scrolling, otherHasScrolling = nil, false
    for _, e in ipairs(sys) do
        if e.system == 1 then
            for _, st in ipairs(e.settings) do
                if st.setting == 8 then
                    if e.systemIndex == 1 then scrolling = st.value
                    else otherHasScrolling = true end
                end
            end
        end
    end
    eq(scrolling, 1, "bar 1's paging arrows hidden")
    ok(not otherHasScrolling, "and HideBarScrolling written only on the main bar")
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

    -- Empty slots are a setting: on keeps the block shape, off lets Blizzard
    -- hide unfilled slots so an empty bar vanishes rather than showing a grid.
    local alwaysShow
    for _, st in ipairs(mainBar.settings) do
        if st.setting == 9 then alwaysShow = st.value end
    end
    eq(alwaysShow, 1, "empty slots shown by default, so bars keep their shape")
    ns.Config:Set("showEmptyButtons", false)
    local sys2 = ns.Layout:Build()
    ns.Config:Set("showEmptyButtons", true)
    local off
    for _, e in ipairs(sys2) do
        if e.system == 1 and e.systemIndex == 1 then
            for _, st in ipairs(e.settings) do
                if st.setting == 9 then off = st.value end
            end
        end
    end
    eq(off, 0, "and the setting actually turns them off")
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

print("\nminimap fixes")
do
    -- Blizzard leaves MiniMapTracking parentless, so it strands itself in the
    -- screen corner. It must end up on the minimap backdrop.
    eq(tracking:GetParent(), backdrop,
        "reparented onto the backdrop even though it already had a parent")
    local p, rel, rp, tx, ty = tracking:GetPoint(1)
    eq(rel, minimap, "placed against the map's centre, the only fixed point on a circle")
    ok(p == "CENTER" and rp == "CENTER", "centre to centre, so the offset IS the polar vector")

    -- The assertion the last attempt would have failed. Dropping straight down
    -- from the LFG eye cuts the chord: 75 out becomes 57 on a map whose rim is
    -- at 70, which draws the button on the map instead of on its edge.
    local mx, my = minimap:GetCentre()
    local lx, ly = lfg:GetCentre()
    local mapR = minimap:GetWidth() / 2
    local lfgR = math.sqrt((lx - mx) ^ 2 + (ly - my) ^ 2)
    local trackR = math.sqrt(tx * tx + ty * ty)
    ok(trackR > mapR,
        ("outside the map's own artwork (%.0f out, rim at %.0f)"):format(trackR, mapR))
    ok(math.abs(trackR - lfgR) < 0.5,
        ("on exactly the LFG eye's circle (%.0f vs %.0f), because rotation preserves radius")
            :format(trackR, lfgR))

    -- Below the eye, and PACKED against it. The first version of this asserted
    -- a full 33-unit frame width of separation, which is the gap the user then
    -- complained about: the frames are 33 but the visible gold ring is only
    -- about 26.5, so frame-tangent still reads as a hole. The rim's twelve
    -- buttons sit a median 24.9 units apart, essentially touching, and that
    -- measured pitch is the target.
    local ldx, ldy = lx - mx, ly - my
    ok(ty < ldy, "below the LFG eye, which is the direction that was asked for")
    local gap = math.sqrt((tx - ldx) ^ 2 + (ty - ldy) ^ 2)
    ok(gap > 22 and gap < 28,
        ("packed against the eye like the rim's own buttons (%.1f units apart, they sit 24.9)"):format(gap))

    -- The ring's SIZE, which is a separate defect from its position: the same
    -- texture file that the eye declares 52x52 is declared 64x64 here, on an
    -- identically-sized 33x33 frame.
    --
    -- Asserted against the eye's own live value rather than the literal 52, since
    -- "match the LFG icon" is what was asked. A fix hard-coding 52 passes an
    -- `== 52` check even when the thing it is supposed to match is not 52.
    eq(trackingBorder:GetWidth(), lfgBorder:GetWidth(), "ring matches the LFG eye's ring")
    eq(trackingBorder:GetHeight(), lfgBorder:GetHeight(), "on both axes")

    -- Size without the anchor slides the ring off the icon, because the ring art
    -- is not centred in its own texture.
    local bp, brel, brp, bx, by = trackingBorder:GetPoint(1)
    eq(brel, tracking, "ring anchored to its own button")
    ok(bp == "TOPLEFT" and brp == "TOPLEFT", "by its top left, as Blizzard declares it")
    local _, _, _, lbx, lby = lfgBorder:GetPoint(1)
    ok(bx == lbx and by == lby,
        ("at the eye's own inset (%s,%s), so the ring sits where the eye's does"):format(tostring(bx), tostring(by)))

    -- The aperture shrinks with the ring, so a 24px icon would overflow it.
    eq(trackingIcon:GetWidth(), 24 * lfgBorder:GetWidth() / 64, "icon scaled by the same factor")
    local ip, irel, irp, ix, iy = trackingIcon:GetPoint(1)
    eq(irel, tracking, "icon anchored to its own button")
    ok(ip == "CENTER" and irp == "CENTER", "centre to centre")
    ok(ix == 0 and iy == 0,
        "with Blizzard's (2,-2) dropped - it only existed to cancel a 64 ring at (0,0)")

    -- THE SCALE TRAP. f:SetScale(52/64) looks like the same fix and is not: the
    -- polar offsets are in the frame's own space, so a 75-unit vector would render
    -- at 61 against a rim at 70 and put the button back on the map. Nothing in the
    -- placement assertions above can see it, because they read the raw offsets.
    eq(tracking:GetScale(), 1, "the frame itself is never scaled")
    ok(math.abs(tracking:GetEffectiveScale() - lfg:GetEffectiveScale()) < 1e-9,
        "so the button and the eye are measured in one coordinate space")
    eq(tracking:GetWidth(), 33, "and the 33x33 hit rect survives, same as the eye's")

    -- The size fix must not have moved the button. Recomputed rather than assumed:
    -- MiniMapTracking is a plain Frame with an explicit size, so region sizes
    -- cannot feed back into its rect, and this is what proves it.
    local _, _, _, sx, sy = tracking:GetPoint(1)
    ok(math.abs(math.sqrt(sx * sx + sy * sy) - trackR) < 1e-9,
        "and the polar radius is untouched by the resize")

    -- Does the code actually READ the eye, or just hard-code 52? Only a live value
    -- that differs can tell those apart.
    lfgBorder:SetSize(50, 50)
    ns.Minimap:Apply()
    eq(trackingBorder:GetWidth(), 50, "follows the eye to a different size")
    eq(trackingIcon:GetWidth(), 24 * 50 / 64, "and rescales the icon with it")
    lfgBorder:SetSize(52, 52)
    ns.Minimap:Apply()

    -- A zero would be an invisible ring around an invisible icon, so garbage falls
    -- back to Blizzard's own 52 rather than being followed or bailing out.
    for _, bad in ipairs({ 0, 500 }) do
        lfgBorder:SetSize(bad, bad)
        ns.Minimap:Apply()
        eq(trackingBorder:GetWidth(), 52, ("a %d-wide eye ring is rejected, not copied"):format(bad))
        eq(trackingIcon:GetWidth(), 19.5, "and the icon stays sane too")
    end
    lfgBorder:SetSize(52, 52)

    -- No eye at all: still shrink, because 52 is independently correct.
    _G.LFGMinimapFrameBorder = nil
    ns.Minimap:Apply()
    eq(trackingBorder:GetWidth(), 52, "no eye to measure falls back to Blizzard's own 52")
    _G.LFGMinimapFrameBorder = lfgBorder
    ns.Minimap:Apply()

    -- Both call-site placements, which are otherwise untestable claims. The sizing
    -- sits outside the "is anything being tracked" branch and outside the "does
    -- the map have a rect" branch, so neither a hidden button nor an unmeasurable
    -- map can leave the ring at 64.
    trackingBorder:SetSize(64, 64)
    _G.GetTrackingTexture = function() return nil end
    ns.Minimap:Apply()
    eq(trackingBorder:GetWidth(), 52, "sized even while hidden, since Blizzard shows it itself")
    _G.GetTrackingTexture = function() return 135725 end

    trackingBorder:SetSize(64, 64)
    local realGetWidth = minimap.GetWidth
    minimap.GetWidth = function() return nil end
    ns.Minimap:Apply()
    eq(trackingBorder:GetWidth(), 52, "sized even when the map has no rect to measure")
    minimap.GetWidth = realGetWidth
    ns.Minimap:Apply()

    -- APPARENT size, not declared size. A texture's GetWidth is in its own
    -- frame's coordinate space, so if another addon scales the eye - minimap
    -- button packs do exactly that - copying its 52 verbatim leaves two rings
    -- identical on paper and 25% apart on screen, which is the complaint being
    -- fixed rather than a hypothetical.
    lfg:SetScale(0.8)
    ns.Minimap:Apply()
    ok(math.abs(trackingBorder:GetWidth() - 52 * 0.8) < 1e-9,
        ("matches the eye's rendered size when the eye is scaled (%.2f)"):format(trackingBorder:GetWidth()))
    lfg:SetScale(1)
    ns.Minimap:Apply()
    eq(trackingBorder:GetWidth(), 52, "and back when it is not")

    -- A foreign MiniMapTrackingFrame must not capture any of this. That name is
    -- dead in the 1.15.9 client, but addons of the sort HelloUI replaces create
    -- it, and both the frame lookup and the region anchors would follow it.
    local decoy = Frame.new("MiniMapTrackingFrame", _G.UIParent)
    trackingBorder:SetSize(64, 64)
    ns.Minimap:Apply()
    eq(trackingBorder:GetWidth(), 52, "sizes the real button even with a decoy global present")
    eq(select(2, trackingBorder:GetPoint(1)), tracking, "and anchors the ring to the real button")
    eq(#decoy._points, 0, "leaving the decoy entirely alone")
    _G.MiniMapTrackingFrame = nil
    ns.Minimap:Apply()

    -- Nudgeable, and the nudge is honoured EXACTLY. Asserted against the angle
    -- recomputed here rather than against a direction, because a clamp - say
    -- "18 to 20, the sensible band" - passes every other check in this block
    -- while silently turning a deliberate 45 into 20.
    ns.Minimap:NudgeTracking(45)
    do
        local _, _, _, fx, fy = tracking:GetPoint(1)
        local rad = 45 * math.pi / 180
        local c, s = math.cos(rad), math.sin(rad)
        local ex, ey = ldx * c - ldy * s, ldx * s + ldy * c
        ok(math.abs(fx - ex) < 1e-9 and math.abs(fy - ey) < 1e-9,
            "an out-of-band angle is honoured exactly, not clamped to a tidy range")
    end
    ns.Minimap:NudgeTracking(90)
    local _, _, _, rx, ry = tracking:GetPoint(1)
    local rimR = math.sqrt(rx * rx + ry * ry)
    ok(math.abs(rimR - lfgR) < 0.5, "a nudge moves it round the rim, not off it")
    ok(ry < ty, "and 90 degrees is further down than the default")
    ns.Minimap:NudgeTracking(19)

    -- Restoration, deliberately placed after all those repeated Applies: it is the
    -- SECOND and later Apply that catches an original recorded unconditionally,
    -- because by then HelloUI's own 52 would be on file as "Blizzard's".
    ns.Config:Set("fixTrackingIcon", false)
    ns.Minimap:Apply()
    eq(trackingBorder:GetWidth(), 64, "ring handed back to Blizzard's 64 when switched off")
    local rp1, _, rp2, rx1, ry1 = trackingBorder:GetPoint(1)
    ok(rp1 == "TOPLEFT" and rp2 == "TOPLEFT" and rx1 == 0 and ry1 == 0,
        "at Blizzard's flush anchor, not HelloUI's inset")
    eq(trackingIcon:GetWidth(), 24, "icon back to 24")
    local _, _, _, rix, riy = trackingIcon:GetPoint(1)
    ok(rix == 2 and riy == -2, "with Blizzard's (2,-2) nudge back, which its 64 ring needs")

    -- Off, on, off again: the saved originals must survive being re-enabled.
    ns.Config:Set("fixTrackingIcon", true)
    ns.Minimap:Apply()
    eq(trackingBorder:GetWidth(), 52, "re-enabling matches the eye again")
    ns.Config:Set("fixTrackingIcon", false)
    ns.Minimap:Apply()
    eq(trackingBorder:GetWidth(), 64, "and the second restore still knows Blizzard's value")

    -- Left ENABLED for everything downstream. Leaving it off here would silently
    -- disable the feature for the rest of the suite and make the master-switch
    -- assertion below measure an already-restored button.
    ns.Config:Set("fixTrackingIcon", true)
    ns.Minimap:Apply()
    eq(trackingBorder:GetWidth(), 52, "and the feature is back on for the rest of the run")

    -- The whole point: Blizzard leaves the frame hidden at login even with
    -- tracking active, so positioning it correctly achieves nothing on its own.
    eq(tracking:IsShown(), true, "and actually SHOWN, which Blizzard never does at login")
    eq(trackingIcon._tex, 135725, "with the active tracking texture set")

    -- No tracking active: mirror Blizzard and hide it again.
    _G.GetTrackingTexture = function() return nil end
    ns.Minimap:Apply()
    eq(tracking:IsShown(), false, "hidden again when nothing is being tracked")
    _G.GetTrackingTexture = function() return 135725 end
    ns.Minimap:Apply()
    eq(tracking:IsShown(), true, "and back when tracking resumes")

    -- The clock sits in a subtree scaled to 110%. Compensating its own scale
    -- brings the EFFECTIVE scale back to 1, so the digits render at native
    -- size on the pixel grid - which rounding the anchor alone could not do.
    ok(math.abs(clockBtn:GetEffectiveScale() - 1) < 0.001,
        ("clock renders at native scale (effective %.3f)"):format(clockBtn:GetEffectiveScale()))
    ok(clockBtn:GetScale() < 1, "by scaling the button down against the minimap")

    -- And only now is rounding the half-pixel anchor meaningful.
    local _, _, _, cx, cy = clockText:GetPoint(1)
    eq(cx, 1, "clock text at the offset dialled in live")
    eq(cy, -1, "both whole pixels, and neither is Blizzard's guess")

    -- The offset is nudgeable, since the right optical value cannot be read
    -- off a screenshot.
    ns.Minimap:NudgeClock(1, 0)
    local _, _, _, nx, ny = clockText:GetPoint(1)
    eq(nx, 1, "clock x nudged")
    eq(ny, 0, "clock y nudged")
    ns.Minimap:NudgeClock(1, -1)

    -- Switching it off hands the scale back.
    ns.Config:Set("fixClockText", false)
    ns.Minimap:Apply()
    eq(clockBtn:GetScale(), 1, "scale restored when disabled")
    ns.Config:Set("fixClockText", true)
    ns.Minimap:Apply()
end

print("\ncast bar style")
do
    -- The flat look: Blizzard's border art off, a backdrop behind the fill, the
    -- name to the left and a countdown on the right. Same shape as hideBarArt -
    -- nothing here ships a texture.
    eq(pcb.Border:GetTexture(), nil, "cast bar border art blanked")
    eq(pcb.Flash:GetTexture(), nil, "and the flash that lights the same outline")
    eq(pcb.BorderShield:GetTexture(), nil, "and the uninterruptible shield")

    -- THE REGRESSION. Hiding these was not enough: on a completed cast Blizzard
    -- calls Flash:Show(), then plays FlashAnim, which animates the alpha to 1 and
    -- leaves it there. A Hide loses to the Show and a SetAlpha loses to the
    -- animation - so the outline flashed back for about a second on every cast
    -- that finished. A blanked texture draws nothing no matter who shows it.
    pcb.Flash:SetAlpha(0)
    pcb.Flash:Show()
    pcb.Flash:SetAlpha(1)
    eq(pcb.Flash:GetTexture(), nil, "and it stays blank when Blizzard shows and lights it")
    ok(pcb.HelloUIBackdrop ~= nil and pcb.HelloUIBackdrop:IsShown(), "flat backdrop behind the fill")
    ok(pcb.HelloUIBackdrop._color and pcb.HelloUIBackdrop._color[4] == 0.55, "and it is actually painted")
    local tp, _, _, tx = pcb.Text:GetPoint(1)
    ok(tp == "LEFT" and tx == 4, "spell name moved to the left")
    eq(pcb.Text:GetJustifyH(), "LEFT", "and justified there")
    ok(pcb.HelloUITimer ~= nil and pcb.HelloUITimer:IsShown(), "countdown created - the client has no CastTimeText")

    -- The spell name has to shrink. Blizzard's GameFontHighlight is sized for a
    -- bar with border art over the overspill; with the border hidden its ink
    -- climbs out of the 13px bar.
    eq(pcb.Text:GetFontObject(), _G.GameFontHighlightSmall or "GameFontHighlightSmall",
        "spell name shrunk to fit a 13px bar")
    eq(pcb.Text._wrap, false, "and kept to one line, which is the other way out of the bar")
    local cr = select(1, pcb:GetStatusBarColor())
    eq(cr, 0.85, "and coloured to match HelloWarrior's")

    -- The colour is the one thing Blizzard overwrites: UpdateBarFillTexture
    -- re-applies a per-bar-type colour on every cast, so it has to be re-asserted
    -- from a hook on the instance.
    ok(ns.CastBar.hookedFill, "UpdateBarFillTexture hooked on the instance")
    pcb:UpdateBarFillTexture(false)
    eq(select(1, pcb:GetStatusBarColor()), 0.85, "and the colour survives Blizzard recomputing it")

    -- The countdown reads the mixin's own numbers, so the digits cannot disagree
    -- with the fill.
    ok(ns.CastBar.hookedUpdate, "the countdown rides Blizzard's own OnUpdate")
    pcb.value, pcb.maxValue, pcb.channeling = 0.5, 2.0, nil
    pcb:Show()
    pcb:GetScript("OnUpdate_hook")(pcb)
    eq(pcb.HelloUITimer:GetText(), "1.5", "cast counts down to zero")
    pcb.value, pcb.channeling = 0.5, true
    pcb:GetScript("OnUpdate_hook")(pcb)
    eq(pcb.HelloUITimer:GetText(), "0.5", "a channel counts its remainder, not its elapsed")
    pcb:Hide()

    -- THE RE-ASSERTION. Blizzard rebuilds the whole look from SetLook, called by
    -- PlayerFrame_DetachCastBar on every Edit Mode layout update - at login, on
    -- every close of Edit Mode, on any layout change. It restores the border art,
    -- the full-size font and a text box anchored 5 above the bar's top, all in
    -- one call, so a style applied once loses all three the first time Edit Mode
    -- so much as refreshes.
    ok(ns.CastBar.hookedLook, "SetLook hooked on the instance")
    pcb:SetLook("CLASSIC")
    eq(pcb.Border:GetTexture(), nil, "border stays blank when Blizzard rebuilds the look")
    eq(pcb.Text:GetFontObject(), _G.GameFontHighlightSmall or "GameFontHighlightSmall",
        "and the name stays small")
    local lp, _, _, lx = pcb.Text:GetPoint(1)
    ok(lp == "LEFT" and lx == 4, "and stays anchored inside the bar, not 5 above its top")

    -- Switchable and restorable, like everything else here.
    ns.Config:Set("castBarStyle", false)
    ns:ApplyAll()
    eq(pcb.Border:GetTexture(), "Interface\\CastingBar\\UI-CastingBar-Border",
        "border art handed back when switched off")
    eq(pcb.Flash:GetTexture(), "Interface\\CastingBar\\UI-CastingBar-Flash", "flash too")
    eq(pcb.HelloUIBackdrop:IsShown(), false, "backdrop hidden")
    local rp, _, _, rx = pcb.Text:GetPoint(1)
    ok(rp == "CENTER" and rx == 0, "and the spell name re-centred")
    eq(select(1, pcb:GetStatusBarColor()), 1, "with Blizzard's own colour recomputed, not remembered")
    eq(pcb.Text:GetFontObject(), "GameFontHighlight", "and Blizzard's own font handed back")
    -- And the re-assertion hook has to respect the switch too: a SetLook while the
    -- style is off must leave Blizzard's own look alone rather than quietly
    -- restyling behind the setting's back.
    pcb:SetLook("CLASSIC")
    eq(pcb.Border:GetTexture(), "Interface\\CastingBar\\UI-CastingBar-Border",
        "and a later SetLook does not restyle while switched off")
    ns.Config:Set("castBarStyle", true)
    ns:ApplyAll()
    eq(pcb.Border:GetTexture(), nil, "and restyled when switched back on")
    -- Asserted after the off/on cycle on purpose: a texture is created shown, so
    -- checking it on the first pass passes even for code that never shows it.
    -- Only the second styling can tell the difference.
    eq(pcb.HelloUIBackdrop:IsShown(), true, "including the backdrop, which restore had hidden")
    eq(pcb.HelloUITimer:IsShown(), true, "and the countdown")
end

print("\ncast bar")
do
    -- No sibling drawing one: Blizzard's is left entirely alone. This is the
    -- half of the feature every non-Warrior gets, so it is asserted first.
    eq(pcb.showCastbar, true, "Blizzard's cast bar untouched with no sibling bar")

    -- HelloWarrior builds its cluster for Warriors only, so the test is the
    -- FRAME's existence, not the addon's. An installed-but-inert HelloWarrior on
    -- a Priest must not cost that Priest their cast bar.
    _G.C_AddOns = { IsAddOnLoaded = function() return true end }
    ns:ApplyAll()
    eq(pcb.showCastbar, true, "and untouched merely because the addon is loaded")

    local hwCluster = Frame.new("HelloWarrior_Container", _G.UIParent)
    local hwBar = Frame.new("HelloWarrior_CastBar", hwCluster)
    ns:ApplyAll()
    eq(pcb.showCastbar, false, "yielded once a sibling is actually drawing one")
    eq(ns.CastBar.yielded, "HelloWarrior_CastBar", "and it names which one")

    -- /hw bars off hides the cluster, so ours is not on screen either - hand
    -- Blizzard's back rather than leave the player with no cast bar at all.
    hwCluster:Hide()
    ns:ApplyAll()
    eq(pcb.showCastbar, true, "handed back when the sibling's cluster is hidden")
    hwCluster:Show()
    ns:ApplyAll()
    eq(pcb.showCastbar, false, "and yielded again when it comes back")

    -- Switchable, like every other feature here.
    ns.Config:Set("yieldCastBar", false)
    ns:ApplyAll()
    eq(pcb.showCastbar, true, "restored when the setting is off")
    ns.Config:Set("yieldCastBar", true)
    ns:ApplyAll()
    eq(pcb.showCastbar, false, "and yielded again when it is back on")

    -- Repeated applies must not thrash the flag: Apply runs on every zone
    -- change, and this is the guard that keeps it a no-op.
    local writes = 0
    local realSet = pcb.SetAndUpdateShowCastbar
    pcb.SetAndUpdateShowCastbar = function(self, show) writes = writes + 1; realSet(self, show) end
    ns:ApplyAll()
    ns:ApplyAll()
    eq(writes, 0, "and a repeated apply writes nothing at all")
    pcb.SetAndUpdateShowCastbar = realSet

    -- The sibling goes away entirely (disabled, then a reload).
    _G.HelloWarrior_CastBar = nil
    _G.HelloWarrior_Container = nil
    ns:ApplyAll()
    eq(pcb.showCastbar, true, "and given back when the sibling is gone")
    eq(ns.CastBar.yielded, nil, "with nothing left recorded")
    _G.HelloWarrior_Container, _G.HelloWarrior_CastBar = hwCluster, hwBar
    _G.C_AddOns = { IsAddOnLoaded = function() return false end }
end

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

-- The gold on the minimap buttons, which is what "the minimap icons still have
-- gold" was about. Blizzard's own art, every piece reached by name.
for label, tex in pairs({
    ["tracking ring"]    = trackingBorder,
    ["LFG eye ring"]     = lfgBorder,
    ["mail ring"]        = mailBorder,
    ["battlefield ring"] = bfBorder,
    ["north tag"]        = northTag,
    ["compass ring"]     = compass,
    ["minimise button"]  = toggleButton._normal,
    ["its pushed state"] = toggleButton._pushed,
}) do
    eq(tex._desat, true, ("%s desaturated"):format(label))
    local tr = select(1, tex:GetVertexColor())
    eq(tr, 0.4, ("%s tinted"):format(label))
end
-- Hidden is not absent: the mail ring was tinted while its frame was hidden, so
-- it is already grey the moment mail arrives.
eq(mailFrame:IsShown(), false, "and the mail ring was tinted while still hidden")

-- THE RULE. A sibling addon's minimap button must be untouched - not because
-- the code avoids it, but because the code never enumerates anything that could
-- reach it. Its ring is anonymous, exactly as the four real ones are, so only a
-- children/regions sweep could find it.
local sr, sg, sb = siblingRing:GetVertexColor()
ok(sr == 1 and sg == 1 and sb == 1, "a sibling addon's minimap button is never touched")
eq(siblingRing._desat, false, "nor desaturated")

-- And live state stays live. Asserted on the VERTEX COLOUR as well as the
-- desaturation flag: SetDesaturated(true) twice is indistinguishable from once,
-- so the flag alone cannot catch a second pass - the tint can.
eq(liveStateIcon._desat, true, "a live-state icon keeps its own desaturation")
local lr, lg = liveStateIcon:GetVertexColor()
ok(lr == 1 and lg == 0.4, "and its own colour, which a second pass would flatten")

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
eq(_G._statusContainer:GetWidth(), 1024, "status bar width restored when disabled")
eq(_G._statusContainer.StandaloneFrameTexture2:GetWidth(), 240, "and its border art too")
eq(mainMenuBar:IsShown(), true, "bar art restored when disabled")
eq(trackingBorder:GetWidth(), 64, "tracking ring handed back to Blizzard when disabled")
eq(select(1, northTag:GetVertexColor()), 1, "minimap button gold un-tinted when disabled")
eq(toggleButton._normal._desat, false, "and the minimise button un-desaturated")
eq(chat:GetWidth(), 400, "chat still untouched")

_G.SlashCmdList["HELLOUI"]("on")
eq(ns.Config:Get("enabled"), true, "/hui on re-enables")
eq(_G.ActionButton1.HotKey._alpha, 0, "keybind text hidden again")

print("\nslash commands")
-- minimapprobe and tracking are in here because both print formatted numbers off
-- frames that may be absent, and a bare %s on a nil is a real hazard in 5.1.
for _, cmd in ipairs({ "", "status", "apply", "char", "char clear", "char barsoff bar3",
                       "char barsoff nonsense", "minimapprobe", "tracking", "tracking 45",
                       "clock 1 -1", "help", "reset" }) do
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

-- The options panel outgrew the Settings canvas - which does not clip, so the
-- last three controls drew over the game instead. Everything lives in a scroll
-- child now, and the way that regresses is somebody adding a widget parented to
-- the panel, which escapes the scroll frame and floats over the game again.
do
    local optPanel = _G["HelloUIOptionsPanel"]
    local optScroll = _G["HelloUIOptionsScroll"]
    ok(optScroll ~= nil, "the options panel is wrapped in a scroll frame")
    local scrollChild = optScroll and optScroll:GetScrollChild()
    ok(scrollChild ~= nil, "which has a scroll child to put the controls in")

    -- The panel itself carries the scroll frame and nothing else.
    local strays = {}
    for _, child in ipairs({ optPanel:GetChildren() }) do
        if child ~= optScroll then strays[#strays + 1] = child:GetName() or "unnamed" end
    end
    ok(#strays == 0, ("no control escapes the scroll frame%s"):format(
        #strays > 0 and (" - found " .. table.concat(strays, ", ")) or ""))

    -- And a control picked from the far end of the panel really is inside it,
    -- so the check above cannot pass by the panel simply being empty.
    local deep = _G["HelloUIOptLayoutPerChar"]
    ok(deep ~= nil and deep:GetParent() == scrollChild,
        "and the last control in the panel is inside the scroll child")
end

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

-- The same trap for the tracking angle. Every install that had ever logged in
-- carried `trackingAngle = 30`, so moving the default to 19 could not reach the
-- machine that reported the gap.
do
    HelloUIDB = { trackingAngle = 30 }
    ns.Config:Init()
    eq(HelloUIDB.trackingAngle, 19, "an install still on the old 30 is migrated")
    ok(HelloUIDB.trackingAngleV2 == true, "latched so it runs once")

    -- Value-guarded, which is the whole point: a deliberate nudge is not a
    -- stale default and must survive.
    HelloUIDB = { trackingAngle = 45 }
    ns.Config:Init()
    eq(HelloUIDB.trackingAngle, 45, "but a deliberately nudged angle is left alone")

    -- And once latched, a later 30 is the player's own choice.
    HelloUIDB.trackingAngle = 30
    ns.Config:Init()
    eq(HelloUIDB.trackingAngle, 30, "a 30 chosen after the migration is not re-migrated")

    ns.Config:ResetAccount()
    ok(HelloUIDB.trackingAngleV2 == true, "reset marks the angle migration done too")
    HelloUIDB.trackingAngle = 30
    ns.Config:Init()
    eq(HelloUIDB.trackingAngle, 30, "so an angle set after a reset survives the next login")
    ns.Config:ResetAccount()
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
