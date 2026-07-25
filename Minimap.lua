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

-- Blizzard never shows this frame at login. MinimapTrackingSimpleMixin only
-- reacts to MINIMAP_UPDATE_TRACKING, which fires when tracking CHANGES - so a
-- character who logs in with tracking already active leaves the frame at its
-- XML hidden="true" indefinitely. The probe made this unmistakable: correct
-- parent, correct position under LFG, right icon, full alpha, shown=false.
--
-- This is the same three lines Blizzard's own handler runs, just also run
-- once now. Their handler keeps working afterwards; this only supplies the
-- initial state it never sets.
local function syncTrackingVisibility(f)
    local getTex = _G["GetTrackingTexture"]
    if not getTex then return end

    local ok, tex = pcall(getTex)
    if not ok then return end

    if tex then
        local icon = _G["MiniMapTrackingIcon"]
        if icon and icon.SetTexture then icon:SetTexture(tex) end
        f:Show()
        Minimap_.trackingShown = true
    else
        f:Hide()
        Minimap_.trackingShown = false
    end
end

local function applyTracking()
    if not Config:Enabled("fixTrackingIcon") then return end

    local f = trackingFrame()
    local map = _G["Minimap"]
    if not (f and map and f.SetParent) then return end

    -- No "already parented, leave it alone" guard. There was one, and it is
    -- why the icon vanished again: MiniMapTracking's parent after a reload is
    -- whatever the parentless XML leaves it with, the guard read that as
    -- somebody else's claim, and skipped the fix. Speculative defensiveness
    -- for a case that was never observed, breaking the case that was.
    local backdrop = _G["MinimapBackdrop"] or map
    f:SetParent(backdrop)
    f:ClearAllPoints()

    -- Directly under the LFG eye, on the ring's edge. Anchoring to LFG rather
    -- than to fixed coordinates means it stays under it wherever that sits -
    -- and a hidden frame still reports its position, so this works even
    -- before either icon is shown.
    syncTrackingVisibility(f)

    local lfg = _G["LFGMinimapFrame"]
    if lfg and lfg.GetPoint and lfg:GetPoint(1) then
        f:SetPoint("TOP", lfg, "BOTTOM", 0, -2)
        Minimap_.trackingFixed = "under the LFG icon"
    else
        -- LFG absent: Blizzard's own position from the non-vanilla variant of
        -- this same file, which is one row below where LFG would be.
        f:SetPoint("TOPLEFT", backdrop, "TOPLEFT", 5, -64)
        Minimap_.trackingFixed = "backdrop fallback"
    end
end

--------------------------------------------------------------------------
-- The clock
--
-- Two things are wrong with it, and the first attempt only addressed the
-- smaller one.
--
-- THE SCALE is the real cause. Making the minimap 110% scales the whole
-- subtree, clock included, so its digits are drawn at a non-integer scale and
-- render soft. Rounding the anchor cannot help while that is true - at 1.1,
-- an offset of 2 lands at 2.2 screen pixels. So the button's own scale is
-- compensated to bring its EFFECTIVE scale back to UIParent's, which renders
-- the text at native size and on the grid. The clock stays its original size
-- while the map around it is bigger, which is the point.
--
-- THE HALF PIXEL is Blizzard's: the ticker is anchored CENTER at x=3, y=1.5.
-- Once the effective scale is 1 that rounding is finally meaningful, so it is
-- done here too - and only the y, because the x=3 centres the digits inside
-- dial art that is not symmetric.
--
-- Blizzard_TimeManager is LoadOnDemand, so the frame may not exist yet; this
-- re-applies if the addon loads later, and on the events that change scales.
--------------------------------------------------------------------------

local function applyClock()
    local button = _G["TimeManagerClockButton"]
    local ticker = _G["TimeManagerClockTicker"]
    if not (button and ticker and button.SetScale) then return end

    if not Config:Enabled("fixClockText") then
        if button.HelloUIScaled then
            button:SetScale(1)
            button.HelloUIScaled = nil
        end
        return
    end

    -- Cancel out whatever scale the minimap subtree is under, so the clock
    -- draws at the same scale as the rest of the UI.
    local parent = button.GetParent and button:GetParent()
    local ui = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    if parent and parent.GetEffectiveScale then
        local own = button:GetEffectiveScale() or 1
        local cur = button:GetScale() or 1
        local parentScale = (own > 0 and cur > 0) and (own / cur) or 1
        if parentScale > 0 then
            button:SetScale(ui / parentScale)
            button.HelloUIScaled = true
        end
    end

    -- Blizzard's x=3 is an attempt at optically centring the digits inside
    -- box art that is not symmetric - its own HitRectInsets are 8 left, 5
    -- right - and whether 3 is the right number is not something the source
    -- can settle. So the offset is a setting, nudgeable live with
    -- `/hui clock <x> <y>`, defaulting to Blizzard's own rounded to the grid.
    ticker:ClearAllPoints()
    ticker:SetPoint("CENTER", button, "CENTER",
        Config:Get("clockTextX") or 3, Config:Get("clockTextY") or 2)

    Minimap_.clockFixed = ("scale %.3f, text %d,%d"):format(button:GetScale() or 1,
        Config:Get("clockTextX") or 3, Config:Get("clockTextY") or 2)
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

    -- The compensating scale depends on the minimap's, which changes with the
    -- UI scale and the resolution.
    -- Keep in step with Blizzard's own handler when tracking changes.
    ns:On("MINIMAP_UPDATE_TRACKING", function()
        local f = trackingFrame()
        if f and Config:Enabled("fixTrackingIcon") then
            ns:SafeCall("Minimap:tracksync", syncTrackingVisibility, f)
        end
    end)

    ns:On("UI_SCALE_CHANGED", function() ns:SafeCall("Minimap:clockscale", applyClock) end)
    ns:On("DISPLAY_SIZE_CHANGED", function() ns:SafeCall("Minimap:clocksize", applyClock) end)

    local f = todFrame()
    if f then
        hooksecurefunc(f, "Show", function(self)
            if Config:Enabled("hideTimeOfDay") then self:Hide() end
        end)
        Minimap_.hookedShow = true
    end
end

-- Live nudge for the clock digits, because a one or two pixel optical offset
-- is not something that can be settled from a screenshot.
function Minimap_:NudgeClock(x, y)
    if x then Config:Set("clockTextX", x) end
    if y then Config:Set("clockTextY", y) end
    applyClock()
    ns:Print("clock text offset: %d, %d |cff808080(/hui clock <x> <y>)|r",
        Config:Get("clockTextX") or 3, Config:Get("clockTextY") or 2)
end

-- Everything the tracking button and clock actually report, since neither is
-- diagnosable from a screenshot.
function Minimap_:Probe()
    local function dump(label, f)
        if not f then ns:Print("  %-12s |cff808080absent|r", label) return end
        local parent = f.GetParent and f:GetParent()
        local pname = parent and parent.GetName and parent:GetName() or "?"
        local l = f.GetLeft and f:GetLeft()
        ns:Print("  %-12s parent=%s shown=%s alpha=%.2f level=%s %s",
            label, tostring(pname), tostring(f.IsShown and f:IsShown()),
            (f.GetAlpha and f:GetAlpha()) or -1,
            tostring(f.GetFrameLevel and f:GetFrameLevel()),
            l and ("at %d,%d %dx%d"):format(l, f:GetBottom() or 0, f:GetWidth() or 0, f:GetHeight() or 0)
              or "|cffff8080unpositioned|r")
    end
    dump("tracking", trackingFrame())
    dump("trackingIcon", _G["MiniMapTrackingIcon"])
    dump("lfg", _G["LFGMinimapFrame"])
    dump("backdrop", _G["MinimapBackdrop"])
    dump("minimap", _G["Minimap"])
    dump("clock", _G["TimeManagerClockButton"])
    local tex = GetTrackingTexture and GetTrackingTexture()
    ns:Print("  GetTrackingTexture() = %s", tostring(tex))
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
    ns:Print("  |cff808080tracking button: %s, shown=%s|r",
        (not track) and "absent" or (Minimap_.trackingFixed or "left alone"),
        tostring(track and track.IsShown and track:IsShown()))
    ns:Print("  |cff808080clock text: %s|r",
        (not _G["TimeManagerClockTicker"]) and "clock not loaded" or (Minimap_.clockFixed or "left alone"))
end
