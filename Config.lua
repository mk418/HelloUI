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

    -- The gryphons and the main bar backdrop. The old profile asked for both
    -- (`gryphons = 'NONE'`, `hideArt = true`); on a stock client that is real
    -- work rather than the no-op it looked like. See Bars.lua.
    hideBarArt = true,

    -- With the bar backdrop gone, each button's own border is all that is
    -- left - and stock ships it at alpha 0.5, which reads as no border at
    -- all. Full alpha, using Blizzard's own texture. See Buttons.lua.
    buttonBorders = true,

    -- Show empty action slots. On, the bars keep their full shape - which is
    -- what makes the flanking blocks read as 4x3 rather than as a couple of
    -- stray buttons, and matches DragonflightUI's alwaysShow default. Off,
    -- Blizzard hides empty slots, so a bar you have not filled disappears
    -- instead of showing a grid of empty squares. Applies through the Edit
    -- Mode layout, so it needs `/hui layout` to take effect.
    showEmptyButtons = true,

    -- The up/down arrows beside bar 1 that page it to another bar. Blizzard's
    -- own HideBarScrolling setting, applied through the Edit Mode layout.
    hidePagingArrows = true,

    -- Bars.lua. DragonflightUI's own base action bar set: bars 1-5 shown,
    -- 6-8 off (its defaults have activate=false for those three), stance and
    -- pet shown. This replaces the earlier profile-derived default, which had
    -- bar 5 off because that is what the old saved profile happened to say -
    -- the base UI is the better baseline, and bar 5 is part of it.
    --
    -- Mind the numbering: these ids are Blizzard's, matching the labels in the
    -- game's own Action Bars options. DragonflightUI's bar4/bar5 are the other
    -- way round. See Bars.lua.
    barsOff = {
        bar6 = true,
        bar7 = true,
        bar8 = true,
    },

    -- StatusBars.lua. "Always show" means the bar text is permanently
    -- readable instead of appearing only on mouseover; the bars themselves
    -- were always visible. ONE setting, not the two the old profile had:
    -- stock 1.15.9 gates both the XP and reputation bar through the same
    -- ShouldBarTextBeDisplayed, so there is a single native switch covering
    -- both and splitting it here would be a lie.
    alwaysShowBarText = true,

    -- Width of the XP/reputation bars, matched to the action bar stack: 12
    -- buttons at a 38px pitch, less the trailing padding. Edit Mode offers no
    -- width control for these - only a scale, which squashes the height - so
    -- this is set directly. 0 leaves Blizzard's 1024 alone.
    statusBarWidth = 454,

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

    -- Three shipped defects in one 33-line Blizzard file, all covered by this
    -- one switch because they are all the same button: it is declared with no
    -- parent at all, so Era strands it in the screen corner next to the player
    -- frame; it is only ever shown from MINIMAP_UPDATE_TRACKING, so a character
    -- who logs in with tracking already active never sees it; and its ring is
    -- declared 64x64 where every other minimap button in the client uses 52x52
    -- on the same 33x33 frame with the same texture, so it drew 23% oversized.
    fixTrackingIcon = true,

    -- Where on the minimap's rim it lands, in degrees around the map from the
    -- LFG eye, counting downwards. 30 is one button-width of arc at that
    -- radius, so it clears the eye and rides the same circle.
    --
    -- A setting rather than a constant because the rim belongs to every addon
    -- that puts a button there, and this addon cannot see those. `/hui tracking
    -- <degrees>` moves it live; negative goes up instead of down.
    trackingAngle = 30,

    -- Compensates the clock's scale so its text renders at native size and on
    -- the pixel grid even with the minimap scaled up, and rounds Blizzard's
    -- half-pixel anchor once that is true. See Minimap.lua - the first attempt
    -- rounded the anchor alone, which could not work while the subtree was at
    -- 110%.
    fixClockText = true,

    -- Where the clock digits sit inside their box. Blizzard uses 3, 1.5;
    -- the y is rounded to the grid and both are nudgeable with
    -- `/hui clock <x> <y>` because the right optical offset cannot be read
    -- off a screenshot.
    -- 1, -1 rather than Blizzard's 3, 1.5: dialled in live with /hui clock,
    -- which is the only way to settle an optical offset against art whose
    -- own HitRectInsets (8 left, 5 right) say the box is not symmetric.
    clockTextX = 1,
    clockTextY = -1,

    -- Minimap size, as Edit Mode's raw slider value: 5 is 100%, 6 is 110%,
    -- each step 10%. Applied through the layout.
    --
    -- 110% is a non-integer scale, which puts the whole minimap subtree -
    -- clock digits included - on fractional pixels and softens any text drawn
    -- there. That is the likely cause of the clock looking off, and it is a
    -- straight trade: 5 is crisp at the original size, 6 is bigger and
    -- slightly soft. 10 would be 200%, the next scale that is a whole number,
    -- and far too large.
    minimapSize = 6,

    -- No chat settings. The old profile pinned ChatFrame1 to 460x207 at
    -- 42,35, but on 1.15.9 ChatFrame1 inherits EditModeChatFrameSystemTemplate
    -- and Edit Mode owns its anchor AND its width and height. Same reasoning
    -- as the minimap: that is Edit Mode's job now.

    -- Layout.lua. At login, offer the DragonflightUI bar arrangement as a
    -- real Edit Mode layout - asked, never applied silently, and only when it
    -- is not already active. Off means HelloUI never touches Edit Mode unless
    -- you run `/hui layout`.
    askLayout = true,

    -- Account-wide by default: 47 characters shared one arrangement, and that
    -- is still the sensible default. This is a PER-CHARACTER decision though -
    -- the options checkbox and `/hui layout char` write it as a character
    -- override, so one character opting out leaves everyone else alone.
    -- Blizzard caps layouts at five per type.
    layoutPerCharacter = false,

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

    -- One-time: replace the profile-derived bar set with DragonflightUI's
    -- base one. applyDefaults only ever FILLS IN missing keys, so changing
    -- the default could not remove the `bar5 = true` an existing install had
    -- already saved - the new default quietly added 6/7/8 on top of it and
    -- the result was bars 5 through 8 all dark. Defaults cannot migrate
    -- state; migrations have to.
    if not HelloUIDB.barsBaseV2 then
        HelloUIDB.barsBaseV2 = true
        HelloUIDB.barsOff = copy(accountDefaults.barsOff)
    end
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
    -- Reset already installs the base bar set, so the migration has nothing
    -- left to do. Marking it done matters: without this the latch is gone and
    -- the migration re-runs at the next login, wiping any bar the player
    -- changed in between.
    HelloUIDB.barsBaseV2 = true
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
