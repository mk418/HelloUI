local ADDON_NAME, ns = ...
ns.ADDON_NAME = ADDON_NAME
ns.VERSION = "0.2.9"

local PREFIX = "|cff80c0ffHelloUI|r "

function ns:Print(fmt, ...)
    if select("#", ...) > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. fmt:format(...))
    else
        DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. tostring(fmt))
    end
end

--------------------------------------------------------------------------
-- Client API
--
-- 1.15.9 moved Classic Era onto the shared modern UI codebase, so this addon
-- runs against a client that has Edit Mode, retail-style action bars and
-- pooled party frames. Everything version-sensitive is resolved once, here,
-- the same way HelloGear does it.
--------------------------------------------------------------------------

ns.API = {}
ns.API.IsEventValid  = C_EventUtils and C_EventUtils.IsEventValid
ns.API.IsAddOnLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
ns.API.GetClassColor = C_ClassColor and C_ClassColor.GetClassColor

-- The client carries the modern UI. This is the same feature-detect
-- DragonflightUI settled on, and it is a deliberate feature test rather than
-- an interface-version comparison: Blizzard is rolling the modern backport
-- across flavours, and the frame is a better answer than the build number.
ns.IsModern = (EditModeManagerFrame ~= nil) or (StatusTrackingBarManager ~= nil)

-- Class colours. CUSTOM_CLASS_COLORS is the long-standing community override
-- (Shaman-blue and friends); honour it when another addon has installed one.
function ns:ClassColor(classFilename)
    if not classFilename then return 1, 1, 1 end

    local custom = CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[classFilename]
    if custom then return custom.r, custom.g, custom.b end

    if ns.API.GetClassColor then
        local c = ns.API.GetClassColor(classFilename)
        if c then return c.r, c.g, c.b end
    end

    local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFilename]
    if c then return c.r, c.g, c.b end

    return 1, 1, 1
end

--------------------------------------------------------------------------
-- Events
--
-- RegisterEvent is guarded. Passing an event this client refuses throws a hard
-- Lua error, and that is exactly how DragonflightUI died on 1.15.9: the client
-- answered RegisterEvent("MINIMAP_PING") with `Attempt to register unknown
-- event` and the unguarded call took the whole minimap module down on every
-- login. The event itself still exists - Blizzard just reaches it through
-- RegisterEventCallback now. Ask first, and have a fallback.
--------------------------------------------------------------------------

ns.eventFrame = CreateFrame("Frame")
ns.eventHandlers = {}

ns.eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handlers = ns.eventHandlers[event]
    if not handlers then return end
    for i = 1, #handlers do
        ns:SafeCall("event " .. event, handlers[i], ...)
    end
end)

function ns:EventExists(event)
    if ns.API.IsEventValid then return ns.API.IsEventValid(event) end
    -- No IsEventValid on this client: probe it and let pcall absorb the throw.
    local probe = CreateFrame("Frame")
    local ok = pcall(probe.RegisterEvent, probe, event)
    if ok then probe:UnregisterAllEvents() end
    return ok
end

function ns:On(event, fn)
    if not ns.eventHandlers[event] then
        if not ns:EventExists(event) then return false end

        -- Registered through pcall even though EventExists just said yes.
        -- On this build "valid" and "registerable" have come apart for at
        -- least one event: the client rejects RegisterEvent("MINIMAP_PING")
        -- outright with `Attempt to register unknown event`, and Blizzard's
        -- own minimap code now reaches it through RegisterEventCallback
        -- instead. Without the pcall an unlucky event name throws at
        -- file-load time and takes the whole addon down - which is precisely
        -- the failure this guard exists to prevent.
        local ok = pcall(ns.eventFrame.RegisterEvent, ns.eventFrame, event)
        if not ok then
            -- Callback-only events are a real category on 1.15.9 and have
            -- their own registration path. The owner arrives as the first
            -- argument, so it is stripped to match what ns:On handlers expect.
            local isCallback = C_EventUtils and C_EventUtils.IsCallbackEvent
                and C_EventUtils.IsCallbackEvent(event)
            if not (isCallback and ns.eventFrame.RegisterEventCallback) then
                return false
            end
            local okCb = pcall(ns.eventFrame.RegisterEventCallback, ns.eventFrame, event,
                function(_owner, ...)
                    local handlers = ns.eventHandlers[event]
                    if not handlers then return end
                    for i = 1, #handlers do
                        ns:SafeCall("event " .. event, handlers[i], ...)
                    end
                end)
            if not okCb then return false end
        end

        ns.eventHandlers[event] = {}
    end
    table.insert(ns.eventHandlers[event], fn)
    return true
end

--------------------------------------------------------------------------
-- Error containment
--
-- This addon reaches into a dozen Blizzard frames whose names could not all
-- be confirmed against a running 1.15.9 client while it was being written.
-- An unguarded nil index in one feature would abort the login-time apply and
-- silently take the other eight down with it, which is the failure mode that
-- made DragonflightUI unusable rather than merely imperfect.
--
-- So every entry point is wrapped, and a failure is reported once per site
-- per session: loud enough to be reportable, quiet enough not to spam a
-- raid. Deliberately not a blanket silent pcall - a swallowed error is how
-- you end up with a feature that has quietly done nothing for months.
--------------------------------------------------------------------------

local reported = {}

function ns:SafeCall(site, fn, ...)
    if type(fn) ~= "function" then return end
    local ok, err = pcall(fn, ...)
    if ok then return true end
    if not reported[site] then
        reported[site] = true
        ns:Print("|cffff8080error in %s:|r %s |cff808080(reported once)|r", site, tostring(err))
    end
    return false
end

--------------------------------------------------------------------------
-- Out-of-combat work queue
--
-- Action bars, the stance bar and the pet bar are protected. Hiding or
-- re-anchoring one in combat is blocked outright, so the work is deferred to
-- PLAYER_REGEN_ENABLED instead of attempted and lost.
--
-- Keyed rather than a plain list: a settings panel can produce a dozen
-- applies while the user drags a slider through a fight, and only the last
-- one matters. The key collapses them.
--------------------------------------------------------------------------

local pending = {}
local pendingOrder = {}

function ns:WhenSafe(key, fn)
    if not InCombatLockdown() then
        return ns:SafeCall(key, fn)
    end
    if pending[key] == nil then
        pendingOrder[#pendingOrder + 1] = key
    end
    pending[key] = fn
    return false
end

local function drain()
    if InCombatLockdown() then return end
    if #pendingOrder == 0 then return end

    local order, work = pendingOrder, pending
    pendingOrder, pending = {}, {}

    for i = 1, #order do
        local key = order[i]
        local fn = work[key]
        if fn then ns:SafeCall(key, fn) end
    end
end

--------------------------------------------------------------------------
-- Modules
--
-- Fixed order, named explicitly. Each feature file hangs a table off ns and
-- optionally implements Init (once, at login) and Apply (whenever settings
-- change). Options.lua re-applies everything rather than tracking which
-- setting belongs to which module - at this size the bookkeeping would cost
-- more than the work it saves.
--------------------------------------------------------------------------

ns.MODULES = {
    "Buttons",
    "Bars",
    "StatusBars",
    "Player",
    "Darkmode",
    "Minimap",
    "CastBar",
    "MirrorTimer",
}

-- Layout is deliberately NOT in that list. ns:ApplyAll runs on every
-- PLAYER_ENTERING_WORLD and on every options change, and a module in the list
-- has its Apply called each time - which for Layout would mean rewriting the
-- Edit Mode layout constantly and undoing any bar the player had dragged.
-- That is the exact behaviour the design forbids, so Layout is wired by hand:
-- Init at login, Apply only when explicitly asked.
ns.EXTRA_MODULES = { "Layout" }

function ns:InitModules()
    for _, name in ipairs(ns.MODULES) do
        local m = ns[name]
        if m and m.Init then
            ns:SafeCall(name .. ":Init", m.Init, m)
        end
    end
    for _, name in ipairs(ns.EXTRA_MODULES) do
        local m = ns[name]
        if m and m.Init then
            ns:SafeCall(name .. ":Init", m.Init, m)
        end
    end
end

function ns:ApplyAll()
    for _, name in ipairs(ns.MODULES) do
        local m = ns[name]
        if m and m.Apply then
            ns:SafeCall(name .. ":Apply", m.Apply, m)
        end
    end
end

-- Modules that touch protected frames route their apply through this so the
-- combat rule lives in one place.
function ns:ApplyAllWhenSafe()
    ns:WhenSafe("ApplyAll", function() ns:ApplyAll() end)
end

--------------------------------------------------------------------------
-- Boot
--------------------------------------------------------------------------

ns:On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    ns.Config:Init()
end)

ns:On("PLAYER_LOGIN", function()
    ns:InitModules()
    ns.Options:Init()
end)

-- The first full apply waits for PLAYER_ENTERING_WORLD rather than
-- PLAYER_LOGIN: several of the frames involved (the status tracking bars, the
-- calendar button) are laid out after login, and applying before that means
-- applying to frames Blizzard then re-lays-out underneath us.
ns:On("PLAYER_ENTERING_WORLD", function()
    ns:ApplyAllWhenSafe()
end)

ns:On("PLAYER_REGEN_ENABLED", drain)

--------------------------------------------------------------------------
-- Slash commands
--
-- Every short form the family would want is already taken - /hbc /hg /hh /hl
-- /hrd /hs /ht /hw /hwb - so /hui it is.
--------------------------------------------------------------------------

local function status()
    ns:Print("v%s - %s", ns.VERSION, ns.Config:Get("enabled") and "enabled" or "|cffff8080disabled|r")
    for _, name in ipairs(ns.MODULES) do
        local m = ns[name]
        if m and m.Status then
            ns:SafeCall(name .. ":Status", m.Status, m)
        end
    end
    for _, name in ipairs(ns.EXTRA_MODULES) do
        local m = ns[name]
        if m and m.Status then
            ns:SafeCall(name .. ":Status", m.Status, m)
        end
    end
    ns:Print("profile: |cffffd100%s|r |cff808080(of %d - /hui profile)|r",
        ns.Config:ProfileName(), #ns.Config:ProfileNames())
end

SlashCmdList["HELLOUI"] = function(msg)
    local cmd, rest = msg:lower():match("^(%S*)%s*(.-)$")

    if cmd == "" or cmd == "config" or cmd == "options" then
        ns.Options:Open()
    elseif cmd == "on" then
        ns.Config:Set("enabled", true)
        ns:ApplyAllWhenSafe()
        ns:Print("enabled")
    elseif cmd == "off" then
        ns.Config:Set("enabled", false)
        ns:ApplyAllWhenSafe()
        ns:Print("disabled - |cff808080/reload to fully restore Blizzard's own state|r")
    elseif cmd == "apply" then
        ns:ApplyAllWhenSafe()
        ns:Print("applied")
    elseif cmd == "status" then
        status()
    elseif cmd == "reset" then
        local name = ns.Config:ResetProfile()
        ns:ApplyAllWhenSafe()
        ns:Print("profile |cffffd100%s|r reset to defaults |cff808080(other profiles are untouched)|r", name)
    elseif cmd == "profile" then
        ns.Config:ProfileCommand(rest)
    elseif cmd == "clock" then
        local cx, cy = rest:match("^(-?%d+)%s+(-?%d+)$")
        if cx then
            ns.Minimap:NudgeClock(tonumber(cx), tonumber(cy))
        else
            ns.Minimap:NudgeClock()
        end
    elseif cmd == "tracking" then
        local deg = rest:match("^(-?%d+)$")
        ns.Minimap:NudgeTracking(deg and tonumber(deg) or nil)
    elseif cmd == "minimapprobe" then
        ns.Minimap:Probe()
    elseif cmd == "layout" then
        if rest == "status" then
            ns.Layout:Status()
        elseif rest == "probe" then
            ns.Layout:Probe()
        elseif rest == "char" or rest == "account" then
            ns:Print("layout: the layout follows your profile now - |cff808080/hui profile new <name>|r " ..
                "gives this character its own, |cff808080/hui profile use Default|r puts it back")
        else
            -- "reset" and no argument are the same thing: rebuild and
            -- overwrite, because Edit Mode saves dragging into the layout.
            ns.Layout:Reset()
        end
    else
        ns:Print("usage: /hui |cff808080[config | on | off | apply | status | reset | profile | layout]|r")
        ns:Print("  |cff808080profile|r           - which profile this character uses, and the rest")
        ns:Print("  |cff808080profile new <name>|r - branch a copy off the current one")
        ns:Print("  |cff808080layout|r            - build/reset the Dragonflight bar layout")
        ns:Print("  |cff808080layout probe|r      - print where the bars actually are")
        ns:Print("  |cff808080minimapprobe|r      - the tracking button and clock's real state")
        ns:Print("  |cff808080clock <x> <y>|r     - nudge the clock digits in their box")
        ns:Print("  |cff808080tracking <deg>|r    - move the tracking button round the minimap's rim")
    end
end

SLASH_HELLOUI1 = "/helloui"
SLASH_HELLOUI2 = "/hui"
