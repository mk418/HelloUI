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

local original = nil

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

    if original == nil then original = current end

    local target = want and "1" or original
    if current == target then return end

    setCVar(target)

    -- Blizzard refreshes on CVAR_UPDATE, but nudging the manager directly
    -- means the change lands immediately rather than on the next event.
    local mgr = _G["StatusTrackingBarManager"]
    if mgr and mgr.UpdateBarTextVisibility then
        pcall(mgr.UpdateBarTextVisibility, mgr)
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
