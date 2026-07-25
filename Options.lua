local ADDON_NAME, ns = ...

ns.Options = {}
local Options = ns.Options

local Config = ns.Config

local panel = CreateFrame("Frame", "HelloUIOptionsPanel")
panel.name = "HelloUI"

local checks = {}

-- Every control writes straight into the settings table and re-applies, so
-- there is no apply/cancel state to keep in sync. Applies route through the
-- combat queue because several of them touch protected frames.
local function Apply()
    ns:ApplyAllWhenSafe()
end

--------------------------------------------------------------------------
-- Widget factories
--
-- InterfaceOptionsCheckButtonTemplate survives on 1.15.9 only inside
-- Blizzard's DeprecatedTemplates.xml, where it is UICheckButtonTemplate at
-- 26x26 plus an OnClick sound we overwrite anyway - so inherit the
-- non-deprecated base, exactly as HelloRangeDisplay does.
--------------------------------------------------------------------------

local function MakeCheck(name, label, anchor, relPoint, x, y, get, set, tooltip)
    local cb = CreateFrame("CheckButton", name, panel, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", anchor, relPoint, x, y)
    local text = _G[name .. "Text"] or cb.Text
    if text then text:SetText(label) end
    cb:SetScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        Apply()
    end)
    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(label, 1, 1, 1)
            GameTooltip:AddLine(tooltip, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    cb.getValue = get
    checks[#checks + 1] = cb
    return cb
end

-- A plain account-wide setting.
local function SettingCheck(suffix, label, anchor, relPoint, x, y, key, tooltip)
    return MakeCheck("HelloUIOpt" .. suffix, label, anchor, relPoint, x, y,
        function() return Config:Get(key) end,
        function(v) Config:Set(key, v) end,
        tooltip)
end

-- A key inside one of the nested tables (darkmodeAreas, barsOff). Writes to
-- the account table unless this character already has an override for the
-- whole table, in which case it writes there - so a per-character bar layout
-- stays per-character once you have made one.
local function SubCheck(suffix, label, anchor, relPoint, x, y, tableKey, key, tooltip)
    return MakeCheck("HelloUIOpt" .. suffix, label, anchor, relPoint, x, y,
        function() return Config:GetTable(tableKey)[key] end,
        function(v)
            if Config:HasChar(tableKey) then
                local t = Config:Get(tableKey)
                t[key] = v or nil
            else
                HelloUIDB[tableKey] = HelloUIDB[tableKey] or {}
                HelloUIDB[tableKey][key] = v or nil
            end
        end,
        tooltip)
end

-- There are deliberately no sliders. Every setting this panel exposes is a
-- boolean, and the one geometry the addon carries - the chat frame's size and
-- position - is captured from wherever you have dragged the frame with
-- `/hui chat save` rather than dialled in by hand.

local function Header(text, anchor, relPoint, x, y)
    local fs = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", anchor, relPoint, x, y)
    fs:SetText(text)
    return fs
end

--------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("HelloUI")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetWidth(560)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("De-clutters the stock interface. No art overhaul, no replacement frames - " ..
    "position is Blizzard Edit Mode's job.")

local enabledCheck = SettingCheck("Enabled", "Enable HelloUI", subtitle, "BOTTOMLEFT", -2, -14, "enabled",
    "Master switch. Turning this off stops HelloUI re-asserting anything, " ..
    "but a /reload is what fully restores Blizzard's own state.")

-- Left column ----------------------------------------------------------

local barsHeader = Header("Action bars", enabledCheck, "BOTTOMLEFT", 2, -14)

local keybindCheck = SettingCheck("Keybind", "Hide keybind text", barsHeader, "BOTTOMLEFT", -2, -8,
    "hideKeybindText")

local macroCheck = SettingCheck("Macro", "Hide macro name text", keybindCheck, "BOTTOMLEFT", 0, -4,
    "hideMacroText")

local offLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
offLabel:SetPoint("TOPLEFT", macroCheck, "BOTTOMLEFT", 2, -8)
offLabel:SetText("Bars switched off:")

-- The eight numbered bars in one tight row - their labels are single digits,
-- so a column of "Hide action bar 6" would be a wall of noise - then stance
-- and pet underneath, where a real label fits.
local BAR_TOOLTIP = "Hides this bar entirely. The class addons (HelloWarrior, " ..
    "HelloTotems, HelloHealer) are additive by design and never hide Blizzard's " ..
    "bars, so this is how you make room for them."

local barChecks = {}
for i = 1, 8 do
    barChecks[i] = SubCheck("BarOffbar" .. i, tostring(i),
        (i == 1) and offLabel or barChecks[1],
        (i == 1) and "BOTTOMLEFT" or "TOPLEFT",
        (i == 1) and -2 or ((i - 1) * 34), (i == 1) and -6 or 0,
        "barsOff", "bar" .. i, BAR_TOOLTIP)
end

local stanceCheck = SubCheck("BarOffstance", "Stance", barChecks[1], "TOPLEFT",
    0, -26, "barsOff", "stance", BAR_TOOLTIP)

SubCheck("BarOffpet", "Pet", stanceCheck, "TOPLEFT",
    80, 0, "barsOff", "pet", BAR_TOOLTIP)

local statusHeader = Header("Status bars", stanceCheck, "BOTTOMLEFT", 2, -14)

-- One checkbox, not two. Stock 1.15.9 runs the XP bar and the reputation bar
-- through the same ShouldBarTextBeDisplayed, so there is a single native
-- switch behind both and offering two would be a lie.
local barTextCheck = SettingCheck("BarText", "XP and reputation bar text always visible",
    statusHeader, "BOTTOMLEFT", -2, -8, "alwaysShowBarText",
    "Otherwise the numbers only appear when you mouse over the bar. This is " ..
    "Blizzard's own xpBarText setting, and it covers both bars together.")

local unitHeader = Header("Unit frames", barTextCheck, "BOTTOMLEFT", 2, -14)

local classColorCheck = SettingCheck("ClassColor", "Class-colour the player health bar",
    unitHeader, "BOTTOMLEFT", -2, -8, "classColorPlayerHealth")

local chatCheck = SettingCheck("Chat", "Pin the chat frame's size and position",
    classColorCheck, "BOTTOMLEFT", 0, -4, "chatAnchor",
    "Re-applies on login. Drag the chat frame yourself and this will put it back.")

-- Right column ---------------------------------------------------------

local RIGHT = 300

local darkHeader = Header("Darkmode", barsHeader, "TOPLEFT", RIGHT, 0)

local darkCheck = SettingCheck("Darkmode", "Desaturate and tint frame art",
    darkHeader, "BOTTOMLEFT", -2, -8, "darkmode")

local desatCheck = SettingCheck("Desaturate", "Desaturate (off = tint only)",
    darkCheck, "BOTTOMLEFT", 12, -4, "darkmodeDesaturate")

-- Four areas, not the old profile's six. `buffs` has no stock target and
-- `ui` was already a no-op - see Darkmode.lua.
local AREAS = {
    { "unitframes", "Unit frames" },
    { "minimap",    "Minimap" },
    { "actionbars", "Action bar art" },
    { "castbar",    "Cast bar" },
}

local areaChecks = {}
for i, def in ipairs(AREAS) do
    local id, label = def[1], def[2]
    areaChecks[i] = SubCheck("Area" .. id, label,
        (i == 1) and desatCheck or areaChecks[i - 1], "BOTTOMLEFT",
        (i == 1) and 0 or 0, -4, "darkmodeAreas", id)
end

local minimapHeader = Header("Minimap", areaChecks[#areaChecks], "BOTTOMLEFT", 2, -14)

-- Not "calendar": Classic Era loads GameTime_NoCalendar, so this button is
-- the time-of-day dial and has no calendar behind it.
local todCheck = SettingCheck("TimeOfDay", "Hide the time-of-day dial",
    minimapHeader, "BOTTOMLEFT", -2, -8, "hideTimeOfDay",
    "The sun/moon icon on the minimap ring. On Classic Era it is not a " ..
    "calendar button - it has no click action at all.")

local minimapNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
minimapNote:SetPoint("TOPLEFT", todCheck, "BOTTOMLEFT", 4, -4)
minimapNote:SetWidth(260)
minimapNote:SetJustifyH("LEFT")
minimapNote:SetSpacing(2)
minimapNote:SetText("Position is Edit Mode's job. Stock is already flush " ..
    "top-right, and the minimap is an Edit Mode system - drag it there.")

local friendsHeader = Header("Friends", minimapNote, "BOTTOMLEFT", -6, -18)

local friendsCheck = SettingCheck("Friends", "Class-colour the friends list",
    friendsHeader, "BOTTOMLEFT", -2, -8, "friendsClassColor")

SettingCheck("Heart", "Heart icon for notes containing <3",
    friendsCheck, "BOTTOMLEFT", 12, -4, "friendsHeart")

--------------------------------------------------------------------------
-- Buttons and live state
--------------------------------------------------------------------------

local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
resetBtn:SetSize(140, 22)
resetBtn:SetPoint("TOPLEFT", chatCheck, "BOTTOMLEFT", 2, -20)
resetBtn:SetText("Reset settings")
resetBtn:SetScript("OnClick", function()
    Config:ResetAccount()
    Apply()
    ns:Print("account settings reset to defaults")
    Options:Refresh()
end)

local clearCharBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
clearCharBtn:SetSize(170, 22)
clearCharBtn:SetPoint("LEFT", resetBtn, "RIGHT", 8, 0)
clearCharBtn:SetText("Clear character overrides")
clearCharBtn:SetScript("OnClick", function()
    Config:ResetChar()
    Apply()
    ns:Print("character overrides cleared")
    Options:Refresh()
end)

local status = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
status:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -14)
status:SetWidth(560)
status:SetJustifyH("LEFT")
status:SetSpacing(2)

--------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------

function Options:Refresh()
    for _, cb in ipairs(checks) do
        cb:SetChecked(cb.getValue() and true or false)
    end

    local lines = {}

    if Config:HasAnyCharOverride() then
        lines[#lines + 1] = "This character overrides: |cffffd100" ..
            Config:CharOverrideList() .. "|r. Everything else follows the account layout."
    else
        lines[#lines + 1] = "This character uses the account layout. " ..
            "|cff808080/hui char barsoff bar1 stance|r overrides just the bars, here only."
    end

    -- What each module actually found on this client. Several of the frames
    -- involved could not be verified against a running client while this was
    -- written, so saying plainly which ones resolved beats implying they all did.
    local found = {}
    for _, name in ipairs(ns.MODULES) do
        local m = ns[name]
        if m and m.StatusText then
            local text = m:StatusText()
            if text then found[#found + 1] = text end
        end
    end
    if #found > 0 then
        lines[#lines + 1] = "|cff808080" .. table.concat(found, "  |  ") .. "|r"
    end

    status:SetText(table.concat(lines, "\n"))
end

panel:SetScript("OnShow", function() Options:Refresh() end)

--------------------------------------------------------------------------
-- Registration
--------------------------------------------------------------------------

function Options:Init()
    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "HelloUI")
        -- Do not override category.ID with a string: since 1.15.9,
        -- Settings.OpenToCategory feeds the ID straight into the native
        -- C_SettingsUtil.OpenSettingsPanel, which requires the auto-assigned
        -- numeric ID and errors on anything else.
        Settings.RegisterAddOnCategory(category)
        Options.categoryID = category:GetID()
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function Options:Open()
    if Settings and Settings.OpenToCategory and Options.categoryID then
        Settings.OpenToCategory(Options.categoryID)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    else
        ns:Print("could not open the settings panel on this client")
    end
end
