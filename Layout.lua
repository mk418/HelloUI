local ADDON_NAME, ns = ...

ns.Layout = {}
local Layout = ns.Layout

local Config = ns.Config

--------------------------------------------------------------------------
-- The DragonflightUI bar layout, as an Edit Mode layout
--
-- Every other module in this addon refuses to own position, on the grounds
-- that Edit Mode owns it on 1.15.9. This module does not break that rule -
-- it is the rule taken seriously. Rather than fighting Edit Mode with
-- SetPoint on frames it will silently re-anchor, HelloUI writes a real Edit
-- Mode layout and lets Edit Mode apply it. Afterwards the addon is not
-- involved: the layout simply is the player's layout, editable and
-- persistent like any other.
--
-- NON-DESTRUCTIVE BY CONSTRUCTION. It adds a layout of its own and never
-- touches an existing one. Switching back is the layout dropdown in Edit
-- Mode, so the worst case is one extra entry in that list.
--
-- Never applied behind your back. At login HelloUI asks - once per session,
-- and only if its layout is not already the active one - and otherwise does
-- nothing. If you then drag a bar, it stays dragged: HelloUI must not put it
-- back, because at that point the layout is yours. Re-applying is an explicit
-- act (`/hui layout`), and because Edit Mode saves your dragging into the
-- layout itself, re-applying IS the reset.
--
-- WHERE THE NUMBERS COME FROM. DragonflightUI's own action bar defaults, in
-- Modules/Actionbar/Actionbar.lua: buttonScale 0.8, padding 2, bar1 above the
-- reputation bar, bars 2 and 3 stacked upward from it, and the two 3-row
-- blocks flanking the stack at +/-64. Edit Mode stores those two scalars
-- pre-conversion - `display = raw * stepSize + minValue`, from
-- EditModeSettingDisplayInfo - so 80% icon size is raw 3 (3*10+50) and 2px
-- padding is raw 0 (0*1+2).
--
-- MIND THE NUMBERING. DragonflightUI's bar4 is MultiBarLeft and its bar5 is
-- MultiBarRight; Blizzard has those the other way round. The table below is
-- in Blizzard's terms, so RightBar1 (MultiBarRight, the game's bar 4) is the
-- block DragonflightUI called bar5 and put on the right.
--------------------------------------------------------------------------

--------------------------------------------------------------------------
-- Account-wide or per-character
--
-- Edit Mode already has this distinction and it costs nothing to use: a
-- layout carries a layoutType, and Character layouts are only visible to the
-- character that owns them. So per-character support is a choice of enum
-- value and a name, not a mechanism.
--
-- Account is the default because that is what the old profile was - 47
-- characters sharing one arrangement. Switching to per-character gives each
-- character its own copy to edit, so tuning the priest no longer moves the
-- warrior's bars.
--
-- Names are suffixed in per-character mode so the Edit Mode dropdown stays
-- readable and so the two modes can coexist without a name collision. The
-- old account-wide layout is left alone when you switch; delete it in Edit
-- Mode if you want it gone.
--
-- Blizzard caps layouts at 5 per type (Constants.EditModeConsts
-- .EditModeMaxLayoutsPerType), counted separately for Account and Character,
-- so creating one can genuinely fail and says so rather than failing quietly.
--------------------------------------------------------------------------

local BASE_NAME = "HelloUI"
local MAX_PER_TYPE = 5

local function perCharacter()
    return Config:Get("layoutPerCharacter") and true or false
end

local function layoutName()
    if not perCharacter() then return BASE_NAME end
    local name = UnitName("player")
    return name and (BASE_NAME .. " - " .. name) or BASE_NAME
end

local function layoutType()
    local T = Enum and Enum.EditModeLayoutType
    if not T then return 1 end
    if perCharacter() then return T.Character or 2 end
    return T.Account or 1
end

-- There is no "applied once" latch any more. It existed to stop a silent
-- auto-apply from re-running, and the login prompt replaced the silent
-- auto-apply: the question only appears when the layout is not already
-- active, so saying yes retires it permanently and saying no costs one
-- dismissal per session.

-- Raw Edit Mode values, not display values.
local ICON_SIZE = 3     -- 3 * 10 + 50 = 80%
local ICON_PADDING = 0  -- 0 *  1 +  2 = 2px

local function indices()
    local I = Enum and Enum.EditModeActionBarSystemIndices
    if not I then return nil end
    return I
end

-- Every bar is anchored to UIParent at an explicit offset. The first attempt
-- chained them - bar2 to MainActionBar's TOP, bar3 to bar2's, and so on - on
-- the reasoning that Blizzard knows its own row height. It does not work: an
-- Edit Mode action bar frame is shorter than the buttons it contains, so a
-- 2px gap measured from the frame's top edge lands inside the row above and
-- the whole stack overlaps. Explicit offsets are less elegant and actually
-- correct.
--
-- ROW_STEP is deliberately generous. A 45px button at 80% is 36px, so 44
-- leaves visible air between rows rather than the hairline DragonflightUI
-- used - and a gap that is slightly too big reads as a choice, where one
-- pixel too small reads as a bug. Nudge any of it in Edit Mode afterwards;
-- that is the point of writing a layout rather than enforcing one.
local ROW_STEP = 44    -- vertical distance between stacked bars
local BASE_Y = 26      -- main bar's height above the screen bottom
local FLANK_X = 330    -- how far the 3-row blocks sit from centre

local function geometry()
    local I = indices()
    if not I then return nil end

    return {
        { index = I.MainBar, rows = 1,
          point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 0, y = BASE_Y },

        { index = I.Bar2, rows = 1,
          point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 0, y = BASE_Y + ROW_STEP },

        { index = I.Bar3, rows = 1,
          point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 0, y = BASE_Y + ROW_STEP * 2 },

        -- MultiBarRight: the right-hand 4x3 block, level with the stack.
        { index = I.RightBar1, rows = 3,
          point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = FLANK_X, y = BASE_Y },

        -- MultiBarLeft: the left-hand one. Switched off in the shipped
        -- defaults, but positioned anyway so it lands correctly if enabled.
        { index = I.RightBar2, rows = 3,
          point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = -FLANK_X, y = BASE_Y },

        -- Stance and pet share a row above the stack, as DragonflightUI had
        -- them. Only druids ever show both at once, and they overlapped there
        -- too - pet is nudged right so that case is merely tight, not stacked.
        { index = I.StanceBar, rows = 1,
          point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = -120, y = BASE_Y + ROW_STEP * 3 },

        { index = I.PetActionBar, rows = 1,
          point = "BOTTOM", relativeTo = "UIParent", relativePoint = "BOTTOM", x = 120, y = BASE_Y + ROW_STEP * 3 },
    }
end

--------------------------------------------------------------------------
-- Building the systems array
--
-- The base is a copy of Blizzard's own preset rather than a hand-built
-- table. Every system HelloUI does not care about - unit frames, bags, micro
-- menu, cast bar, minimap - then carries Blizzard's own correct entry, and
-- there is no chance of shipping a layout that is missing a system or has one
-- shaped wrong.
--------------------------------------------------------------------------

local function presetSystems()
    local mgr = _G["EditModePresetLayoutManager"]
    if not (mgr and mgr.GetCopyOfPresetLayouts) then return nil end

    local ok, presets = pcall(mgr.GetCopyOfPresetLayouts, mgr)
    if not ok or type(presets) ~= "table" or #presets == 0 then return nil end

    -- Prefer the Classic preset when the client offers both.
    local wanted = Enum and Enum.EditModePresetLayouts and Enum.EditModePresetLayouts.Classic
    for _, preset in ipairs(presets) do
        if wanted and preset.layoutIndex == wanted and preset.systems then
            return CopyTable(preset.systems)
        end
    end
    return presets[1].systems and CopyTable(presets[1].systems) or nil
end

local function findSystem(systems, system, systemIndex)
    for _, entry in ipairs(systems) do
        if entry.system == system and entry.systemIndex == systemIndex then return entry end
    end
end

-- settings is an array of {setting=, value=} pairs, not a map, so a plain
-- table assignment would silently add a numeric key and change nothing.
local function setSetting(entry, setting, value)
    if setting == nil then return end
    entry.settings = entry.settings or {}
    for _, s in ipairs(entry.settings) do
        if s.setting == setting then
            s.value = value
            return
        end
    end
    table.insert(entry.settings, { setting = setting, value = value })
end

function Layout:Build()
    local systems = presetSystems()
    if not systems then return nil, "no preset layout to build on" end

    local geo = geometry()
    if not geo then return nil, "Edit Mode action bar enums missing" end

    local S = Enum.EditModeActionBarSetting
    local barSystem = Enum.EditModeSystem.ActionBar

    local touched = 0
    for _, def in ipairs(geo) do
        local entry = findSystem(systems, barSystem, def.index)
        if entry then
            entry.anchorInfo = {
                point = def.point,
                relativeTo = def.relativeTo,
                relativePoint = def.relativePoint,
                offsetX = def.x,
                offsetY = def.y,
            }
            -- Anything we have moved is by definition no longer where
            -- Blizzard put it; leaving this true makes Edit Mode treat the
            -- system as untouched and re-slam it to the preset anchor.
            entry.isInDefaultPosition = false

            setSetting(entry, S.NumRows, def.rows)
            setSetting(entry, S.IconSize, ICON_SIZE)
            setSetting(entry, S.IconPadding, ICON_PADDING)
            touched = touched + 1
        end
    end

    if touched == 0 then return nil, "found no action bar systems to position" end
    return systems, touched
end

--------------------------------------------------------------------------
-- Applying
--------------------------------------------------------------------------

local function layoutIndexByName(info, name)
    for i, l in ipairs(info.layouts or {}) do
        if l.layoutName == name then return i end
    end
end

function Layout:Apply(silent)
    if InCombatLockdown() then
        if not silent then ns:Print("layout: not in combat - try again after") end
        return false
    end

    if not (C_EditMode and C_EditMode.GetLayouts and C_EditMode.SaveLayouts) then
        if not silent then ns:Print("layout: |cffff8080this client has no C_EditMode|r") end
        return false
    end

    local systems, err = Layout:Build()
    if not systems then
        if not silent then ns:Print("layout: |cffff8080%s|r", tostring(err)) end
        return false
    end

    local ok, info = pcall(C_EditMode.GetLayouts)
    if not ok or type(info) ~= "table" or type(info.layouts) ~= "table" then
        if not silent then ns:Print("layout: |cffff8080could not read the layout list|r") end
        return false
    end

    local name = layoutName()
    local index = layoutIndexByName(info, name)
    local created = false

    if index then
        -- Refresh in place: this is also what "reset it back to the HelloUI
        -- default" means, since Edit Mode saves any dragging you did straight
        -- into this layout. Only ever HelloUI's own layout; the player's are
        -- never written to.
        info.layouts[index].systems = systems
    else
        local wantType = layoutType()

        -- Blizzard caps each type at 5 and refuses the save past that, so
        -- check first and say which type is full.
        local sameType = 0
        for _, l in ipairs(info.layouts) do
            if l.layoutType == wantType then sameType = sameType + 1 end
        end
        if sameType >= MAX_PER_TYPE then
            if not silent then
                ns:Print("layout: |cffff8080you already have %d %s layouts|r - delete one in Edit Mode first",
                    MAX_PER_TYPE, perCharacter() and "character" or "account")
            end
            return false
        end

        if C_EditMode.IsValidLayoutName then
            local valid, isValid = pcall(C_EditMode.IsValidLayoutName, name)
            if valid and isValid == false then
                if not silent then ns:Print("layout: |cffff8080the client rejected the name '%s'|r", name) end
                return false
            end
        end

        table.insert(info.layouts, {
            layoutName = name,
            layoutType = wantType,
            systems = systems,
        })
        index = #info.layouts
        created = true
    end

    local saved = pcall(C_EditMode.SaveLayouts, info)
    if not saved then
        if not silent then ns:Print("layout: |cffff8080the client rejected the layout|r") end
        return false
    end

    -- OnLayoutAdded is the "a new one appeared, switch to it" path; an
    -- existing layout is activated directly.
    if created and C_EditMode.OnLayoutAdded then
        pcall(C_EditMode.OnLayoutAdded, index, true, false)
    elseif C_EditMode.SetActiveLayout then
        pcall(C_EditMode.SetActiveLayout, index)
    end

    Layout.applied = true
    ns:Print("layout: %s the |cffffd100%s|r Edit Mode layout%s and switched to it",
        created and "created" or "reset", name,
        perCharacter() and " |cff808080(this character only)|r" or "")
    ns:Print("  |cff808080your own layouts are untouched - switch back any time in Edit Mode|r")
    return true
end

--------------------------------------------------------------------------
-- One-time application
--
-- Deliberately latched. Re-applying on every login would undo any bar the
-- player has since dragged, which is precisely the "addon owns your layout"
-- behaviour this whole design is written against.
--------------------------------------------------------------------------

function Layout:Init()
    -- PLAYER_ENTERING_WORLD also fires on every zone and instance change, so
    -- the prompt is gated on a session flag as well as on whether the layout
    -- is already active.
    ns:On("PLAYER_ENTERING_WORLD", function()
        ns:WhenSafe("Layout:ask", function() Layout:MaybeAsk() end)
    end)
end

-- "Reset" and "apply" are the same operation - rebuild from the shipped
-- geometry and overwrite - because Edit Mode saves your dragging into the
-- layout itself. Named separately because that is not obvious.
function Layout:Reset()
    return Layout:Apply()
end

--------------------------------------------------------------------------
-- Asking, rather than deciding
--
-- Silently rewriting somebody's UI layout at login is exactly the kind of
-- thing this addon spends the rest of its comments refusing to do. So it
-- asks, once per session, and only when its layout is not already the active
-- one - which means the question disappears for good the moment you say yes.
--
-- "Never" is a real button rather than a buried setting, because a prompt you
-- cannot dismiss permanently is worse than no prompt.
--------------------------------------------------------------------------

function Layout:IsActive()
    if not (C_EditMode and C_EditMode.GetLayouts) then return false end
    local ok, info = pcall(C_EditMode.GetLayouts)
    if not ok or type(info) ~= "table" then return false end
    local index = layoutIndexByName(info, layoutName())
    return index ~= nil and info.activeLayout == index
end

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["HELLOUI_USE_LAYOUT"] = {
    text = "Use the HelloUI bar layout?\n\n|cff808080Bars stacked and centred, the way DragonflightUI "
        .. "had them. This adds an Edit Mode layout and switches to it - your own layouts are not "
        .. "touched, and you can switch back in Edit Mode at any time.|r",
    button1 = "Use it",
    button2 = "Not now",
    button3 = "Never",
    OnAccept = function() ns.Layout:Apply() end,
    OnCancel = function() end,
    -- button3 is the "alt" action in this template.
    OnAlt = function()
        ns.Config:Set("askLayout", false)
        ns:Print("layout: won't ask again - |cff808080/hui layout|r applies it whenever you want")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = false,
    preferredIndex = 3,
}

local askedThisSession = false

function Layout:MaybeAsk()
    if askedThisSession then return end
    if not Config:Enabled("askLayout") then return end
    if not (C_EditMode and C_EditMode.GetLayouts) then return end
    if Layout:IsActive() then return end

    askedThisSession = true
    if StaticPopup_Show then StaticPopup_Show("HELLOUI_USE_LAYOUT") end
end

function Layout:StatusText()
    if not (C_EditMode and C_EditMode.GetLayouts) then
        return "layout: |cffffd100no C_EditMode|r"
    end
    return nil
end

function Layout:Status()
    if not (C_EditMode and C_EditMode.GetLayouts) then
        ns:Print("layout: |cffffd100C_EditMode not available|r")
        return
    end
    local ok, info = pcall(C_EditMode.GetLayouts)
    if not ok or type(info) ~= "table" then
        ns:Print("layout: |cffff8080could not read the layout list|r")
        return
    end
    local name = layoutName()
    local index = layoutIndexByName(info, name)
    ns:Print("layout: %s%s",
        index and ("|cffffd100" .. name .. "|r exists at slot " .. index) or ("|cffffd100" .. name .. "|r not created"),
        (index and info.activeLayout == index) and " |cff808080(active)|r" or "")
    ns:Print("  |cff808080mode: %s%s, prompt at login: %s|r",
        perCharacter() and "per character" or "account-wide",
        Config:HasChar("layoutPerCharacter") and " (character override)" or "",
        tostring(Config:Enabled("askLayout") and true or false))
end
