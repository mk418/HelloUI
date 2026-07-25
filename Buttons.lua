local ADDON_NAME, ns = ...

ns.Buttons = {}
local Buttons = ns.Buttons

local Config = ns.Config

--------------------------------------------------------------------------
-- Keybind and macro text
--
-- There is no native toggle for this. Blizzard's Options > Action Bars panel
-- offers per-bar visibility, Lock Action Bars and cooldown numbers, and
-- nothing else; Edit Mode's action bar settings are Orientation, NumRows,
-- NumIcons, IconSize, IconPadding, VisibleSetting, HideBarArt,
-- HideBarScrolling and AlwaysShowButtons. So unlike the bar-visibility
-- feature next door, this one really does have to be done by hand.
--
-- Alpha, not Hide. Blizzard drives both font strings itself:
-- ActionBarActionButtonMixin:UpdateHotkeys calls hotkey:Show() / :Hide() on
-- every binding change, and ActionButton_UpdateRangeIndicator shows and
-- recolours the same font string to signal range. Hiding them starts a
-- fight that we re-lose on the next action update; alpha survives untouched
-- because nothing in Blizzard's path ever sets it.
--
-- Consequence worth knowing: on a button whose hotkey text is the range
-- indicator, that indicator is the range display. Alpha 0 hides it too.
-- That was already true under DragonflightUI, which did the same thing.
--------------------------------------------------------------------------

-- Both font strings resolve two ways on 1.15.9 and we prefer the object
-- field. `Name` is a direct child of the button so `_G[name.."Name"]` is
-- unambiguous, but `HotKey` lives inside an unnamed TextOverlayContainer and
-- only reaches the global namespace because $parent resolves past unnamed
-- ancestors to the nearest named one. That is real - Blizzard relies on it
-- themselves, and the working fork dereferences _G[name.."Count"] out of
-- the same container unguarded - but the parentKey alias Blizzard installs
-- in ActionButtonTextOverlayContainerMixin:OnLoad is the more direct route
-- and does not depend on naming semantics at all.
local function hotkeyOf(btn, name)
    return btn.HotKey or _G[name .. "HotKey"]
end

local function macroOf(btn, name)
    return btn.Name or _G[name .. "Name"]
end

local applying = false

local function applyToButton(btn, name)
    local hideKey = Config:Enabled("hideKeybindText")
    local hideMacro = Config:Enabled("hideMacroText")

    local hotkey = hotkeyOf(btn, name)
    if hotkey then hotkey:SetAlpha(hideKey and 0 or 1) end

    local macro = macroOf(btn, name)
    if macro then macro:SetAlpha(hideMacro and 0 or 1) end
end

function Buttons:Apply()
    applying = true
    for _, def in ipairs(ns.BARS) do
        for i = 1, def.count do
            local name = def.buttons .. i
            local btn = _G[name]
            if btn then applyToButton(btn, name) end
        end
    end
    applying = false
end

--------------------------------------------------------------------------
-- Re-assertion
--
-- Blizzard rewrites the hotkey text whenever bindings change or a button's
-- action changes, and although it never touches alpha, a button that did not
-- exist at our first pass has to be caught. Hooking UpdateHotkeys covers
-- both: it is the one function that owns the text, and it runs per button.
--
-- The `applying` guard is not for recursion (we never call UpdateHotkeys) -
-- it is so a full Apply() sweep does not re-enter this per button and do the
-- same work twice for every button on screen.
--------------------------------------------------------------------------

function Buttons:Init()
    local mixin = _G["ActionBarActionButtonMixin"]
    if mixin and mixin.UpdateHotkeys then
        hooksecurefunc(mixin, "UpdateHotkeys", function(btn)
            if applying then return end
            local name = btn.GetName and btn:GetName()
            if not name then return end
            applyToButton(btn, name)
        end)
        Buttons.hooked = true
    end

    -- The stance and pet bars inherit the same button template but reach
    -- their own update paths, and a binding change repaints every bar, so a
    -- cheap whole-sweep on the binding event covers what the per-button hook
    -- does not.
    ns:On("UPDATE_BINDINGS", function() ns:SafeCall("Buttons:bindings", Buttons.Apply, Buttons) end)
    ns:On("ACTIONBAR_SLOT_CHANGED", function() ns:SafeCall("Buttons:slot", Buttons.Apply, Buttons) end)
    ns:On("UPDATE_SHAPESHIFT_FORMS", function() ns:SafeCall("Buttons:forms", Buttons.Apply, Buttons) end)
    ns:On("UNIT_PET", function(unit)
        if unit == "player" then ns:SafeCall("Buttons:pet", Buttons.Apply, Buttons) end
    end)
end

function Buttons:StatusText()
    if not Buttons.hooked then
        return "buttons: |cffffd100no UpdateHotkeys hook|r"
    end
    return nil
end

function Buttons:Status()
    local total, withHotkey, withMacro = 0, 0, 0
    for _, def in ipairs(ns.BARS) do
        for i = 1, def.count do
            local name = def.buttons .. i
            local btn = _G[name]
            if btn then
                total = total + 1
                if hotkeyOf(btn, name) then withHotkey = withHotkey + 1 end
                if macroOf(btn, name) then withMacro = withMacro + 1 end
            end
        end
    end
    ns:Print("buttons: %d found, %d with keybind text, %d with macro text%s",
        total, withHotkey, withMacro,
        Buttons.hooked and "" or " |cffffd100(no UpdateHotkeys hook)|r")
end
