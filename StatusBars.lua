local ADDON_NAME, ns = ...

ns.StatusBars = {}
local StatusBars = ns.StatusBars

local Config = ns.Config

--------------------------------------------------------------------------
-- XP and reputation bar text
--
-- This one collapses almost entirely into a Blizzard setting, which is the
-- best possible outcome and worth spelling out.
--
-- Blizzard's own rule, from StatusTrackingBarMixin:
--
--   function StatusTrackingBarMixin:ShouldBarTextBeDisplayed()
--       return GetCVarBool("xpBarText") or self.textLocked
--              or StatusTrackingBarManager:IsTextLocked();
--   end
--
-- So `xpBarText` is the native "always show the numbers" switch, and setting
-- it is exactly what ticking Blizzard's own checkbox does. No draw-layer
-- surgery, no re-anchoring, nothing to re-assert - the CVar is read live and
-- CVAR_UPDATE makes the manager refresh the bars for us.
--
-- The two other terms in that expression are both mouseover machinery and
-- neither is usable here: StatusTrackingBarContainerMixin:ShowText/HideText
-- set the per-bar `textLocked` on enter and clear it on leave, so a lock we
-- set would be wiped the first time the cursor crossed the bar.
--
-- Which is also why this is ONE setting and not two. The old profile had
-- independent alwaysShowXP and alwaysShowRep flags because DragonflightUI
-- built two separate bars of its own. On stock 1.15.9 both bars share
-- ShouldBarTextBeDisplayed, so there is a single switch covering both, and
-- pretending otherwise in the options panel would be a lie.
--------------------------------------------------------------------------

local CVAR = "xpBarText"

-- The player's own value, remembered in saved variables rather than a
-- file-local. A cvar survives /reload but a file-local does not, so a local
-- would be re-captured from the value HelloUI itself had just written - and
-- then "disable the feature" would restore "1" forever, having quietly eaten
-- the player's real setting on the first reload.
local function rememberOriginal(value)
    HelloUIDB = HelloUIDB or {}
    if HelloUIDB.xpBarTextOriginal == nil then
        HelloUIDB.xpBarTextOriginal = value
    end
end

local function takeOriginal()
    local v = HelloUIDB and HelloUIDB.xpBarTextOriginal
    if HelloUIDB then HelloUIDB.xpBarTextOriginal = nil end
    return v
end

local function getCVar()
    if C_CVar and C_CVar.GetCVar then return C_CVar.GetCVar(CVAR) end
    return GetCVar and GetCVar(CVAR)
end

local function setCVar(value)
    local setter = (C_CVar and C_CVar.SetCVar) or SetCVar
    if not setter then return false end
    return pcall(setter, CVAR, value)
end

function StatusBars:Apply()
    local want = Config:Enabled("alwaysShowBarText")

    local current = getCVar()
    if current == nil then return end

    local target
    if want then
        rememberOriginal(current)
        target = "1"
    else
        -- Nothing remembered means we never changed it, so there is nothing to
        -- put back and the player's current value stands.
        target = takeOriginal() or current
    end

    if current == target then return end

    setCVar(target)

    -- Blizzard refreshes on CVAR_UPDATE, but nudging the manager directly
    -- means the change lands immediately rather than on the next event.
    local mgr = _G["StatusTrackingBarManager"]
    if mgr and mgr.UpdateBarTextVisibility then
        pcall(mgr.UpdateBarTextVisibility, mgr)
    end
end


--------------------------------------------------------------------------
-- Width
--
-- Edit Mode has no width control for these bars. Its "Size" setting is a
-- scale - SetScale(value / 100) - so narrowing the bar with it squashes the
-- height too, and it floors at 50%, which on a 1024px container is still
-- wider than the 454px action bar stack. Both were wrong in different
-- directions, which is why the width is set directly here.
--
-- Three frames per container, because they do not follow each other:
-- StatusTrackingBarTemplate's inner StatusBar carries an explicit
-- <Size x="1024"> and is anchored only at RIGHT, so it does not track its
-- parent's width, and StatusTrackingBarContainerMixin:InitializeBars stamps
-- that size in again at creation from the container's width.
--
-- Re-asserted after UpdateBarVisuals, which Blizzard calls on anchor changes
-- and from UIParent_ManageFramePositions. The hook goes on the manager
-- INSTANCE, not StatusTrackingManagerMixin - Mixin() copies functions onto
-- the frame at creation, so hooking the mixin table reaches nothing.
--------------------------------------------------------------------------

local savedWidth = {}

local function containers()
    local mgr = _G["StatusTrackingBarManager"]
    return mgr and mgr.barContainers
end

local function setWidth(frame, width)
    if not (frame and frame.SetWidth and frame.GetWidth) then return end
    if savedWidth[frame] == nil then savedWidth[frame] = frame:GetWidth() end
    frame:SetWidth(width or savedWidth[frame])
end

-- Derived from the real main action bar rather than a stored constant, and
-- scale-aware. StatusTrackingManagerMixin:UpdateBarVisuals calls
-- SetScale(self.ClassicScale) on the manager, so a width set in the
-- container's own coordinate space does not render at that many screen
-- pixels: 454 in a container scaled 1.4 draws 636 wide, which is what made
-- the bar overshoot the stack on the right. Converting through effective
-- scales makes it match whatever the bar actually measures, whatever either
-- scale happens to be.
local function wantedWidth(container)
    local configured = Config:Get("statusBarWidth")
    if not Config:Enabled("statusBarWidth") or configured == 0 then return nil end

    local bar = _G["MainActionBar"]
    if not (bar and bar.GetWidth and container.GetEffectiveScale) then return configured end

    local barWidth = bar:GetWidth()
    if not barWidth or barWidth <= 0 then return configured end

    local barScale = (bar.GetEffectiveScale and bar:GetEffectiveScale()) or 1
    local ownScale = container:GetEffectiveScale() or 1
    if ownScale <= 0 then return configured end

    return barWidth * barScale / ownScale
end

local function applyWidth()
    local list = containers()
    if not list then return end

    for _, container in ipairs(list) do
        local want = wantedWidth(container)
        setWidth(container, want)
        if container.bars then
            -- Keyed by StatusTrackingBarInfo.BarsEnum, so pairs not ipairs.
            for _, bar in pairs(container.bars) do
                setWidth(bar, want)
                setWidth(bar.StatusBar, want)
            end
        end
    end
end

-- Apply runs on every ApplyAll; width is cheap and idempotent.
local applyText = StatusBars.Apply
function StatusBars:Apply()
    applyText(self)
    applyWidth()
end

function StatusBars:Init()
    local mgr = _G["StatusTrackingBarManager"]
    if mgr and mgr.UpdateBarVisuals then
        hooksecurefunc(mgr, "UpdateBarVisuals", function()
            ns:SafeCall("StatusBars:width", applyWidth)
        end)
        StatusBars.hookedVisuals = true
    end
end

function StatusBars:StatusText()
    if getCVar() == nil then
        return "status bars: |cffff8080no xpBarText cvar|r"
    end
    return nil
end

function StatusBars:Status()
    local current = getCVar()
    if current == nil then
        ns:Print("status bars: |cffff8080xpBarText cvar not found|r")
        return
    end
    ns:Print("status bars: xpBarText=%s |cff808080(one switch covers both the XP and reputation bar)|r",
        tostring(current))
end
