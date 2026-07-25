local ADDON_NAME, ns = ...

ns.Chat = {}
local Chat = ns.Chat

local Config = ns.Config

--------------------------------------------------------------------------
-- Chat frame size and position
--
-- The old module did exactly this and no more: SetPoint plus SetSize on
-- ChatFrame1, re-applied on PLAYER_ENTERING_WORLD. The ordering is the whole
-- trick. Blizzard restores its own saved chat geometry during login via
-- FCF_RestorePositionAndDimensions, so anything applied earlier gets
-- overwritten; PLAYER_ENTERING_WORLD lands after that.
--
-- Deliberately not routed through FCF_SavePositionAndDimensions. Writing our
-- geometry into Blizzard's own saved chat settings would make the change
-- permanent and un-restorable - turning the feature off later could not put
-- back what the user had. Re-asserting on login is reversible; overwriting
-- their saved state is not.
--
-- Only ChatFrame1. Additional chat windows are the user's own layout and
-- there is nothing in the old profile to suggest otherwise.
--------------------------------------------------------------------------

local original = nil

local function frame()
    return _G["ChatFrame1"]
end

local function remember(f)
    if original then return end
    local point, relativeTo, relativePoint, x, y = f:GetPoint(1)
    if not point then return end
    original = {
        point = point,
        relativeTo = relativeTo,
        relativePoint = relativePoint,
        x = x,
        y = y,
        width = f:GetWidth(),
        height = f:GetHeight(),
    }
end

local function restore(f)
    if not original then return end
    f:ClearAllPoints()
    f:SetPoint(original.point, original.relativeTo or UIParent,
        original.relativePoint, original.x, original.y)
    f:SetSize(original.width, original.height)
end

function Chat:Apply()
    local f = frame()
    if not f then return end

    if not Config:Enabled("chatAnchor") then
        restore(f)
        return
    end

    remember(f)

    local x = Config:Get("chatX") or 42
    local y = Config:Get("chatY") or 35
    local w = Config:Get("chatWidth") or 460
    local h = Config:Get("chatHeight") or 207

    -- Skip the work when it would change nothing. Re-anchoring a chat frame
    -- that is already where we want it is not harmful, but it does reset the
    -- scroll-to-bottom state on some builds, and this runs on every zone.
    local point, _, relativePoint, curX, curY = f:GetPoint(1)
    local sameSpot = point == "BOTTOMLEFT" and relativePoint == "BOTTOMLEFT"
        and math.abs((curX or 0) - x) < 0.5 and math.abs((curY or 0) - y) < 0.5
    local sameSize = math.abs(f:GetWidth() - w) < 0.5 and math.abs(f:GetHeight() - h) < 0.5
    if sameSpot and sameSize then return end

    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
    f:SetSize(w, h)
end

--------------------------------------------------------------------------
-- /hui chat save
--
-- The pin is a fixed geometry, and the only sane way to choose one is to drag
-- the frame until it looks right and then snapshot it. Same idiom HelloGear
-- uses for its off-hand swap: define the value by capturing the real thing
-- once, rather than dialling four numbers in a settings panel.
--------------------------------------------------------------------------

function Chat:Capture()
    local f = frame()
    if not f then
        ns:Print("chat: |cffff8080ChatFrame1 not found|r")
        return
    end

    local point, _, relativePoint, x, y = f:GetPoint(1)
    if not point then
        ns:Print("chat: |cffff8080ChatFrame1 has no anchor to read|r")
        return
    end

    -- Only the BOTTOMLEFT/BOTTOMLEFT form is stored, because that is what
    -- Apply re-asserts. Anything else is converted by measuring the frame
    -- against UIParent, so a chat window docked elsewhere still captures
    -- correctly instead of silently storing an offset for the wrong corner.
    local px, py = x or 0, y or 0
    if not (point == "BOTTOMLEFT" and relativePoint == "BOTTOMLEFT") then
        local scale = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
        px = (f:GetLeft() or 0) * scale
        py = (f:GetBottom() or 0) * scale
    end

    Config:Set("chatX", math.floor(px + 0.5))
    Config:Set("chatY", math.floor(py + 0.5))
    Config:Set("chatWidth", math.floor(f:GetWidth() + 0.5))
    Config:Set("chatHeight", math.floor(f:GetHeight() + 0.5))
    Config:Set("chatAnchor", true)

    -- The captured geometry becomes the new baseline, so the old "original"
    -- is no longer what turning the feature off should restore.
    original = nil

    ns:Print("chat: pinned to where it is now - %d,%d size %dx%d",
        Config:Get("chatX"), Config:Get("chatY"),
        Config:Get("chatWidth"), Config:Get("chatHeight"))
end

function Chat:StatusText()
    if not frame() then return "chat: |cffff8080ChatFrame1 missing|r" end
    return nil
end

function Chat:Status()
    local f = frame()
    if not f then
        ns:Print("chat: |cffff8080ChatFrame1 not found|r")
        return
    end
    if not Config:Enabled("chatAnchor") then
        ns:Print("chat: not pinned")
        return
    end
    ns:Print("chat: pinned at %d,%d size %dx%d",
        Config:Get("chatX"), Config:Get("chatY"),
        Config:Get("chatWidth"), Config:Get("chatHeight"))
end
