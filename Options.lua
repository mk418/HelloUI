local ADDON_NAME, ns = ...

ns.Options = {}
local Options = ns.Options

local Config = ns.Config

local panel = CreateFrame("Frame", "HelloUIOptionsPanel")
panel.name = "HelloUI"

--------------------------------------------------------------------------
-- Scroll wrapper
--
-- The Settings canvas is a fixed height - about 580 units, whatever the
-- resolution, since UIParent is always 768 tall - and this panel's left column
-- alone is taller than that. Anything past the bottom is not clipped by the
-- canvas: it draws over the game, which is what "the settings do not fit"
-- looked like on screen.
--
-- Rebalancing the columns would have bought one release: the panel gained two
-- checkboxes in a single afternoon. A scroll wrapper is what HelloHealer's
-- settings panel already does for the same reason, so it is also the shape the
-- family expects.
--
-- Everything below is parented to `content`, never to `panel`. A widget
-- attached to the panel instead escapes the scroll frame and floats over the
-- game again - the harness asserts against exactly that.
--------------------------------------------------------------------------

local scroll = CreateFrame("ScrollFrame", "HelloUIOptionsScroll", panel, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 8, -8)
scroll:SetPoint("BOTTOMRIGHT", -28, 8)

local content = CreateFrame("Frame", nil, scroll)
content:SetSize(560, 760)
scroll:SetScrollChild(content)

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
    local cb = CreateFrame("CheckButton", name, content, "UICheckButtonTemplate")
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

-- A key inside one of the nested tables (barsOff). Writes into the active
-- profile's copy of that table - there is only one place it can go now that
-- profiles replaced the account/override split.
local function SubCheck(suffix, label, anchor, relPoint, x, y, tableKey, key, tooltip)
    return MakeCheck("HelloUIOpt" .. suffix, label, anchor, relPoint, x, y,
        function() return Config:GetTable(tableKey)[key] end,
        function(v)
            -- Store a real boolean, never nil. Deleting the key looks
            -- equivalent - every consumer tests truthiness - but Config's
            -- applyDefaults recurses into these nested tables and refills any
            -- missing key from the defaults on the next ADDON_LOADED. A
            -- deleted key is indistinguishable from one never set, so
            -- unticking "bar 5" would come back ticked at the next login,
            -- forever.
            local t = Config:Get(tableKey)
            if type(t) ~= "table" then
                t = {}
                Config:Set(tableKey, t)
            end
            t[key] = v and true or false
        end,
        tooltip)
end

-- There are deliberately no sliders. Every setting this panel exposes is a
-- boolean, because every geometry the addon might have carried turned out to
-- belong to Edit Mode.

local function Header(text, anchor, relPoint, x, y)
    local fs = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", anchor, relPoint, x, y)
    fs:SetText(text)
    return fs
end

--------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------

local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("HelloUI")

local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetWidth(560)
subtitle:SetJustifyH("LEFT")
subtitle:SetText("De-clutters the stock interface. Stock-frame positioning goes through " ..
    "Blizzard Edit Mode; XP and reputation use compact addon-owned bars.")

-- What the addon does without being asked. Listed rather than left implicit:
-- these were checkboxes until they were not, and a panel that simply stopped
-- mentioning them would read as features that had been dropped.
local alwaysNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
alwaysNote:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -6)
alwaysNote:SetWidth(560)
alwaysNote:SetJustifyH("LEFT")
alwaysNote:SetSpacing(2)
alwaysNote:SetText("Always on: gryphons and bar backdrop hidden, compact XP and reputation " ..
    "bars, time-of-day dial hidden, class-coloured player health, and a flat " ..
    "cast bar that steps aside when a sibling addon draws its own, with a matching " ..
    "breath meter.")

local enabledCheck = SettingCheck("Enabled", "Enable HelloUI", alwaysNote, "BOTTOMLEFT", -2, -14, "enabled",
    "Master switch. Turning this off stops HelloUI re-asserting anything, " ..
    "but a /reload is what fully restores Blizzard's own state.")

-- Left column ----------------------------------------------------------

local barsHeader = Header("Action bars", enabledCheck, "BOTTOMLEFT", 2, -14)

local keybindCheck = SettingCheck("Keybind", "Hide keybind text", barsHeader, "BOTTOMLEFT", -2, -8,
    "hideKeybindText")

local macroCheck = SettingCheck("Macro", "Hide macro name text", keybindCheck, "BOTTOMLEFT", 0, -4,
    "hideMacroText")

local emptyCheck = SettingCheck("EmptySlots", "Show empty action slots",
    macroCheck, "BOTTOMLEFT", 0, -4, "showEmptyButtons",
    "On, bars keep their full rectangular shape - which is what makes the " ..
    "side blocks read as 4x3. Off, Blizzard hides empty slots, so a bar you " ..
    "have not filled vanishes instead of showing a grid of empty squares. " ..
    "Run /hui layout afterwards - this one lives in the Edit Mode layout.")

local offLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
offLabel:SetPoint("TOPLEFT", emptyCheck, "BOTTOMLEFT", 2, -8)
offLabel:SetText("Bars switched off:")

-- The eight numbered bars in one tight row - their labels are single digits,
-- so a column of "Hide action bar 6" would be a wall of noise - then stance
-- and pet underneath, where a real label fits.
local BAR_TOOLTIP = "Hides this bar entirely. The class addons (HelloWarrior, " ..
    "HelloTotems, HelloHealer) are additive by design and never hide Blizzard's " ..
    "bars, so this is how you make room for them. Visible HelloWarrior, HelloMage, " ..
    "HelloWarlock, HelloDruid, and HelloRogue clusters automatically make room without changing " ..
    "these saved choices."

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

-- No "Status bars" or "Unit frames" sections: the custom XP/reputation bars
-- and the class-coloured health bar are unconditional while HelloUI is on.

-- Right column ---------------------------------------------------------

local RIGHT = 300

local darkHeader = Header("Darkmode", barsHeader, "TOPLEFT", RIGHT, 0)

-- One switch, no sub-options. It used to carry a desaturate toggle and four
-- per-area checkboxes; nobody was going to tint the minimap but not the cast
-- bar, and the tint colour was three numbers nobody was going to change.
SettingCheck("Darkmode", "Desaturate and tint Blizzard's frame art",
    darkHeader, "BOTTOMLEFT", -2, -8, "darkmode",
    "Unit frames, the minimap and its buttons, the action bar backdrop and the " ..
    "cast bars - Blizzard's own art, desaturated and tinted grey. Never a " ..
    "sibling addon's icons, and never anything that uses desaturation as a " ..
    "signal.")

--------------------------------------------------------------------------
-- Buttons and live state
--------------------------------------------------------------------------

local layoutHeader = Header("Bar layout", stanceCheck, "BOTTOMLEFT", 2, -14)

-- What the layout actually covers. There used to be notes here and under the
-- minimap saying position was Edit Mode's job and to go drag it - written before
-- the layout existed, and wrong ever since: HelloUI writes the chat frame's
-- position and the minimap's size into the layout itself.
local layoutNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
layoutNote:SetPoint("TOPLEFT", layoutHeader, "BOTTOMLEFT", 2, -8)
layoutNote:SetWidth(260)
layoutNote:SetJustifyH("LEFT")
layoutNote:SetSpacing(2)
layoutNote:SetText("An Edit Mode layout named HelloUI: the action bars, cast " ..
    "bar, chat frame, minimap and its size, " ..
    "the micro menu and the bags. Drag any of it in Edit Mode afterwards - your " ..
    "changes are saved into the layout, and re-applying is the reset. With " ..
    "HelloHealer active, a separate Healer layout lowers chat into the space " ..
    "freed by the bottom-left action bar, shortens it to keep the healing frames " ..
    "clear, and keeps it above HelloBuffCap.")

local askCheck = SettingCheck("AskLayout", "Offer the HelloUI layout at login",
    layoutNote, "BOTTOMLEFT", -6, -12, "askLayout",
    "Asks once per session, and only when the HelloUI layout is not already " ..
    "the active one - so saying yes retires the question for good.")

--------------------------------------------------------------------------
-- Profiles
--
-- Everything above writes into the profile this character uses; this is where
-- you choose which one that is. The dropdown follows HelloBuffCap's, which is
-- the family's only precedent for one and works on this client.
--------------------------------------------------------------------------

local profileHeader = Header("Profile", askCheck, "BOTTOMLEFT", 2, -16)

local profileNote = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
profileNote:SetPoint("TOPLEFT", profileHeader, "BOTTOMLEFT", 2, -6)
profileNote:SetWidth(260)
profileNote:SetJustifyH("LEFT")
profileNote:SetSpacing(2)
profileNote:SetText("Every setting on this panel belongs to the profile below. " ..
    "Characters pick a profile each, so alts can differ - and the bar layout " ..
    "follows it too.")

-- UIDropDownMenuTemplate writes into Blizzard's shared DropDownList1 pool.
-- Keeping the profile selector addon-owned prevents that global state from
-- carrying HelloUI taint into the Game Menu's protected callbacks.
local profilePrev = CreateFrame("Button", "HelloUIOptProfilePrev", content, "UIPanelButtonTemplate")
profilePrev:SetSize(26, 22)
profilePrev:SetPoint("TOPLEFT", profileNote, "BOTTOMLEFT", 2, -6)
profilePrev:SetText("<")

local profileName = CreateFrame("Button", "HelloUIOptProfile", content, "UIPanelButtonTemplate")
profileName:SetSize(170, 22)
profileName:SetPoint("LEFT", profilePrev, "RIGHT", 4, 0)

local profileNext = CreateFrame("Button", "HelloUIOptProfileNext", content, "UIPanelButtonTemplate")
profileNext:SetSize(26, 22)
profileNext:SetPoint("LEFT", profileName, "RIGHT", 4, 0)
profileNext:SetText(">")

local function stepProfile(delta)
    local names = Config:ProfileNames()
    if #names < 2 then return end

    local current = 1
    for i, name in ipairs(names) do
        if name == Config:ProfileName() then
            current = i
            break
        end
    end

    local index = ((current - 1 + delta) % #names) + 1
    local name = names[index]
    Config:UseProfile(name)
    Apply()
    Options:Refresh()
    ns:Print("profile: switched to |cffffd100%s|r", name)
end

profilePrev:SetScript("OnClick", function() stepProfile(-1) end)
profileNext:SetScript("OnClick", function() stepProfile(1) end)

-- Naming a new profile needs a text box, and StaticPopup is the only one of
-- those that does not mean building a dialog frame from scratch.
StaticPopupDialogs["HELLOUI_NEW_PROFILE"] = {
    text = "Name for the new profile\n\n|cff808080It starts as a copy of the one you are on, "
        .. "and this character switches to it.|r",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    maxLetters = 24,
    OnAccept = function(self)
        local box = self.editBox or (self.GetEditBox and self:GetEditBox())
        local name = box and box:GetText() or ""
        local ok, err = Config:CopyProfile(name)
        if not ok then
            ns:Print("|cffff8080%s|r", err)
            return
        end
        Apply()
        Options:Refresh()
        ns:Print("profile: |cffffd100%s|r created and in use", name)
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

local newProfileBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
newProfileBtn:SetSize(150, 22)
newProfileBtn:SetPoint("TOPLEFT", profilePrev, "BOTTOMLEFT", 0, -6)
newProfileBtn:SetText("New from this one")
newProfileBtn:SetScript("OnClick", function()
    if StaticPopup_Show then StaticPopup_Show("HELLOUI_NEW_PROFILE") end
end)

local deleteProfileBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
deleteProfileBtn:SetSize(110, 22)
deleteProfileBtn:SetPoint("LEFT", newProfileBtn, "RIGHT", 8, 0)
deleteProfileBtn:SetText("Delete")
deleteProfileBtn:SetScript("OnClick", function()
    local name = Config:ProfileName()
    local ok, err = Config:DeleteProfile(name)
    if not ok then
        ns:Print("|cffff8080%s|r", err)
        return
    end
    Apply()
    Options:Refresh()
    ns:Print("profile: deleted |cffffd100%s|r - this character is on %s", name, Config:ProfileName())
end)

local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
resetBtn:SetSize(190, 22)
resetBtn:SetPoint("TOPLEFT", newProfileBtn, "BOTTOMLEFT", 0, -10)
resetBtn:SetText("Reset this profile")
resetBtn:SetScript("OnClick", function()
    local name = Config:ResetProfile()
    Apply()
    ns:Print("profile |cffffd100%s|r reset to defaults", name)
    Options:Refresh()
end)

-- Applying the layout is an action, not a setting: it writes an Edit Mode
-- layout once and then HelloUI is not involved. A checkbox would imply
-- HelloUI keeps enforcing it, which is exactly what it does not do.
local layoutBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
layoutBtn:SetSize(220, 22)
layoutBtn:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -8)
layoutBtn:SetText("Apply / reset the bar layout")
layoutBtn:SetScript("OnClick", function() ns.Layout:Apply() end)
layoutBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Apply / reset the bar layout", 1, 1, 1)
    GameTooltip:AddLine("Creates HelloUI's Edit Mode layout and switches to it: " ..
        "bars stacked and centred, 80% icons, 2px padding, and with them the cast " ..
        "bar, the chat frame, the minimap and its size, the micro menu and the " ..
        "bags - everything that would otherwise collide with the arrangement. Run " ..
        "it again to reset the layout back to that after you have dragged things " ..
        "around - Edit Mode saves your changes into the layout, so re-applying is " ..
        "the reset. With HelloHealer active, this uses the separate Healer layout " ..
        "and fits a shorter chat near the bottom-left between HelloBuffCap and " ..
        "the healing frames. Your own layouts are never touched.",
        nil, nil, nil, true)
    GameTooltip:Show()
end)
layoutBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local status = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
status:SetPoint("TOPLEFT", layoutBtn, "BOTTOMLEFT", 0, -14)
status:SetWidth(560)
status:SetJustifyH("LEFT")
status:SetSpacing(2)

--------------------------------------------------------------------------
-- Refresh
--------------------------------------------------------------------------

-- The scroll child's height IS the scrollbar's range, so a constant would
-- either cut the last control off or scroll into empty space. Measured from the
-- lowest element instead - the status text, which is the one thing here that
-- changes height, since it grows a line when this character has overrides.
--
-- No feedback loop: the status text's position comes from the anchor chain down
-- from the content frame's TOP, so it does not move when the height below it
-- changes. Only runs once the panel has been shown and laid out, hence the
-- guard: before that the rects are nil and the initial size stands.
local function fitContent()
    if not (content.GetTop and status.GetBottom) then return end
    local top, bottom = content:GetTop(), status:GetBottom()
    if not (top and bottom) then return end
    content:SetHeight(math.max(200, top - bottom + 24))
end

function Options:Refresh()
    for _, cb in ipairs(checks) do
        cb:SetChecked(cb.getValue() and true or false)
    end

    profileName:SetText(Config:ProfileName())

    local lines = {}

    local names = Config:ProfileNames()
    lines[#lines + 1] = ("This character is on the |cffffd100%s|r profile, of %d. " ..
        "|cff808080Everything on this panel, and the bar layout, belongs to it.|r")
        :format(Config:ProfileName(), #names)

    -- What each module actually found on this client. Several of the frames
    -- involved could not be verified against a running client while this was
    -- written, so saying plainly which ones resolved beats implying they all did.
    local found = {}
    for _, name in ipairs(ns.EXTRA_MODULES) do
        local m = ns[name]
        if m and m.StatusText then
            local text = m:StatusText()
            if text then found[#found + 1] = text end
        end
    end
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

    -- After the text is set, so a two-line status is measured as two lines.
    fitContent()
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
