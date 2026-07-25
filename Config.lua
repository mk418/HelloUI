local ADDON_NAME, ns = ...

ns.Config = {}
local Config = ns.Config

--------------------------------------------------------------------------
-- Defaults
--
-- These are not neutral defaults, and they are not meant to be. This addon
-- exists to reproduce one specific layout that was already in use across 47
-- characters under DragonflightUI, so the defaults ARE that layout - see the
-- evidence table in DESIGN.md. A fresh install should look like the thing it
-- replaced, not like a blank slate that has to be re-configured from scratch.
--
-- Everything is individually switchable, and `/hui reset` puts these back.
--------------------------------------------------------------------------

local accountDefaults = {
    enabled = true,

    -- Buttons.lua. The most-set pair in the old profile: both flags, on every
    -- single bar, with no exceptions anywhere.
    hideKeybindText = true,
    hideMacroText   = true,

    -- Bars.lua. One bar was switched off on every character - and mind the
    -- numbering. The old profile called it "bar4", but DragonflightUI bound
    -- its bar4 to MultiBarLeft, which the game itself calls bar 5
    -- (PROXY_SHOW_ACTIONBAR_5). These ids follow Blizzard's numbering,
    -- because that is what the labels in the game's own Action Bars options
    -- say, so the same physical bar is bar5 here. See Bars.lua.
    --
    -- The stance and pet entries exist because a character running one of the
    -- class addons wants them off too, but that is a per-character call
    -- rather than an account-wide one - see the char override machinery below.
    barsOff = {
        bar5 = true,
    },

    -- StatusBars.lua. "Always show" means the bar text is permanently
    -- readable instead of appearing only on mouseover; the bars themselves
    -- were always visible. ONE setting, not the two the old profile had:
    -- stock 1.15.9 gates both the XP and reputation bar through the same
    -- ShouldBarTextBeDisplayed, so there is a single native switch covering
    -- both and splitting it here would be a lie.
    alwaysShowBarText = true,

    -- Player.lua. The only unit frame setting in the entire old profile.
    classColorPlayerHealth = true,

    -- Darkmode.lua. Desaturate plus a flat grey tint, per area, matching the
    -- old module's own defaults (0.4 grey everywhere except unit frames,
    -- which used 77/255 - close enough to the same intent that one value
    -- covers both, and the difference was invisible in play).
    -- Two of the old profile's six areas are gone: `buffs` has no stock
    -- target (1.15.9 aura buttons are anonymous pooled frames whose only
    -- border is dispel-type colour) and `ui` was already a no-op in the old
    -- module. See Darkmode.lua.
    darkmode = true,
    darkmodeDesaturate = true,
    darkmodeTint = { r = 0.4, g = 0.4, b = 0.4 },
    darkmodeAreas = {
        unitframes = true,
        minimap    = true,
        actionbars = true,
        castbar    = true,
    },

    -- Minimap.lua. On Era this button is the time-of-day sun/moon dial, not
    -- a calendar - Classic Era loads GameTime_NoCalendar. There is no tuck
    -- setting because stock 1.15.9 already anchors the minimap flush
    -- top-right and MinimapCluster is an Edit Mode system; moving it is Edit
    -- Mode's job.
    hideTimeOfDay = true,

    -- No chat settings. The old profile pinned ChatFrame1 to 460x207 at
    -- 42,35, but on 1.15.9 ChatFrame1 inherits EditModeChatFrameSystemTemplate
    -- and Edit Mode owns its anchor AND its width and height. Same reasoning
    -- as the minimap: that is Edit Mode's job now.

    -- Friends.lua.
    friendsClassColor = true,
    friendsHeart = true,
}

-- Per-character. Sparse on purpose: a key is only present here once it has
-- been explicitly overridden for this character, so an account-wide change
-- still reaches every character that has not opted out.
--
-- 47 characters shared one layout and exactly one character diverged, so this
-- is deliberately not a profile manager. It is an exception list.
local charDefaults = {
    overrides = {},
}

local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = {}
                applyDefaults(target[k], v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            applyDefaults(target[k], v)
        end
    end
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, sub in pairs(v) do out[k] = copy(sub) end
    return out
end

function Config:Init()
    HelloUIDB = HelloUIDB or {}
    HelloUICharDB = HelloUICharDB or {}
    applyDefaults(HelloUIDB, accountDefaults)
    applyDefaults(HelloUICharDB, charDefaults)
end

--------------------------------------------------------------------------
-- Reads
--
-- One resolution rule, used by every module: this character's override if it
-- has one, otherwise the account value.
--------------------------------------------------------------------------

function Config:Get(key)
    local o = HelloUICharDB and HelloUICharDB.overrides
    if o and o[key] ~= nil then return o[key] end
    return HelloUIDB and HelloUIDB[key]
end

function Config:GetTable(key)
    local v = Config:Get(key)
    if type(v) == "table" then return v end
    -- A missing table is a bug in the defaults rather than a user state, but
    -- returning an empty one keeps every caller free of nil checks.
    return {}
end

-- Convenience for the many boolean features: false whenever the addon as a
-- whole is switched off, so `/hui off` is one check rather than nine.
function Config:Enabled(key)
    if not Config:Get("enabled") then return false end
    if key == nil then return true end
    return Config:Get(key) and true or false
end

--------------------------------------------------------------------------
-- Writes
--------------------------------------------------------------------------

function Config:Set(key, value)
    HelloUIDB = HelloUIDB or {}
    HelloUIDB[key] = value
end

function Config:SetChar(key, value)
    HelloUICharDB = HelloUICharDB or {}
    HelloUICharDB.overrides = HelloUICharDB.overrides or {}
    HelloUICharDB.overrides[key] = value
end

function Config:ClearChar(key)
    local o = HelloUICharDB and HelloUICharDB.overrides
    if o then o[key] = nil end
end

function Config:HasChar(key)
    local o = HelloUICharDB and HelloUICharDB.overrides
    return o ~= nil and o[key] ~= nil
end

function Config:HasAnyCharOverride()
    local o = HelloUICharDB and HelloUICharDB.overrides
    if not o then return false end
    return next(o) ~= nil
end

function Config:CharOverrideList()
    local o = HelloUICharDB and HelloUICharDB.overrides
    if not o then return "none" end
    local keys = {}
    for k in pairs(o) do keys[#keys + 1] = k end
    table.sort(keys)
    if #keys == 0 then return "none" end
    return table.concat(keys, ", ")
end

function Config:ResetAccount()
    HelloUIDB = {}
    applyDefaults(HelloUIDB, accountDefaults)
end

function Config:ResetChar()
    HelloUICharDB = { overrides = {} }
end

-- Defaults are handed out as copies. A caller that mutated the live default
-- table would silently change what "reset" means for every future character.
function Config:Default(key)
    return copy(accountDefaults[key])
end

function Config:DefaultKeys()
    local keys = {}
    for k in pairs(accountDefaults) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys
end

--------------------------------------------------------------------------
-- /hui char
--
-- The whole per-character story in one subcommand, because the only thing it
-- is ever used for is "this warrior wants Blizzard's bar 1 and stance bar
-- gone, everybody else keeps them".
--------------------------------------------------------------------------

function Config:CharCommand(rest)
    rest = rest or ""
    local sub, arg = rest:match("^(%S*)%s*(.-)$")

    if sub == "clear" then
        Config:ResetChar()
        ns:ApplyAllWhenSafe()
        ns:Print("character overrides cleared - back to the account layout")
        return
    end

    if sub == "barsoff" then
        local function report()
            local off = Config:GetTable("barsOff")
            local list = {}
            for id, v in pairs(off) do
                if v then list[#list + 1] = id end
            end
            table.sort(list)
            ns:Print("bars off here: %s%s",
                #list > 0 and table.concat(list, ", ") or "none",
                Config:HasChar("barsOff") and " |cff808080(character override)|r" or " |cff808080(account)|r")
        end

        if arg == "" then
            report()
            return
        end

        -- Validate against the real bar table rather than accepting anything
        -- that looks like a word. A typo used to be stored silently and then
        -- reported back as if it had worked, which is the worst of both.
        local valid = {}
        for _, def in ipairs(ns.BARS or {}) do valid[def.id] = true end

        local off = copy(Config:GetTable("barsOff"))
        local unknown, touched = {}, {}
        for id in arg:gmatch("[%w]+") do
            if valid[id] then
                off[id] = not off[id] and true or false
                touched[#touched + 1] = id
            else
                unknown[#unknown + 1] = id
            end
        end

        if #unknown > 0 then
            ns:Print("|cffff8080unknown bar%s:|r %s", #unknown > 1 and "s" or "",
                table.concat(unknown, ", "))
            ns:Print("  |cff808080ids: bar1 bar2 bar3 bar4 bar5 bar6 bar7 bar8 stance pet|r")
        end
        if #touched == 0 then return end

        Config:SetChar("barsOff", off)
        ns:ApplyAllWhenSafe()
        -- Report the bars, not the override key. This used to print
        -- CharOverrideList(), which is the list of overridden SETTING names -
        -- so it always said "barsOff" no matter which bars you had toggled.
        report()
        return
    end

    if Config:HasAnyCharOverride() then
        ns:Print("overrides on this character: %s", Config:CharOverrideList())
    else
        ns:Print("no overrides on this character - using the account layout")
    end
    ns:Print("usage: /hui char |cff808080[clear | barsoff <id ...>]|r")
    ns:Print("  |cff808080ids: bar1 bar2 bar3 bar4 bar5 bar6 bar7 bar8 stance pet|r")
end
