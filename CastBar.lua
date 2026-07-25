local ADDON_NAME, ns = ...

ns.CastBar = {}
local CastBar = ns.CastBar

local Config = ns.Config

--------------------------------------------------------------------------
-- Blizzard's player cast bar, when a sibling is drawing its own
--
-- HelloUI's layout parks PlayerCastingBarFrame just above the action bar
-- stack, which is also where HelloWarrior's cluster sits, so on a Warrior the
-- two draw through each other. Moving one out of the way is the hard version of
-- this problem - the cast bar is an Edit Mode system, an anchor set from outside
-- is reverted on the next close of Edit Mode, and making one stick means writing
-- Edit Mode's own layout table in our taint context. HelloWarrior draws its own
-- bar at the top of its cluster instead, and this switches Blizzard's off.
--
-- THE MECHANISM IS BLIZZARD'S OWN, not a workaround:
--
--   function CastingBarMixin:ShouldShowCastBar()
--       return self.showCastbar and (self.unit ~= nil);
--   end
--
-- and every path that would show the bar - HandleCastStart, UpdateIsShown -
-- goes through it. `SetAndUpdateShowCastbar(false)` is what the client itself
-- calls in OverlayPlayerCastingBarMixin:StartReplacingPlayerBarAt, under the
-- comment "Disable real Player Cast Bar", for exactly this case: another bar has
-- taken over. So this is a supported flag, not a Hide() we have to defend, and
-- it needs no re-assertion - nothing in Blizzard's code sets it back.
--
-- DETECTION IS BY FRAME, NOT BY ADDON. `IsAddOnLoaded("HelloWarrior")` is true
-- on a Priest with the addon installed, where it builds nothing at all
-- (HelloWarrior gates its whole UI on the player being a Warrior). The
-- condition that actually matters is "is a sibling drawing a cast bar right
-- now", and the honest test for that is its frame existing and its cluster being
-- shown. Both are named globals, looked up by name - no enumeration, no reach
-- into a sibling's internals, and no coupling in the other direction:
-- HelloWarrior neither knows nor cares that this file exists.
--
-- Consequence worth stating: `/hw bars off` hides the cluster, and Blizzard's
-- bar comes back on HelloUI's next apply pass (a zone change, an options
-- change, or `/hui apply`) rather than instantly. That is a second or two of
-- neither-bar in the worst case, and the alternative is HelloUI polling a
-- sibling's visibility every frame, which is a much worse trade.
--------------------------------------------------------------------------

local SIBLINGS = {
    -- frame that exists while the sibling draws a cast bar, and the cluster
    -- whose visibility says whether it is on screen at all.
    { bar = "HelloWarrior_CastBar", cluster = "HelloWarrior_Container" },
}

local function siblingBar()
    for _, def in ipairs(SIBLINGS) do
        local bar = _G[def.bar]
        if bar then
            local cluster = _G[def.cluster]
            if not cluster or (cluster.IsShown and cluster:IsShown()) then
                return def.bar
            end
        end
    end
    return nil
end

local function playerBar()
    local f = _G["PlayerCastingBarFrame"]
    if f and f.SetAndUpdateShowCastbar then return f end
    return nil
end

function CastBar:Apply()
    local f = playerBar()
    if not f then return end

    local sibling = Config:Enabled("yieldCastBar") and siblingBar() or nil

    -- Only ever written when it needs to change, and the previous value is not
    -- remembered: `showCastbar` is true for every frame Blizzard ships except
    -- the overlay bar, which is a different frame, so "restore" is unambiguous.
    if sibling then
        if CastBar.yielded then return end
        f:SetAndUpdateShowCastbar(false)
        CastBar.yielded = sibling
    else
        if not CastBar.yielded then return end
        f:SetAndUpdateShowCastbar(true)
        CastBar.yielded = nil
    end
end

function CastBar:StatusText()
    if CastBar.yielded then
        return ("cast bar: |cff808080yielded to %s|r"):format(CastBar.yielded)
    end
    return nil
end

function CastBar:Status()
    if not playerBar() then
        ns:Print("cast bar: |cffff8080PlayerCastingBarFrame has no SetAndUpdateShowCastbar|r")
        return
    end
    if not Config:Enabled("yieldCastBar") then
        ns:Print("cast bar: Blizzard's, always |cff808080(yielding is switched off)|r")
        return
    end
    local sibling = siblingBar()
    ns:Print("cast bar: %s", sibling
        and ("hidden - " .. sibling .. " is drawing one")
        or "Blizzard's |cff808080(no sibling cast bar found)|r")
end
