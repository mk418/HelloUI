local ADDON_NAME, ns = ...

ns.Player = {}
local Player = ns.Player

local Config = ns.Config

--------------------------------------------------------------------------
-- Class-coloured player health bar
--
-- Do not write `PlayerFrameHealthBar.lockColor`. Although Blizzard supports
-- the field, its shared UnitFrameHealthBar_Update path reads it before updating
-- player, target and target-of-target frames. An addon-written control-flow
-- value can therefore carry taint into TargetFrameToT's protected show/anchor
-- work. A secure post-hook is the safer boundary: Blizzard completes its
-- update first, then HelloUI changes only the player bar's visual colour.
--
-- The bar is still a named global on 1.15.9 - PlayerFrame.xml declares
-- `<StatusBar name="PlayerFrameHealthBar" parentKey="HealthBar">` as a
-- direct child of PlayerFrame - so both the global and PlayerFrame.HealthBar
-- resolve. Preferring the global keeps this readable; the fallback covers a
-- future rename.
--
-- Deliberately no texture swap. DragonflightUI replaced the bar texture with
-- its own art because it had art; on stock the default status bar texture
-- takes a colour fine, and swapping it would be the beginning of the
-- overhaul this addon exists not to be.
--------------------------------------------------------------------------

local function healthBar()
    return _G["PlayerFrameHealthBar"]
        or (_G["PlayerFrame"] and (_G["PlayerFrame"].HealthBar or _G["PlayerFrame"].healthbar))
end

local original = nil

local function setClassColor(bar)
    local _, class = UnitClass("player")
    local r, g, b = ns:ClassColor(class)
    bar:SetStatusBarColor(r, g, b, 1)
end

--------------------------------------------------------------------------
-- Target-of-target position guard
--
-- TargetFrameToT is protected and not an Edit Mode system of its own. Login
-- detection is read-only. A repair is performed only from a StaticPopup button
-- click, preserving the hardware-event authority required by both the frame
-- methods and C_UI.Reload. Never defer a repair through a timer, pcall queue or
-- PLAYER_REGEN_ENABLED: that loses the click and produces ADDON_ACTION_BLOCKED.
--------------------------------------------------------------------------

local TOT_POINT = "BOTTOMRIGHT"
local TOT_X, TOT_Y = -16, -14
local POSITION_EPSILON = 0.01

local function sameOffset(actual, expected)
    return type(actual) == "number" and math.abs(actual - expected) <= POSITION_EPSILON
end

local function targetOfTargetFrames()
    return _G["TargetFrameToT"], _G["TargetFrame"]
end

function Player:TargetOfTargetNeedsRepair()
    local frame, target = targetOfTargetFrames()
    if not (frame and target and frame.GetPoint and frame.GetParent) then return false end

    local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
    return frame:GetParent() ~= target
        or point ~= TOT_POINT
        or relativeTo ~= target
        or relativePoint ~= TOT_POINT
        or not sameOffset(x, TOT_X)
        or not sameOffset(y, TOT_Y)
end

local function repairTargetOfTarget(stage)
    if InCombatLockdown and InCombatLockdown() then
        Player.targetOfTargetRetryAfterCombat = true
        Player.checkedTargetOfTargetThisSession = false
        Player.askedTargetOfTargetThisSession = false
        ns:Print("target-of-target: leave combat, then accept the repair prompt again")
        return false
    end

    local frame, target = targetOfTargetFrames()
    if not (frame and target and frame.SetUserPlaced and frame.ClearAllPoints and frame.SetPoint) then
        ns:Print("target-of-target: |cffff8080frame not available|r")
        return false
    end

    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:SetUserPlaced(false)
    frame:ClearAllPoints()
    frame:SetPoint(TOT_POINT, target, TOT_POINT, TOT_X, TOT_Y)

    HelloUICharDB = HelloUICharDB or {}
    HelloUICharDB.targetOfTargetRepairStage = stage
    ns:Print(stage == 1
        and "target-of-target: restored Blizzard's attachment; reloading the UI"
        or "target-of-target: finished clearing the saved position; reloading the UI")

    -- This function is called directly by StaticPopup OnAccept. Do not move
    -- ReloadUI into the delayed detection path: C_UI.Reload is protected there.
    local reload = _G["ReloadUI"]
    if reload then reload() end
    return true
end

StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["HELLOUI_FIX_TARGET_OF_TARGET"] = {
    text = "The target-of-target frame has a saved position that no longer attaches it to the target frame.\n\n"
        .. "|cff808080HelloUI can restore Blizzard's normal attachment. Classic Era may retain the stale entry "
        .. "for one reload; if so, a second user-confirmed pass is required because this protected work cannot "
        .. "run automatically.|r",
    button1 = "Fix and reload",
    button2 = "Not now",
    OnAccept = function() repairTargetOfTarget(1) end,
    OnCancel = function() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = false,
    preferredIndex = 4,
}

StaticPopupDialogs["HELLOUI_FINISH_TARGET_OF_TARGET"] = {
    text = "Classic Era restored the old target-of-target position once more.\n\n"
        .. "|cff808080Click Finish repair to clear the remaining saved entry. This second click is required by "
        .. "WoW's protected-frame rules; HelloUI will not run it automatically.|r",
    button1 = "Finish repair",
    button2 = "Not now",
    OnAccept = function() repairTargetOfTarget(2) end,
    OnCancel = function() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = false,
    preferredIndex = 4,
}

Player.askedTargetOfTargetThisSession = false
Player.checkedTargetOfTargetThisSession = false
Player.targetOfTargetCheckScheduled = false

function Player:MaybeAskTargetOfTarget()
    if Player.checkedTargetOfTargetThisSession then return end
    Player.checkedTargetOfTargetThisSession = true
    if Player.askedTargetOfTargetThisSession or not Config:Enabled() then return end

    local needsRepair = Player:TargetOfTargetNeedsRepair()
    local stage = HelloUICharDB and HelloUICharDB.targetOfTargetRepairStage
    if not needsRepair then
        if HelloUICharDB then HelloUICharDB.targetOfTargetRepairStage = nil end
        return
    end

    Player.askedTargetOfTargetThisSession = true
    if StaticPopup_Show then
        StaticPopup_Show(stage == 1
            and "HELLOUI_FINISH_TARGET_OF_TARGET"
            or "HELLOUI_FIX_TARGET_OF_TARGET")
    end
end

function Player:ScheduleTargetOfTargetCheck()
    if Player.checkedTargetOfTargetThisSession or Player.targetOfTargetCheckScheduled then return end
    Player.targetOfTargetCheckScheduled = true
    local timer = _G["C_Timer"]

    local function confirmPosition()
        Player.targetOfTargetCheckScheduled = false
        ns:WhenSafe("Player:asktot", function() Player:MaybeAskTargetOfTarget() end)
    end

    local function firstRead()
        ns:WhenSafe("Player:probetot", function()
            if not Player:TargetOfTargetNeedsRepair() then
                Player.checkedTargetOfTargetThisSession = true
                Player.targetOfTargetCheckScheduled = false
            elseif timer and timer.After then
                timer.After(3, confirmPosition)
            else
                confirmPosition()
            end
        end)
    end

    if timer and timer.After then timer.After(1, firstRead) else firstRead() end
end

function Player:Apply()
    local bar = healthBar()
    if not bar then return end

    if not Config:Enabled() then
        if original then
            bar:SetStatusBarColor(original.r, original.g, original.b, original.a)
            original = nil
        end
        return
    end

    if not original then
        local r, g, b, a = bar:GetStatusBarColor()
        original = { r = r, g = g, b = b, a = a }
    end

    setClassColor(bar)
end

function Player:Init()
    if type(UnitFrameHealthBar_Update) == "function" then
        hooksecurefunc("UnitFrameHealthBar_Update", function(bar)
            if bar == healthBar() and Config:Enabled() then setClassColor(bar) end
        end)
        Player.hookedHealth = true
    end

    -- The class cannot change, but the frame can be re-set to a vehicle or
    -- back (UnitFrame_SetUnit re-points the same bar), and a login lands
    -- before the frame has its unit.
    ns:On("PLAYER_ENTERING_WORLD", function() ns:SafeCall("Player:pew", Player.Apply, Player) end)
    ns:On("PLAYER_ENTERING_WORLD", function() Player:ScheduleTargetOfTargetCheck() end)
    ns:On("PLAYER_REGEN_ENABLED", function()
        if Player.targetOfTargetRetryAfterCombat then
            Player.targetOfTargetRetryAfterCombat = false
            Player.checkedTargetOfTargetThisSession = false
            Player.askedTargetOfTargetThisSession = false
            Player:MaybeAskTargetOfTarget()
        end
    end)
    ns:On("UNIT_ENTERED_VEHICLE", function(unit)
        if unit == "player" then ns:SafeCall("Player:vehicle", Player.Apply, Player) end
    end)
    ns:On("UNIT_EXITED_VEHICLE", function(unit)
        if unit == "player" then ns:SafeCall("Player:novehicle", Player.Apply, Player) end
    end)
end

function Player:StatusText()
    if not healthBar() then return "player: |cffff8080health bar not found|r" end
    return nil
end

function Player:Status()
    local bar = healthBar()
    if not bar then
        ns:Print("player: |cffff8080PlayerFrameHealthBar not found|r")
        return
    end
    if not Config:Enabled() then
        ns:Print("player: health bar left to Blizzard")
        return
    end
    local _, class = UnitClass("player")
    local r, g, b = ns:ClassColor(class)
    ns:Print("player: health bar class-coloured %s |cff808080(%.2f %.2f %.2f, secure post-hook=%s)|r",
        tostring(class), r, g, b, tostring(Player.hookedHealth or false))
end
