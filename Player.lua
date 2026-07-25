local ADDON_NAME, ns = ...

ns.Player = {}
local Player = ns.Player

local Config = ns.Config

--------------------------------------------------------------------------
-- Class-coloured player health bar
--
-- Blizzard hands this one over voluntarily. UnitFrameHealthBar_Update's
-- colour write is guarded:
--
--   if ( not statusbar.lockColor ) then
--       statusbar:SetStatusBarColor(0.0, 1.0, 0.0);
--   end
--
-- so `PlayerFrameHealthBar.lockColor = true` makes Blizzard stop resetting
-- it, and no hooksecurefunc is needed at all. That flag is a long-standing
-- part of the unit frame contract, it is read on both the connected and
-- disconnected paths, and using it means the colour is set once rather than
-- re-asserted on every health tick.
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

function Player:Apply()
    local bar = healthBar()
    if not bar then return end

    if not Config:Enabled("classColorPlayerHealth") then
        if original then
            bar.lockColor = original.lockColor
            bar:SetStatusBarColor(original.r, original.g, original.b, original.a)
            original = nil
            -- Hand the colour back to Blizzard for the next health event.
            if UnitFrameHealthBar_Update and bar.unit then
                pcall(UnitFrameHealthBar_Update, bar, bar.unit)
            end
        end
        return
    end

    if not original then
        local r, g, b, a = bar:GetStatusBarColor()
        original = { r = r, g = g, b = b, a = a, lockColor = bar.lockColor }
    end

    local _, class = UnitClass("player")
    local r, g, b = ns:ClassColor(class)

    -- Order matters only in that lockColor must be set before anything else
    -- calls the update path; setting both together every apply is idempotent.
    bar.lockColor = true
    bar:SetStatusBarColor(r, g, b, 1)
end

function Player:Init()
    -- The class cannot change, but the frame can be re-set to a vehicle or
    -- back (UnitFrame_SetUnit re-points the same bar), and a login lands
    -- before the frame has its unit. Cheap re-assert on the few events that
    -- can plausibly disturb it; lockColor handles the per-tick case.
    ns:On("PLAYER_ENTERING_WORLD", function() ns:SafeCall("Player:pew", Player.Apply, Player) end)
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
    if not Config:Enabled("classColorPlayerHealth") then
        ns:Print("player: health bar left to Blizzard")
        return
    end
    local _, class = UnitClass("player")
    local r, g, b = ns:ClassColor(class)
    ns:Print("player: health bar class-coloured %s |cff808080(%.2f %.2f %.2f, lockColor=%s)|r",
        tostring(class), r, g, b, tostring(bar.lockColor))
end
