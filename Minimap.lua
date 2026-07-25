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
-- Neither of Blizzard's own positions is usable, which is worth spelling out
-- because both look authoritative:
--
--   MinimapTracking_Simple.xml   TOPLEFT (11, -26)   the vanilla file
--   MinimapTracking_Dropdown.xml TOPLEFT (5, -64)    every other flavour
--
-- LFGMinimapFrame sits at TOPLEFT (25, -28) with 33px icons, so the vanilla
-- offset is 14px from it - straight overlap, which is what the player saw. And
-- the dropdown offset, measured against the rects the probe actually reported,
-- is 57 units from the map's centre on a map whose rim is at 70. It is INSIDE
-- the artwork. So is anything reached by dropping straight down from LFG: the
-- rim is a circle, and a vertical translation cuts the chord.
--
-- Hence polar placement. Take the LFG eye's own offset from the map's centre -
-- 75 units at about 137 degrees, riding the rim - and ROTATE it around that
-- centre. Rotation preserves the radius by construction, so the button lands on
-- the same circle every other minimap button rides, at whatever angle is free.
--
-- AND IT IS DECLARED THE WRONG SIZE. Third defect in the same 33-line file.
-- Both buttons are 33x33 frames and both rings are the same texture,
-- Interface\Minimap\MiniMap-TrackingBorder, with no TexCoords, colour or scale
-- attribute on either - so the declared size is the whole difference:
--
--   LFGMinimapFrameBorder     52x52 at TOPLEFT (1,-1)
--   MiniMapMailBorder         52x52 at TOPLEFT
--   MiniMapBattlefieldBorder  52x52 at TOPLEFT
--   MiniMapWorldBorder        52x52 at TOPLEFT
--   MiniMapTrackingBorder     64x64 at TOPLEFT      <- the vanilla file again
--
-- 64/52 = 1.2308, so the ring drew 23% larger than every other button on the
-- rim; at 52 it is 30.06 units across, which fits inside the 33x33 frame, and at
-- 64 it is 37 - overflowing its own frame by 4 units. That is the "too large".
-- Measured independently off a screenshot by sub-pixel circle fit before it was
-- changed: 42.91px against the eye's 34.98px, ratio 1.227 +/- 0.008. It is not
-- the only 64 declaration of that texture in the client (Blizzard_HelpPlate has
-- one too), but it is the only 33x33 minimap button carrying one.
--
-- Two consequences that are not optional:
--
-- 1. THE ANCHOR MOVES WITH THE SIZE. The ring art is not centred in its file -
--    the hole sits about 0.289 of the way in from the left and top - so a
--    TOPLEFT-anchored border on a smaller frame puts the hole somewhere new.
--    Copying LFG's (1,-1) verbatim sidesteps having to know that fraction:
--    same texture, same 52, same 33x33 frame, therefore the same offset from the
--    frame's centre by construction. Which is exactly the parity the polar
--    placement needs, since ringOffset measures the eye's FRAME centre.
--    Resizing to 52 while leaving the anchor at (0,0) slides the ring 3.47 units
--    up-left of the icon still sitting at Blizzard's (2,-2).
--
-- 2. IT IS SetSize ON THE REGIONS, NEVER SetScale ON THE FRAME. SetPoint offsets
--    live in the anchored frame's own coordinate space, so f:SetScale(52/64)
--    would render the 75-unit polar vector at 61 units against a rim at 70 -
--    putting the button back on top of the map, the exact bug the rotation was
--    written to fix, while the icon looked correct. Blizzard divides its own
--    cached offsets by GetScale for this reason (MinimapClusterMixin's
--    ResetFramePoints). Region sizes cannot feed back the other way:
--    MiniMapTracking is a plain Frame with an explicit <Size x="33" y="33"/> and
--    inherits nothing, so its rect - and the polar maths - are untouched.
--------------------------------------------------------------------------

-- MiniMapTracking first, deliberately. MiniMapTrackingFrame does not exist
-- anywhere in the 1.15.9 client, but addons of the sort this one replaces do
-- create it, and preferring a foreign frame would point every region lookup and
-- every anchor below at somebody else's button.
local function trackingFrame()
    return _G["MiniMapTracking"] or _G["MiniMapTrackingFrame"]
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

--------------------------------------------------------------------------
-- Matching the eye's size
--------------------------------------------------------------------------

-- Blizzard's own numbers for every other ring on the rim, used when the eye
-- cannot be measured. Not a setting: trackingAngle is one because the rim is
-- shared with addons this code cannot see, whereas 52 is settled by four
-- Blizzard declarations agreeing with each other.
local RING_SIZE, RING_INSET = 52, 1

-- The vanilla file's own icon-to-ring proportion, 24 in 64. Kept rather than
-- refitted to the ring's hole: the ring draws OVER the icon (icon on layer
-- BORDER, ring on ARTWORK), so the square icon's corners are meant to tuck under
-- the bevel, and that overhang should shrink with everything else. 24 * 52/64 =
-- 19.5, which sits between the mail button's 18 and the world map's 20 and
-- within a quarter-unit of what TBC uses for this same tracking art.
local ICON_RATIO = 24 / 64

-- Keyed by the region object, and written only once - the StatusBars savedWidth
-- pattern. Recording unconditionally would make the second Apply file HelloUI's
-- own 52 as "Blizzard's original" and turn the restore into a no-op.
--
-- A file-local rather than HelloUIDB, unlike the xpBarText original next door: a
-- CVar survives a reload and a region's size does not, so at the next login the
-- XML re-establishes 64 and 24 by itself and there is nothing to persist.
local savedArt = {}

local function remember(r)
    if savedArt[r] ~= nil then return end
    local p, rel, rp, x, y = r:GetPoint(1)
    savedArt[r] = {
        w = r:GetWidth(), h = r:GetHeight(),
        p = p, rel = rel, rp = rp, x = x, y = y,
    }
end

-- What to match, read off the eye's own ring rather than hard-coded. 52 is
-- today's answer to "the size of the LFG icon"; the request was the question,
-- not the answer.
--
-- Scale-aware, which is the one thing a verbatim copy gets wrong: GetWidth on a
-- texture is in its own frame's coordinate space, so if another addon scales
-- LFGMinimapFrame - minimap button packs do exactly this - then copying 52
-- leaves two rings declared the same and RENDERED 25% apart, which is the
-- complaint this is answering. In stock the two frames are siblings under
-- MinimapBackdrop and the factor is exactly 1.
local function ringSpec(f)
    local b = _G["LFGMinimapFrameBorder"]
    if not (b and b.GetWidth and b.GetPoint) then return RING_SIZE, RING_INSET, -RING_INSET end

    local w = b:GetWidth()
    -- Rejects nil, 0 - which would be an invisible ring and an invisible icon -
    -- and anything too far out to be a minimap button ring.
    if type(w) ~= "number" or w < 24 or w > 96 then return RING_SIZE, RING_INSET, -RING_INSET end

    local theirs = (b.GetEffectiveScale and b:GetEffectiveScale()) or 1
    local ours = (f.GetEffectiveScale and f:GetEffectiveScale()) or 1
    local factor = (theirs > 0 and ours > 0) and (theirs / ours) or 1

    local ox, oy = RING_INSET, -RING_INSET
    local p, _, rp, x, y = b:GetPoint(1)
    if p == "TOPLEFT" and rp == "TOPLEFT" and type(x) == "number" and type(y) == "number" then
        ox, oy = x, y
    end

    return w * factor, ox * factor, oy * factor
end

-- Anchored to MiniMapTracking itself, not to whatever trackingFrame() returned:
-- the regions belong to that frame, and anchoring a child texture to a foreign
-- frame would leave the ring tracking something that is not its own button.
local function matchTrackingArt()
    local tf = _G["MiniMapTracking"]
    if not tf then return end

    local size, ox, oy = ringSpec(tf)

    local border = _G["MiniMapTrackingBorder"]
    if border and border.SetSize and border.SetPoint then
        remember(border)
        border:SetSize(size, size)
        border:ClearAllPoints()
        border:SetPoint("TOPLEFT", tf, "TOPLEFT", ox, oy)
    end

    -- Blizzard's CENTER (2,-2) goes to (0,0). That nudge existed solely to cancel
    -- where a 64 ring flush at (0,0) put the hole; against a 52 ring at (1,-1) it
    -- would push the icon 2.5 units down-right inside a 22-unit aperture.
    local icon = _G["MiniMapTrackingIcon"]
    if icon and icon.SetSize and icon.SetPoint then
        remember(icon)
        local n = ICON_RATIO * size
        icon:SetSize(n, n)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", tf, "CENTER", 0, 0)
    end

    Minimap_.trackingRing = size
end

-- Sizes and region anchors are handed back together. Handing back only the sizes
-- would leave Blizzard's 64 ring around an icon still centred for a 52 one.
local function restoreTrackingArt()
    for _, name in ipairs({ "MiniMapTrackingBorder", "MiniMapTrackingIcon" }) do
        local r = _G[name]
        local s = r and savedArt[r]
        if s then
            r:SetSize(s.w, s.h)
            if s.p then
                r:ClearAllPoints()
                r:SetPoint(s.p, s.rel or _G["MiniMapTracking"], s.rp, s.x, s.y)
            end
            savedArt[r] = nil
        end
    end
    Minimap_.trackingRing = nil
end

local function centreOf(f)
    if not (f and f.GetLeft) then return nil end
    local l, b = f:GetLeft(), f:GetBottom()
    local w, h = f:GetWidth(), f:GetHeight()
    if not (l and b and w and h) then return nil end
    return l + w / 2, b + h / 2
end

-- Offset from the map's centre for a button `degrees` around the rim from the
-- LFG eye. Positive turns anticlockwise, which from the upper-left where the
-- eye sits means downwards along the edge - the direction asked for.
--
-- Everything is measured live rather than taken from the XML, because the map's
-- size is an Edit Mode setting and the eye moves with it.
local function ringOffset(map, lfg, degrees)
    local mx, my = centreOf(map)
    if not mx then return nil end

    local dx, dy
    local lx, ly = centreOf(lfg)
    if lx and (lx ~= mx or ly ~= my) then
        dx, dy = lx - mx, ly - my
    else
        -- No eye to follow. Its declared position, TOPLEFT (25,-28) inside a
        -- 192-wide backdrop centred on the map, is 5 units outside a 140-wide
        -- map's rim at 137 degrees; rebuild that from whatever the map measures
        -- now rather than hard-coding the 140.
        local r = ((map.GetWidth and map:GetWidth() or 140) / 2) + 5
        dx, dy = -r * 0.7314, r * 0.6820
    end

    local rad = degrees * math.pi / 180
    local c, s = math.cos(rad), math.sin(rad)
    return dx * c - dy * s, dx * s + dy * c
end

local function trackingAngle()
    local v = Config:Get("trackingAngle")
    return type(v) == "number" and v or 30
end

local function applyTracking()
    local f = trackingFrame()
    if not f then return end

    if not Config:Enabled("fixTrackingIcon") then
        -- What can actually be handed back: the two region sizes and their
        -- anchors, because those were recorded. The frame's parent, its shown
        -- state and its polar anchor cannot be reconstructed without re-reading
        -- Blizzard's XML - which is what `/hui off`'s own "/reload to fully
        -- restore Blizzard's own state" already covers, and what a reload does
        -- for free.
        restoreTrackingArt()
        Minimap_.trackingFixed = nil
        return
    end

    -- The artwork first, and outside every branch below on purpose. It depends on
    -- nothing but the two regions, so it must still happen when the map has no
    -- rect yet and when the button is hidden - Blizzard's own mixin calls
    -- MiniMapTracking:Show() the moment tracking changes, and the regions have to
    -- already be right at that moment.
    matchTrackingArt()

    local map = _G["Minimap"]
    if not (map and f.SetParent) then return end

    -- No "already parented, leave it alone" guard. There was one, and it is
    -- why the icon vanished again: MiniMapTracking's parent after a reload is
    -- whatever the parentless XML leaves it with, the guard read that as
    -- somebody else's claim, and skipped the fix. Speculative defensiveness
    -- for a case that was never observed, breaking the case that was.
    local backdrop = _G["MinimapBackdrop"] or map
    f:SetParent(backdrop)
    f:ClearAllPoints()

    -- Shown first, and deliberately: a hidden frame still reports a rect, but
    -- only a frame that has one at all does, and this is also what makes the
    -- icon appear on a character who logged in with tracking already active.
    syncTrackingVisibility(f)

    -- Anchored to the map's centre rather than to the eye. Anchoring to LFG is
    -- what produced the chord: SetPoint can only translate, and the rim needs a
    -- rotation. The eye is still what the angle is measured FROM, so the button
    -- keeps following it - just around the circle instead of down the screen.
    local degrees = trackingAngle()
    local dx, dy = ringOffset(map, _G["LFGMinimapFrame"], degrees)
    if dx then
        f:SetPoint("CENTER", map, "CENTER", dx, dy)
        Minimap_.trackingFixed = ("%d degrees round the rim from the LFG eye"):format(degrees)
    else
        -- The map has no rect yet, so there is no circle to place anything on.
        -- Blizzard's non-vanilla offset is the least wrong thing left; the next
        -- Apply, once the map has been laid out, replaces it with the real one.
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

-- Live nudge for where the button sits on the rim. This one is not cosmetic
-- fine-tuning: the rim is shared with every other addon's minimap button, and
-- nothing in here can know which slots those have already taken. 30 degrees
-- clears the eye; whether it lands on somebody else's button is a question only
-- the screen can answer.
function Minimap_:NudgeTracking(degrees)
    if degrees then Config:Set("trackingAngle", degrees) end
    applyTracking()
    ns:Print("tracking button: %d degrees round the rim from the LFG eye |cff808080(/hui tracking <degrees>, negative goes the other way)|r",
        trackingAngle())
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
            -- %.0f rather than %d throughout: region sizes here are genuinely
            -- fractional now (the icon is 19.5), and %d on a non-integer is a
            -- hard error outside WoW's own tolerant 5.1 - which is how the
            -- offline harness caught this line at all.
            l and ("at %.0f,%.0f %.1fx%.1f"):format(l, f:GetBottom() or 0,
                f:GetWidth() or 0, f:GetHeight() or 0)
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

    -- Same idea as the rim line below, for the size: three numbers, side by side,
    -- where the answer is "the first two match". Printed before the early return
    -- underneath, because the artwork is right or wrong regardless of whether the
    -- map has a rect to measure.
    local function widthOf(name)
        local r = _G[name]
        local w = r and r.GetWidth and r:GetWidth()
        return (type(w) == "number") and ("%.1f"):format(w) or "absent"
    end
    ns:Print("  ring: tracking %s, lfg %s, icon %s |cff808080(tracking should match lfg)|r",
        widthOf("MiniMapTrackingBorder"), widthOf("LFGMinimapFrameBorder"),
        widthOf("MiniMapTrackingIcon"))

    -- The line that made the last mistake obvious. A button whose distance from
    -- the map's centre is smaller than the map's own radius is drawn on the map,
    -- not on its edge, and no screenshot says that as plainly as three numbers.
    local map = _G["Minimap"]
    local mx, my = centreOf(map)
    if not mx then return end

    local function radius(f)
        local x, y = centreOf(f)
        if not x then return nil end
        local dx, dy = x - mx, y - my
        return math.sqrt(dx * dx + dy * dy)
    end

    local function fmt(r) return r and ("%.0f"):format(r) or "?" end
    ns:Print("  rim: map %s, lfg %s, tracking %s |cff808080(tracking should match lfg; below map is on top of the map)|r",
        fmt((map:GetWidth() or 0) / 2), fmt(radius(_G["LFGMinimapFrame"])),
        fmt(radius(trackingFrame())))
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
    ns:Print("  |cff808080tracking button: %s, shown=%s, ring %s|r",
        (not track) and "absent" or (Minimap_.trackingFixed or "left alone"),
        tostring(track and track.IsShown and track:IsShown()),
        Minimap_.trackingRing and ("%.1f"):format(Minimap_.trackingRing) or "Blizzard's")
    ns:Print("  |cff808080clock text: %s|r",
        (not _G["TimeManagerClockTicker"]) and "clock not loaded" or (Minimap_.clockFixed or "left alone"))
end
