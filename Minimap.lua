local ADDON_NAME, ns = ...

ns.Minimap = {}
local Minimap_ = ns.Minimap

local Config = ns.Config

--------------------------------------------------------------------------
-- The minimap
--
-- This module got smaller than the design expected, and both reductions are
-- the right answer rather than a shortcut.
--
-- 1. THIS MODULE MOVES NOTHING. Stock 1.15.9 already anchors the minimap
--    flush to the top right: both Edit Mode preset layouts set the Minimap
--    system to TOPRIGHT / UIParent / TOPRIGHT at offset 0,0, and the XML
--    agrees. There is nothing to move. (Its SIZE is set, but through the Edit
--    Mode layout in Layout.lua, which is the sanctioned route - not from
--    here.)
--
--    The residual gap between the visible ring and the screen edge is not an
--    anchor problem. MinimapCluster is a ResizeLayoutFrame sized to the union
--    of its shown children, and the widest of those is the ~176px BorderTop
--    header, so the header is flush and the 140px map sits inside it. Closing
--    that gap means moving the map relative to its own header, which is a
--    different and much worse idea.
--
--    DragonflightUI's +7 does not transfer. Its own comment says why: it was
--    compensating for dead margin in a 178px frame DragonflightUI created
--    and re-parented the real minimap into. Different frame, different art,
--    different units.
--
--    And MinimapCluster is an Edit Mode system, which makes fighting it
--    actively unpleasant: EditModeSystemMixin swaps SetPoint, ClearAllPoints,
--    SetScale, SetShown and Hide for overrides, so `MinimapCluster:SetPoint`
--    is not the C method and writes manager state in our taint context; the
--    frame is clampedToScreen with zero insets, so a positive offset on a
--    TOPRIGHT anchor cannot move it anyway; and any anchor we did set is
--    reverted on layout save, spec change and every close of Edit Mode.
--    Drag it in Edit Mode instead - that is what Edit Mode is for.
--
-- 2. IT IS NOT A CALENDAR BUTTON ON ERA. Classic Era loads
--    GameTime_NoCalendar, not the Wrath GameTime, so `GameTimeFrame` here is
--    the time-of-day sun/moon dial: a Frame rather than a Button, no OnClick,
--    no enableMouse declared and nothing that ever calls EnableMouse, which
--    makes even its tooltip script unreachable. Hiding it costs the sun icon
--    and saves a per-frame OnUpdate, and it is not protected, not secure and
--    not an Edit Mode system, so a plain Hide() is safe and taint-free.
--
--    The setting keeps the old profile's name so the migration is traceable,
--    but nothing user-facing calls it a calendar.
--------------------------------------------------------------------------

local function todFrame()
    return _G["GameTimeFrame"]
end

-- Hide is unconditional; Show is not. ToggleMinimap hides the dial along with
-- the map and shows it again on the way back, so an unconditional Show in the
-- restore path would put the sun back on screen with no minimap under it the
-- moment the feature was switched off while the map was toggled away.
-- Blizzard's own state is the authority on whether it should be visible at
-- all, and Minimap:IsShown() is that state.
local function applyTimeOfDay()
    local f = todFrame()
    if not f then return end

    if Config:Enabled("hideTimeOfDay") then
        f:Hide()
        return
    end

    local map = _G["Minimap"]
    if not map or map:IsShown() then f:Show() end
end

--------------------------------------------------------------------------
-- The tracking button
--
-- On Era this is genuinely broken in Blizzard's own XML.
-- Blizzard_Minimap/Classic/MinimapTracking_Simple.xml declares
--   <Frame name="MiniMapTracking" mixin="MinimapTrackingSimpleMixin" hidden="true">
-- with NO parent attribute and an unqualified <Anchor point="TOPLEFT" x="11"
-- y="-26"/>, and MinimapTracking_Simple.lua never reparents it. So it lands
-- at the top-left of the SCREEN, next to the player frame, rather than on the
-- minimap. The non-vanilla variant of the same file has parent="MinimapBackdrop";
-- the vanilla one lost it.
--
-- Only classes with an active tracking ability ever see it, which is why it
-- survives in the shipped client.
--
-- The position is Blizzard's own, not invented: the SAME frame name is
-- declared in MinimapTracking_Dropdown.xml - the variant loaded on every
-- non-vanilla flavour - as
--   <Frame name="MiniMapTracking" parent="MinimapBackdrop">
--       <Anchor point="TOPLEFT" x="5" y="-64"/>
-- so that is where Blizzard puts it when the parent attribute has not gone
-- missing. It also avoids a collision the naive fix walks straight into:
-- LFGMinimapFrame sits at MinimapBackdrop TOPLEFT (25, -28), and the vanilla
-- file's own TOPLEFT (11, -26) is 14px from it with 33px icons. Blizzard's
-- dropdown position at y = -64 is a full row below, which is why it is the
-- right answer rather than merely a different one.
--------------------------------------------------------------------------

local function trackingFrame()
    return _G["MiniMapTrackingFrame"] or _G["MiniMapTracking"]
end

local function applyTracking()
    if not Config:Enabled("fixTrackingIcon") then return end

    local f = trackingFrame()
    local map = _G["Minimap"]
    if not (f and map and f.SetParent) then return end
    -- Already parented somewhere sensible by the client or another addon:
    -- leave it be rather than fighting over it.
    if f.GetParent and f:GetParent() ~= nil and f:GetParent() ~= _G["UIParent"]
       and not f.HelloUIReparented then
        Minimap_.trackingFixed = "already parented"
        return
    end
    if f.HelloUIReparented then return end

    local backdrop = _G["MinimapBackdrop"] or map
    f:SetParent(backdrop)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 5, -64)
    f.HelloUIReparented = true
    Minimap_.trackingFixed = true
end

--------------------------------------------------------------------------
-- The clock
--
-- Blizzard anchors the ticker at a HALF PIXEL:
--   <FontString name="TimeManagerClockTicker" inherits="WhiteNormalNumberFont">
--       <Anchor point="CENTER" x="3" y="1.5"/>
-- and a font string rendered off the pixel grid smears rather than landing
-- cleanly, which is what reads as misaligned. The x=3 is deliberate - it
-- centres the digits inside the dial art, which is not symmetric - so only
-- the y is rounded, keeping Blizzard's intent and snapping to the grid.
--
-- Blizzard_TimeManager is LoadOnDemand, so the frame may not exist yet; it is
-- re-applied if the addon loads later.
--------------------------------------------------------------------------

local function applyClock()
    if not Config:Enabled("fixClockText") then return end

    local ticker = _G["TimeManagerClockTicker"]
    local button = _G["TimeManagerClockButton"]
    if not (ticker and button and ticker.SetPoint) then return end

    local point, rel, relPoint, x, y = ticker:GetPoint(1)
    if not point then return end
    if y == math.floor(y) then
        Minimap_.clockFixed = "already whole-pixel"
        return
    end

    ticker:ClearAllPoints()
    ticker:SetPoint(point, rel or button, relPoint, x, math.floor(y + 0.5))
    Minimap_.clockFixed = "rounded"
end

function Minimap_:Apply()
    applyTimeOfDay()
    applyTracking()
    applyClock()
end

function Minimap_:Init()
    -- ToggleMinimap is the only thing in the entire 1.15.9 interface that
    -- re-shows GameTimeFrame - it hides it with the map and shows it again on
    -- the way back. Two clicks of the minimap toggle button, or the
    -- TOGGLEMINIMAP binding twice, and the sun is back for the session, so a
    -- single Hide() at login is not durable.
    if type(_G["ToggleMinimap"]) == "function" then
        hooksecurefunc("ToggleMinimap", function()
            applyTimeOfDay()
        end)
        Minimap_.hookedToggle = true
    end

    -- Catch anything else that shows it, including other addons. hooksecurefunc
    -- runs after the original, and Hide is not itself hooked, so this cannot
    -- recurse. Same idiom the working fork uses on its own minimap globals.
    -- The clock addon is LoadOnDemand and may arrive after us.
    ns:On("ADDON_LOADED", function(name)
        if name == "Blizzard_TimeManager" then
            ns:SafeCall("Minimap:clock", applyClock)
        end
    end)

    local f = todFrame()
    if f then
        hooksecurefunc(f, "Show", function(self)
            if Config:Enabled("hideTimeOfDay") then self:Hide() end
        end)
        Minimap_.hookedShow = true
    end
end

function Minimap_:StatusText()
    if not todFrame() then return "minimap: |cffffd100no GameTimeFrame|r" end
    return nil
end

function Minimap_:Status()
    local f = todFrame()
    if not f then
        ns:Print("minimap: |cffffd100GameTimeFrame not found|r")
        return
    end
    ns:Print("minimap: time-of-day dial %s |cff808080(toggle hook=%s, show hook=%s)|r",
        Config:Enabled("hideTimeOfDay") and "hidden" or "shown",
        tostring(Minimap_.hookedToggle or false), tostring(Minimap_.hookedShow or false))
    ns:Print("  |cff808080position is Edit Mode's job; size is set in the layout|r")
    local track = trackingFrame()
    ns:Print("  |cff808080tracking button: %s|r",
        (not track) and "absent" or (Minimap_.trackingFixed and "moved onto the minimap" or "left alone"))
    ns:Print("  |cff808080clock text: %s|r",
        (not _G["TimeManagerClockTicker"]) and "clock not loaded" or (Minimap_.clockFixed or "left alone"))
end
