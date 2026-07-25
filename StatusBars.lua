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
