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

--------------------------------------------------------------------------
-- No button borders
--
-- There was a feature here that took ActionButtonTemplate's NormalTexture
-- (Interface\Buttons\UI-Quickslot2) from Blizzard's alpha="0.5" up to 1, on the
-- reasoning that hiding the bar backdrop takes the milled recesses with it and
-- leaves the icons floating on a half-transparent outline.
--
-- Removed on the only evidence that settles a look: it was tried on screen and
-- the stock half-alpha border was preferred. Nothing here touches the texture
-- now - not to set it, not to restore it - so the buttons carry exactly what
-- Blizzard ships. Worth keeping the observation, since somebody will notice the
-- faint outline and think it is a bug: it is Blizzard's own art at Blizzard's
-- own alpha, and their Hide Bar Art setting produces the same thing.
--------------------------------------------------------------------------

local function applyToButton(btn, name)
    local hideKey = Config:Enabled("hideKeybindText")
    local hideMacro = Config:Enabled("hideMacroText")

    local hotkey = hotkeyOf(btn, name)
    if hotkey then hotkey:SetAlpha(hideKey and 0 or 1) end

    local macro = macroOf(btn, name)
    if macro then macro:SetAlpha(hideMacro and 0 or 1) end
end

function Buttons:Apply()
    local found = 0
    for _, def in ipairs(ns.BARS) do
        for i = 1, def.count do
            local name = def.buttons .. i
            local btn = _G[name]
            if btn then
                applyToButton(btn, name)
                found = found + 1
            end
        end
    end
    Buttons.found = found
end

--------------------------------------------------------------------------
-- Re-assertion, and why there is almost none
--
-- Nothing in Blizzard's interface ever calls SetAlpha on an action button's
-- HotKey or Name. The whole tree was searched: the only SetAlpha calls on a
-- font string called Name belong to the raid pullout buttons and the
-- commentator UI, neither of which is an action button. Blizzard's action bar
-- code reaches these two font strings through Show, Hide, SetText and
-- SetVertexColor only - and none of those touch alpha.
--
-- So an alpha we set stays set, permanently, and the correct amount of
-- re-assertion is zero. That is also why alpha was the right choice over
-- Hide in the first place.
--
-- The events below are therefore pure insurance against a button that did not
-- exist during the first pass. On Era every bar and every button is created at
-- load, so in practice they never do anything - they are cheap, and the cost
-- of being wrong about that is a visible keybind on a bar nobody asked for.
--
-- Deliberately NOT hooking ActionBarActionButtonMixin.UpdateHotkeys: Mixin()
-- copies function references onto each button when it is created, so hooking
-- the mixin table afterwards would not reach a single existing button. It
-- would look like it worked and do nothing.
--------------------------------------------------------------------------

function Buttons:Init()
    local function sweep(label)
        return function() ns:SafeCall("Buttons:" .. label, Buttons.Apply, Buttons) end
    end

    ns:On("UPDATE_BINDINGS", sweep("bindings"))
    ns:On("UPDATE_SHAPESHIFT_FORMS", sweep("forms"))
    ns:On("UNIT_PET", function(unit)
        if unit == "player" then sweep("pet")() end
    end)
end

function Buttons:StatusText()
    if (Buttons.found or 0) == 0 then
        return "buttons: |cffff8080none found|r"
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
    ns:Print("buttons: %d found, %d with keybind text, %d with macro text",
        total, withHotkey, withMacro)
    ns:Print("  |cff808080keybind %s, macro %s|r",
        Config:Enabled("hideKeybindText") and "hidden" or "shown",
        Config:Enabled("hideMacroText") and "hidden" or "shown")
end
