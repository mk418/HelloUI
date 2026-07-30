local ADDON_NAME, ns = ...

ns.MirrorTimer = {}
local MirrorTimer = ns.MirrorTimer

local Config = ns.Config

--------------------------------------------------------------------------
-- Blizzard's breath / fatigue / death timers, in the cast-bar style
--
-- Classic calls these mirror timers. There are three interchangeable frames,
-- and BREATH is assigned to whichever one is free when it starts, so styling
-- MirrorTimer1 alone works until fatigue or another timer gets there first.
-- All three are therefore treated identically.
--
-- This is deliberately a restyle of Blizzard's timers, not a replacement.
-- MirrorTimerFrame_OnUpdate already reads GetMirrorTimerProgress and updates
-- the stock status bar every frame. HelloUI only blanks the same 256x64 border
-- used by the cast bar, moves the stock label left, and displays frame.value on
-- the right after Blizzard has updated it. The stock type colour stays intact:
-- breath remains blue, fatigue yellow, and death orange.
--------------------------------------------------------------------------

local NUM_TIMERS = 3
local SMALL_FONT = "GameFontHighlightSmall"
local DEFAULT_Y = -124

local saved = {}

local function parts(index)
    local frame = _G["MirrorTimer" .. index]
    if not frame then return nil end

    local name = frame.GetName and frame:GetName() or ("MirrorTimer" .. index)
    return frame, _G[name .. "StatusBar"], _G[name .. "Text"], _G[name .. "Border"]
end

local function remember(frame, text, border)
    if saved[frame] then return end

    local point, rel, relPoint, x, y
    local framePoint, frameRel, frameRelPoint, frameX, frameY
    if text and text.GetPoint then
        point, rel, relPoint, x, y = text:GetPoint(1)
    end
    if frame.GetPoint then
        framePoint, frameRel, frameRelPoint, frameX, frameY = frame:GetPoint(1)
    end

    saved[frame] = {
        borderTex = border and border.GetTexture and border:GetTexture(),
        textPoint = point,
        textRel = rel,
        textRelPoint = relPoint,
        textX = x,
        textY = y,
        justify = text and text.GetJustifyH and text:GetJustifyH(),
        font = text and text.GetFontObject and text:GetFontObject(),
        framePoint = framePoint,
        frameRel = frameRel,
        frameRelPoint = frameRelPoint,
        frameX = frameX,
        frameY = frameY,
    }
end

local function restoreAnchor(frame)
    local original = saved[frame]
    if not (original and original.framePoint) then return end

    frame:ClearAllPoints()
    frame:SetPoint(original.framePoint, original.frameRel, original.frameRelPoint,
        original.frameX, original.frameY)
end

local function positionStack()
    local first = parts(1)
    if not (first and saved[first]) then return end

    first:ClearAllPoints()
    first:SetPoint("TOP", UIParent, "TOP", 0, DEFAULT_Y)
    MirrorTimer.positioned = true
end

local function ensureTimer(frame, statusbar)
    if frame.HelloUITimer or not (statusbar and statusbar.CreateFontString) then return end

    local timer = statusbar:CreateFontString(nil, "OVERLAY", SMALL_FONT)
    timer:SetPoint("RIGHT", statusbar, "RIGHT", -4, 0)
    frame.HelloUITimer = timer
end

local function updateTimer(frame)
    local timer = frame.HelloUITimer
    if not timer then return end

    if not frame:IsShown() or not frame.timer or type(frame.value) ~= "number" then
        timer:SetText("")
        return
    end

    timer:SetText(("%.1f"):format(math.max(0, frame.value)))
end

local function applyStyle(frame, statusbar, text, border)
    if not statusbar then return false end

    remember(frame, text, border)
    ensureTimer(frame, statusbar)

    -- SetTexture(nil), rather than Hide(), for the same reason as the cast bar:
    -- the frame may show the region again, but a texture with no file still
    -- paints nothing. The stock file is remembered for /hui off.
    if border and border.SetTexture then border:SetTexture(nil) end

    if text then
        text:ClearAllPoints()
        text:SetPoint("LEFT", statusbar, "LEFT", 4, 0)
        text:SetPoint("RIGHT", statusbar, "RIGHT", -40, 0)
        if text.SetJustifyH then text:SetJustifyH("LEFT") end
        if text.SetFontObject then text:SetFontObject(_G[SMALL_FONT] or SMALL_FONT) end
        if text.SetWordWrap then text:SetWordWrap(false) end
        if text.SetMaxLines then text:SetMaxLines(1) end
    end

    if frame.HelloUITimer then
        frame.HelloUITimer:Show()
        updateTimer(frame)
    end
    return true
end

local function restoreStyle(frame, text, border)
    local original = saved[frame]
    if not original then return end

    restoreAnchor(frame)
    if border and original.borderTex then border:SetTexture(original.borderTex) end
    if frame.HelloUITimer then frame.HelloUITimer:Hide() end

    if text and original.textPoint then
        text:ClearAllPoints()
        text:SetPoint(original.textPoint, original.textRel, original.textRelPoint,
            original.textX, original.textY)
        if text.SetJustifyH and original.justify then text:SetJustifyH(original.justify) end
        if text.SetFontObject and original.font then text:SetFontObject(original.font) end
        if text.SetWordWrap then text:SetWordWrap(true) end
    end

    saved[frame] = nil
end

function MirrorTimer:Apply()
    local found, styled = 0, 0

    for index = 1, NUM_TIMERS do
        local frame, statusbar, text, border = parts(index)
        if frame then
            found = found + 1
            if Config:Enabled() then
                if applyStyle(frame, statusbar, text, border) then styled = styled + 1 end
            else
                restoreStyle(frame, text, border)
            end
        end
    end

    if Config:Enabled() then
        positionStack()
    else
        MirrorTimer.positioned = false
    end

    MirrorTimer.found = found
    MirrorTimer.styled = styled
end

function MirrorTimer:Init()
    local hooked = 0

    for index = 1, NUM_TIMERS do
        local frame = parts(index)
        if frame and frame.HookScript then
            -- Blizzard's OnUpdate writes frame.value before post-hooks run, so
            -- the number shown here is the same value its fill just received.
            frame:HookScript("OnUpdate", function(self)
                if Config:Enabled() then updateTimer(self) end
            end)
            frame:HookScript("OnShow", function(self)
                if Config:Enabled() then updateTimer(self) end
            end)
            hooked = hooked + 1
        end
    end

    MirrorTimer.hooked = hooked
end

function MirrorTimer:StatusText()
    if MirrorTimer.found and MirrorTimer.found < NUM_TIMERS then
        return ("breath meter: |cffff8080%d/%d mirror timers found|r"):format(
            MirrorTimer.found, NUM_TIMERS)
    end
    return nil
end

function MirrorTimer:Status()
    ns:Print("breath meter: %d/%d Blizzard mirror timers styled%s",
        MirrorTimer.styled or 0, MirrorTimer.found or 0,
        MirrorTimer.positioned and (" at top-center y=" .. DEFAULT_Y)
            or " at Blizzard's position")
end
