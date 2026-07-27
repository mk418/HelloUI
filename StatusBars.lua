local ADDON_NAME, ns = ...

ns.StatusBars = {}
local StatusBars = ns.StatusBars

local Config = ns.Config

-- These are addon-owned frames. Blizzard's tracking manager remains in place
-- for its secure bookkeeping, but is only made transparent while HelloUI is
-- enabled. In particular, never resize its containers, hook UpdateBarVisuals,
-- or call one of its update methods: UI panel positioning reaches that manager
-- before the Game Menu invokes its protected Logout/Exit callback.
local WIDTH = 454
local HEIGHT = 10
local GAP = 1
local BOTTOM = 3

local bars = {}
local stockAlpha

local function formatNumber(value)
    value = math.floor((tonumber(value) or 0) + 0.5)
    if BreakUpLargeNumbers then
        local ok, text = pcall(BreakUpLargeNumbers, value)
        if ok and text then return text end
    end
    return tostring(value)
end

local function setStockVisible(visible)
    local manager = _G["StatusTrackingBarManager"]
    if not (manager and manager.SetAlpha and manager.GetAlpha) then return end

    if stockAlpha == nil then stockAlpha = manager:GetAlpha() end
    manager:SetAlpha(visible and stockAlpha or 0)
end

local function showTooltip(bar)
    local data = bar.data
    if not data then return end

    GameTooltip:SetOwner(bar, "ANCHOR_TOP")
    GameTooltip:AddLine(data.label, 1, 1, 1)
    GameTooltip:AddLine(("%s / %s (%.1f%%)"):format(
        formatNumber(data.value), formatNumber(data.max), data.percent))
    if data.rested and data.rested > 0 then
        GameTooltip:AddLine(("Rested: %s"):format(formatNumber(data.rested)), 0.3, 0.6, 1)
    end
    GameTooltip:Show()
end

local function createBar(name)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(true)

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0.03, 0.03, 0.03, 0.9)

    -- Rested XP is drawn first and extends beyond the current-XP fill. The
    -- normal fill, created second, covers the portion already earned.
    local rested = CreateFrame("StatusBar", nil, frame)
    rested:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    rested:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    rested:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    rested:SetStatusBarColor(0.10, 0.32, 0.72, 1)

    local fill = CreateFrame("StatusBar", nil, frame)
    fill:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
    fill:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")

    -- Put the label on the top status-bar frame, not its parent: child-frame
    -- level ordering otherwise allows the fill to cover a parent FontString
    -- even when that FontString uses the OVERLAY draw layer.
    local text = fill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetWidth(WIDTH - 8)
    text:SetWordWrap(false)
    text:SetMaxLines(1)

    frame.rested = rested
    frame.fill = fill
    frame.text = text
    frame:SetScript("OnEnter", showTooltip)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:Hide()
    return frame
end

local function ensureBars()
    if bars.xp then return end
    bars.xp = createBar("HelloUIXPBar")
    bars.rep = createBar("HelloUIRepBar")
end

local function setBar(bar, label, value, maximum, color, rested)
    maximum = tonumber(maximum) or 0
    if maximum <= 0 then
        bar.data = nil
        bar:Hide()
        return false
    end

    value = math.max(0, math.min(tonumber(value) or 0, maximum))
    rested = math.max(0, tonumber(rested) or 0)
    local percent = value / maximum * 100

    bar.rested:SetMinMaxValues(0, maximum)
    bar.rested:SetValue(rested > 0 and math.min(maximum, value + rested) or 0)
    bar.fill:SetMinMaxValues(0, maximum)
    bar.fill:SetValue(value)
    bar.fill:SetStatusBarColor(color.r, color.g, color.b, 1)
    bar.text:SetText(("%s  %s / %s  %.1f%%"):format(
        label, formatNumber(value), formatNumber(maximum), percent))
    bar.data = {
        label = label,
        value = value,
        max = maximum,
        percent = percent,
        rested = rested,
    }
    bar:Show()
    return true
end

local function playerIsMaxLevel()
    if not UnitLevel then return false end

    local level = UnitLevel("player")
    if not level then return false end

    local getCap = GetMaxPlayerLevel or GetMaxLevelForPlayerExpansion
        or (C_PlayerInfo and C_PlayerInfo.GetMaxLevelForPlayerExpansion)
    if not getCap then return false end

    local ok, cap = pcall(getCap)
    return ok and type(cap) == "number" and cap > 0 and level >= cap
end

local function updateXP()
    if not (UnitXP and UnitXPMax) then
        bars.xp:Hide()
        return false
    end

    -- UnitXPMax is not consistently zero at cap across Classic clients. Use
    -- the explicit player cap first, with the zero-maximum check below as the
    -- compatibility fallback when no cap API exists.
    if playerIsMaxLevel() then
        bars.xp:Hide()
        bars.xp.data = nil
        return false
    end

    local maximum = UnitXPMax("player") or 0
    local current = UnitXP("player") or 0
    local rested = GetXPExhaustion and GetXPExhaustion() or 0
    return setBar(bars.xp, "XP", current, maximum,
        { r = 0.58, g = 0.18, b = 0.72 }, rested)
end

local function watchedFaction()
    if C_Reputation and C_Reputation.GetWatchedFactionData then
        local ok, first, standing, minimum, maximum, value =
            pcall(C_Reputation.GetWatchedFactionData)
        if ok and type(first) == "table" then
            local data = first
            return data.name, data.reaction or data.standingID,
                data.currentReactionThreshold or data.barMin,
                data.nextReactionThreshold or data.barMax,
                data.currentStanding or data.barValue
        elseif ok and first then
            return first, standing, minimum, maximum, value
        end
    end

    if GetWatchedFactionInfo then
        local ok, name, standing, minimum, maximum, value = pcall(GetWatchedFactionInfo)
        if ok then return name, standing, minimum, maximum, value end
    end
end

local function reputationColor(standing)
    local color = FACTION_BAR_COLORS and FACTION_BAR_COLORS[standing or 0]
    if color then return color end
    return { r = 0.10, g = 0.65, b = 0.20 }
end

local function updateReputation()
    local name, standing, minimum, maximum, value = watchedFaction()
    if not (name and minimum and maximum and value) then
        bars.rep:Hide()
        bars.rep.data = nil
        return false
    end

    return setBar(bars.rep, name, value - minimum, maximum - minimum,
        reputationColor(standing), 0)
end

local function positionVisibleBars(xpVisible, repVisible)
    local index = 0
    for _, entry in ipairs({
        { bar = bars.xp, visible = xpVisible },
        { bar = bars.rep, visible = repVisible },
    }) do
        if entry.visible then
            entry.bar:ClearAllPoints()
            entry.bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0,
                BOTTOM + index * (HEIGHT + GAP))
            index = index + 1
        end
    end
end

function StatusBars:Refresh()
    ensureBars()
    if not Config:Enabled() then
        bars.xp:Hide()
        bars.rep:Hide()
        return
    end

    setStockVisible(false)
    positionVisibleBars(updateXP(), updateReputation())
end

-- Older builds of HelloUI forced xpBarText on for Blizzard's bars. Restore the
-- player's saved value once now that the custom bars own their own text.
local function restoreLegacyCVar()
    local original = HelloUIDB and HelloUIDB.xpBarTextOriginal
    if original == nil then return end

    local getter = (C_CVar and C_CVar.GetCVar) or GetCVar
    local setter = (C_CVar and C_CVar.SetCVar) or SetCVar
    if getter and setter and getter("xpBarText") ~= original then
        pcall(setter, "xpBarText", original)
    end
    HelloUIDB.xpBarTextOriginal = nil
end

function StatusBars:Apply()
    ensureBars()
    restoreLegacyCVar()

    if Config:Enabled() then
        self:Refresh()
    else
        bars.xp:Hide()
        bars.rep:Hide()
        setStockVisible(true)
    end
end

function StatusBars:Init()
    ensureBars()

    ns:On("PLAYER_XP_UPDATE", function(unit)
        if not unit or unit == "player" then StatusBars:Refresh() end
    end)
    ns:On("UPDATE_EXHAUSTION", function() StatusBars:Refresh() end)
    ns:On("PLAYER_LEVEL_UP", function() StatusBars:Refresh() end)
    ns:On("UPDATE_FACTION", function() StatusBars:Refresh() end)
    ns:On("EDIT_MODE_LAYOUTS_UPDATED", function() StatusBars:Refresh() end)
end

function StatusBars:StatusText()
    if not (UnitXP and UnitXPMax) then
        return "status bars: |cffff8080XP API unavailable|r"
    end
    return nil
end

function StatusBars:Status()
    ensureBars()
    local manager = _G["StatusTrackingBarManager"]
    local alpha = manager and manager.GetAlpha and manager:GetAlpha() or "missing"
    ns:Print("status bars: custom XP=%s, reputation=%s |cff808080(%dx%d, stock alpha=%s)|r",
        tostring(bars.xp:IsShown()), tostring(bars.rep:IsShown()), WIDTH, HEIGHT,
        tostring(alpha))
end
