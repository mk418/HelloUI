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

--------------------------------------------------------------------------
-- The flat style
--
-- HelloWarrior's cast bar reads better than Blizzard's, and almost all of the
-- difference is art rather than shape: the fill texture is ALREADY the same one
-- (CastingBarMixin:UpdateBarFillTexture sets Interface\TargetingFrame\UI-StatusBar
-- on the classic-style path), so what is left is the 256x64 border wrapped
-- around a 195x13 bar, a centred spell name, and no countdown.
--
-- So this is the hideBarArt pattern, not a reimplementation: hide Blizzard's
-- border, put a flat backdrop behind the fill, move the name to the left and add
-- the countdown the frame does not have. No shipped textures - the backdrop is a
-- solid colour and everything else is Blizzard's own.
--
-- THE COUNTDOWN HAS TO BE OURS. CastingBarMixin:UpdateCastTimeTextShown opens
-- with `if not self.CastTimeText then return end`, and the Classic template
-- declares no such region - Enum.EditModeCastBarSetting.ShowCastTime exists but
-- the Classic preset does not carry it either. So the timer is a FontString of
-- ours fed from the mixin's own self.value / self.maxValue.
--
-- THE COLOUR NEEDS RE-ASSERTING, unlike everything else here. UpdateBarFillTexture
-- re-applies a per-bar-type colour on every cast and every state change, so a
-- colour set once is gone by the next spell. Hooked on the INSTANCE - Mixin()
-- copies the method onto the frame, so hooking the mixin table would reach
-- nothing, the same trap StatusBars documents.
--------------------------------------------------------------------------

local GOLD = { 0.85, 0.70, 0.30 }  -- HelloWarrior's, so the two match exactly

local saved = {}

local function remember(f)
    if saved[f] then return end
    -- Spelled out rather than `f.Text and f.Text:GetPoint(1)`: `and` truncates a
    -- multiple return to its first value, so that form silently records the
    -- point and drops the other four, and the restore path would put the spell
    -- name back with no offsets at all.
    local point, rel, relPoint, x, y
    if f.Text and f.Text.GetPoint then
        point, rel, relPoint, x, y = f.Text:GetPoint(1)
    end
    saved[f] = {
        border = f.Border and f.Border:IsShown(),
        shield = f.BorderShield and f.BorderShield:IsShown(),
        flash = f.Flash and f.Flash:IsShown(),
        textPoint = point, textRel = rel, textRelPoint = relPoint,
        textX = x, textY = y,
        justify = f.Text and f.Text.GetJustifyH and f.Text:GetJustifyH(),
    }
end

local function ensureParts(f)
    if not f.HelloUIBackdrop and f.CreateTexture then
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.55)
        f.HelloUIBackdrop = bg
    end
    if not f.HelloUITimer and f.CreateFontString then
        local timer = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timer:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        f.HelloUITimer = timer
    end
end

-- Fed from the mixin's own numbers rather than a second read of the cast API:
-- self.value and self.maxValue are what the bar is drawing, so the digits cannot
-- disagree with the fill.
local function updateTimer(f)
    local timer = f.HelloUITimer
    if not timer then return end
    if not (f.value and f.maxValue) or not f:IsShown() then
        timer:SetText("")
        return
    end
    local remaining = f.channeling and f.value or (f.maxValue - f.value)
    if remaining < 0 then remaining = 0 end
    timer:SetText(("%.1f"):format(remaining))
end

local function applyStyle(f)
    remember(f)
    ensureParts(f)

    if f.Border then f.Border:Hide() end
    if f.BorderShield then f.BorderShield:Hide() end
    -- The flash is the same 256x64 border shape lighting up on a completed cast.
    -- Kept hidden with the border, or a successful cast draws a glowing outline
    -- around art that is no longer there.
    if f.Flash then f.Flash:Hide() end

    if f.HelloUIBackdrop then f.HelloUIBackdrop:Show() end
    if f.HelloUITimer then f.HelloUITimer:Show() end

    if f.Text then
        f.Text:ClearAllPoints()
        f.Text:SetPoint("LEFT", f, "LEFT", 4, 0)
        f.Text:SetPoint("RIGHT", f, "RIGHT", -40, 0)
        if f.Text.SetJustifyH then f.Text:SetJustifyH("LEFT") end
    end

    f:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3])
end

local function restoreStyle(f)
    local s = saved[f]
    if not s then return end

    if f.Border and s.border then f.Border:Show() end
    if f.BorderShield and s.shield then f.BorderShield:Show() end
    if f.Flash and s.flash then f.Flash:Show() end

    if f.HelloUIBackdrop then f.HelloUIBackdrop:Hide() end
    if f.HelloUITimer then f.HelloUITimer:Hide() end

    if f.Text and s.textPoint then
        f.Text:ClearAllPoints()
        f.Text:SetPoint(s.textPoint, s.textRel, s.textRelPoint, s.textX, s.textY)
        if f.Text.SetJustifyH and s.justify then f.Text:SetJustifyH(s.justify) end
    end

    -- Blizzard's own colour, recomputed rather than remembered: it depends on the
    -- bar type, so a value captured while a normal spell was casting would be
    -- wrong to hand back after a channel.
    if f.UpdateBarFillTexture then pcall(f.UpdateBarFillTexture, f, false) end

    saved[f] = nil
end

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

    if Config:Enabled("castBarStyle") then
        applyStyle(f)
        CastBar.styled = true
    else
        restoreStyle(f)
        CastBar.styled = false
    end

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

function CastBar:Init()
    local f = playerBar()
    if not f then return end

    -- The colour is the one thing here Blizzard overwrites: UpdateBarFillTexture
    -- re-applies a per-bar-type colour on every cast, channel and interrupt.
    if f.UpdateBarFillTexture then
        hooksecurefunc(f, "UpdateBarFillTexture", function(self)
            if Config:Enabled("castBarStyle") then
                self:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3])
            end
        end)
        CastBar.hookedFill = true
    end

    -- The countdown rides Blizzard's own OnUpdate rather than a second ticker of
    -- ours: the frame is already updating every frame while it is shown, and a
    -- hook is one line against a whole parallel timer.
    if f.HookScript then
        f:HookScript("OnUpdate", function(self)
            if CastBar.styled then updateTimer(self) end
        end)
        CastBar.hookedUpdate = true
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
