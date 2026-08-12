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

-- Eight things are deliberately NOT here. Hiding the gryphons and bar backdrop,
-- always-visible XP and reputation text, hiding the time-of-day dial,
-- class-colouring the player health bar, yielding the cast bar to a sibling
-- that draws its own, the flat cast bar, the matching flat breath meter, and
-- fitting Blizzard's oversized auto-attack flash to its button are what HelloUI
-- IS. They were switches because everything started as one; a switch implies a
-- decision worth making, and nobody was going to install this addon and then
-- turn those off. They now run whenever the addon is enabled, so `enabled` is
-- the only switch above them and `/hui off` still hands every one of them back.
local accountDefaults = {
    enabled = true,

    -- Buttons.lua. The most-set pair in the old profile: both flags, on every
    -- single bar, with no exceptions anywhere.
    hideKeybindText = true,
    hideMacroText   = true,

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

    -- Darkmode.lua. Desaturate plus a flat grey tint, per area, matching the
    -- old module's own defaults (0.4 grey everywhere except unit frames,
    -- which used 77/255 - close enough to the same intent that one value
    -- covers both, and the difference was invisible in play).
    -- Two of the old profile's six areas are gone: `buffs` has no stock
    -- target (1.15.9 aura buttons are anonymous pooled frames whose only
    -- border is dispel-type colour) and `ui` was already a no-op in the old
    -- module. See Darkmode.lua.
    darkmode = true,

    -- Three shipped defects in one 33-line Blizzard file, all covered by this
    -- one switch because they are all the same button: it is declared with no
    -- parent at all, so Era strands it in the screen corner next to the player
    -- frame; it is only ever shown from MINIMAP_UPDATE_TRACKING, so a character
    -- who logs in with tracking already active never sees it; and its ring is
    -- declared 64x64 where every other minimap button in the client uses 52x52
    -- on the same 33x33 frame with the same texture, so it drew 23% oversized.
    fixTrackingIcon = true,

    -- Where on the minimap's rim it lands, in degrees around the map from the
    -- LFG eye, counting downwards.
    --
    -- 19, not the 30 this shipped with. 30 was reasoned from the 33x33 FRAMES,
    -- and the frames are much bigger than the art they carry: the visible gold
    -- ring measures about 26.5 units across, so 30 degrees left a 15.7-unit
    -- hole between the two rings. The number that matters is the rim's own
    -- pitch - the twelve buttons on this minimap ride one circle and the packed
    -- pairs sit a median 24.9 units apart, essentially touching. At r=75 the
    -- chord for 19 degrees is 24.8. Measured off a screenshot rather than
    -- reasoned about, because the last two attempts at this were reasoned about.
    --
    -- A setting rather than a constant because the rim belongs to every addon
    -- that puts a button there, and this addon cannot see those. `/hui tracking
    -- <degrees>` moves it live; negative goes up instead of down. There is no
    -- clamp - a deliberate 45 is a legitimate answer to a crowded rim.
    trackingAngle = 19,

    -- Mirrors the clock text into an addon-owned foreground layer so minimap
    -- buttons cannot cover it, without changing Blizzard's clock frame inside
    -- the Edit Mode-managed minimap tree. See Minimap.lua.
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

    -- No chat toggle, which is not the same as ignoring the chat frame. On
    -- 1.15.9 it inherits EditModeChatFrameSystemTemplate, so its anchor and
    -- size belong to Edit Mode. The layout raises it above the stance bar and
    -- gives it a 250px height there; applying the layout is the decision, and
    -- Edit Mode owns it afterwards.

    -- Layout.lua. At login, offer the DragonflightUI bar arrangement as a
    -- real Edit Mode layout - asked, never applied silently, and only when it
    -- is not already active. Off means HelloUI never touches Edit Mode unless
    -- you run `/hui layout`.
    askLayout = true,

}

-- Per-character preferences contain only which profile this character uses.
-- Player.lua may also keep `targetOfTargetRepairStage` across ReloadUI so a
-- retained Classic Era layout entry gets a clearly labelled second prompt.
-- It records workflow state, never permission for automatic protected work.
--
-- This replaces a sparse override list that was explicitly "not a profile
-- manager, an exception list". The exception list was the right shape for one
-- diverging character out of 47; it is the wrong shape for "these settings
-- apply to everyone and that is annoying", which is what actually happens once
-- you have alts you play differently.
local DEFAULT_PROFILE = "Default"

local charDefaults = {
    profile = DEFAULT_PROFILE,
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

-- Keys nothing reads any more - some because the setting became unconditional
-- behaviour, some because the feature is gone. Deleted from saved variables on
-- sight rather than left to rot: an install that had ever ticked one carries the
-- key forever otherwise, and a stale `hideBarArt = false` sitting in the file
-- reads like a setting that stopped working rather than one that was retired.
local RETIRED = {
    -- Became unconditional behaviour.
    "hideBarArt", "alwaysShowBarText", "hideTimeOfDay",
    "classColorPlayerHealth", "yieldCastBar", "castBarStyle",
    -- Features removed outright: the friends list and the button borders are
    -- Blizzard's again.
    "friendsClassColor", "friendsHeart", "buttonBorders",
    -- Darkmode is one switch: the per-area picks, the desaturate toggle and the
    -- tint colour are gone, the tint being a constant in Darkmode.lua now.
    "darkmodeDesaturate", "darkmodeAreas", "darkmodeTint",
    -- Profiles replaced it: a character that wants its own Edit Mode layout
    -- wants its own profile, and gets one named after itself by the migration.
    "layoutPerCharacter",
}

local function dropRetired(t)
    if type(t) ~= "table" then return end
    for _, key in ipairs(RETIRED) do t[key] = nil end
end

-- Everything that is a SETTING, so the migration knows what to move into the
-- Default profile and what to leave at the top level as remembered state.
local function isSettingKey(key)
    return accountDefaults[key] ~= nil
end

function Config:Init()
    HelloUIDB = HelloUIDB or {}
    HelloUICharDB = HelloUICharDB or {}
    applyDefaults(HelloUICharDB, charDefaults)

    ----------------------------------------------------------------------
    -- Into profiles.
    --
    -- Before this, every setting sat at the top level of HelloUIDB and was
    -- shared by all 47 characters, with a sparse per-character override list
    -- beside it. The move is mechanical: the settings become the Default
    -- profile, the remembered originals and the latches stay where they are.
    --
    -- Latched on `profilesV1` rather than on "is profiles nil", because a
    -- perfectly good install can end up with an empty profiles table - delete
    -- every profile but Default, then reset it - and re-running the move then
    -- would drag stale top-level keys back in.
    ----------------------------------------------------------------------
    if not HelloUIDB.profilesV1 then
        HelloUIDB.profilesV1 = true
        local default = {}
        for key, value in pairs(HelloUIDB) do
            if isSettingKey(key) then
                default[key] = value
                HelloUIDB[key] = nil
            end
        end
        HelloUIDB.profiles = HelloUIDB.profiles or {}
        HelloUIDB.profiles[DEFAULT_PROFILE] = default
    end

    ----------------------------------------------------------------------
    -- A character that had overrides gets its own profile, named after itself.
    --
    -- Per character rather than all at once, because HelloUICharDB is only
    -- ever this character's - the others migrate themselves when they next log
    -- in, which is also when their name is knowable.
    --
    -- The name matters beyond tidiness: Layout names its Edit Mode layout
    -- "HelloUI - <profile>", and the old per-character layout was
    -- "HelloUI - <character>". Naming the profile after the character means the
    -- layout it already has is the layout it keeps.
    ----------------------------------------------------------------------
    local overrides = HelloUICharDB.overrides
    if type(overrides) == "table" and next(overrides) ~= nil then
        local who = (UnitName and UnitName("player")) or "Character"
        local mine = copy(HelloUIDB.profiles[DEFAULT_PROFILE] or {})
        for key, value in pairs(overrides) do
            if isSettingKey(key) then mine[key] = value end
        end
        HelloUIDB.profiles[who] = HelloUIDB.profiles[who] or mine
        HelloUICharDB.profile = who
    end
    HelloUICharDB.overrides = nil

    -- A profile this character points at can have been deleted by another
    -- character since. Fall back rather than resurrect it as a bag of defaults.
    if not HelloUIDB.profiles[Config:ProfileName()] then
        HelloUICharDB.profile = DEFAULT_PROFILE
    end

    -- Fill in and clean every profile, not just the active one: a key added in
    -- this release has to reach the profiles the player is not currently on, or
    -- switching to one hands back nils.
    HelloUIDB.profiles[DEFAULT_PROFILE] = HelloUIDB.profiles[DEFAULT_PROFILE] or {}
    for _, profile in pairs(HelloUIDB.profiles) do
        applyDefaults(profile, accountDefaults)
        dropRetired(profile)
    end
    dropRetired(HelloUIDB)

    -- One-time: replace the profile-derived bar set with DragonflightUI's
    -- base one. applyDefaults only ever FILLS IN missing keys, so changing
    -- the default could not remove the `bar5 = true` an existing install had
    -- already saved - the new default quietly added 6/7/8 on top of it and
    -- the result was bars 5 through 8 all dark. Defaults cannot migrate
    -- state; migrations have to.
    if not HelloUIDB.barsBaseV2 then
        HelloUIDB.barsBaseV2 = true
        for _, profile in pairs(HelloUIDB.profiles) do
            profile.barsOff = copy(accountDefaults.barsOff)
        end
    end

    -- Same trap, one setting over: every install that has ever logged in has
    -- `trackingAngle = 30` written to disk, so moving the default to 19 cannot
    -- reach it. See the comment above - defaults cannot migrate state.
    --
    -- Value-guarded, unlike barsBaseV2. barsOff is a table and had to be
    -- replaced wholesale; this is a scalar, so "only rewrite it if it is still
    -- literally the old default" is available, and that is what protects
    -- somebody who had already run `/hui tracking 45`.
    --
    -- The honest hole: a player who deliberately typed `/hui tracking 30` is
    -- indistinguishable from one who never touched it, and gets moved. There is
    -- no stored provenance to consult, and the alternative - leaving every 30
    -- alone - fixes nothing on the installs that have the problem.
    if not HelloUIDB.trackingAngleV2 then
        HelloUIDB.trackingAngleV2 = true
        for _, profile in pairs(HelloUIDB.profiles) do
            -- A literal, never accountDefaults: it names the historical value,
            -- not the current default, and the two must not drift together.
            if profile.trackingAngle == 30 then
                profile.trackingAngle = accountDefaults.trackingAngle
            end
        end
    end
end

--------------------------------------------------------------------------
-- Profiles
--
-- Settings live in HelloUIDB.profiles[name]; each character stores the name of
-- the one it uses. Switching profile is switching which table every Get reads.
--
-- What deliberately does NOT live in a profile: the things HelloUI remembers
-- about BLIZZARD's state - proxyOriginals and the legacy xpBarTextOriginal -
-- plus migration latches. Those are memory of what the client looked like
-- before we touched it, not preferences, and copying them into a profile would
-- mean a profile switch could hand back the wrong original.
--------------------------------------------------------------------------

local function profiles()
    HelloUIDB = HelloUIDB or {}
    HelloUIDB.profiles = HelloUIDB.profiles or {}
    return HelloUIDB.profiles
end

local function profileTable(name)
    local all = profiles()
    local p = all[name]
    if not p then
        p = {}
        applyDefaults(p, accountDefaults)
        all[name] = p
    end
    return p
end

function Config:ProfileName()
    local name = HelloUICharDB and HelloUICharDB.profile
    if type(name) ~= "string" or name == "" then return DEFAULT_PROFILE end
    return name
end

function Config:Profile()
    return profileTable(Config:ProfileName())
end

function Config:ProfileNames()
    local names = {}
    for name in pairs(profiles()) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function Config:ProfileExists(name)
    return profiles()[name] ~= nil
end

-- Characters on a profile can outlive the profile: one character deletes it,
-- another is still pointing at the name. Resolving that at load rather than
-- silently recreating an empty one is what stops a deleted profile coming back
-- from the dead full of defaults.
-- The Edit Mode layout follows the profile, and `wasActive` is read BEFORE the
-- switch on purpose: it answers "was the player using our layout a moment ago",
-- which is the consent that carries across. Asking afterwards would be asking
-- about the layout we just switched to.
local function followLayout(wasActive)
    if ns.Layout and ns.Layout.FollowProfile then
        ns:SafeCall("Layout:follow", ns.Layout.FollowProfile, ns.Layout, wasActive)
    end
end

local function layoutWasActive()
    if not (ns.Layout and ns.Layout.IsActive) then return false end
    local ok, active = pcall(ns.Layout.IsActive, ns.Layout)
    return ok and active or false
end

function Config:UseProfile(name)
    if type(name) ~= "string" or name:match("^%s*$") then return false, "a profile needs a name" end
    name = name:match("^%s*(.-)%s*$")
    HelloUICharDB = HelloUICharDB or {}
    local wasActive = layoutWasActive()
    profileTable(name)
    HelloUICharDB.profile = name
    followLayout(wasActive)
    return true, name
end

-- Copy, never a blank slate. "New profile" in most addons means "carry on from
-- what I have and diverge", and a fresh set of defaults is one `/hui reset`
-- away for anyone who wanted the other thing.
function Config:CopyProfile(name)
    if type(name) ~= "string" or name:match("^%s*$") then return false, "a profile needs a name" end
    name = name:match("^%s*(.-)%s*$")
    if Config:ProfileExists(name) then return false, ("there is already a profile called %s"):format(name) end
    local wasActive = layoutWasActive()
    profiles()[name] = copy(Config:Profile())
    HelloUICharDB.profile = name
    -- A brand new profile has no layout yet, so this is the case that builds
    -- one. Without it the next login asks for a layout the player already said
    -- yes to on the profile they copied from.
    followLayout(wasActive)
    return true, name
end

function Config:DeleteProfile(name)
    if name == DEFAULT_PROFILE then return false, "the Default profile cannot be deleted" end
    if not Config:ProfileExists(name) then return false, ("no profile called %s"):format(name) end
    local wasActive = layoutWasActive()
    profiles()[name] = nil
    if Config:ProfileName() == name then
        HelloUICharDB.profile = DEFAULT_PROFILE
        followLayout(wasActive)
    end
    return true, name
end

--------------------------------------------------------------------------
-- Reads
--
-- One resolution rule, used by every module: whatever this character's profile
-- says.
--------------------------------------------------------------------------

function Config:Get(key)
    return Config:Profile()[key]
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
    Config:Profile()[key] = value
end

-- Resets THIS profile, not the account. The other profiles are other
-- characters' business.
function Config:ResetProfile()
    local name = Config:ProfileName()
    local fresh = {}
    applyDefaults(fresh, accountDefaults)
    profiles()[name] = fresh
    -- Both migrations have already run against everything on disk; leaving the
    -- latches set stops a reset re-arming them to overwrite whatever gets
    -- dialled in next. Same bug the barsBaseV2 comment records.
    HelloUIDB.barsBaseV2 = true
    HelloUIDB.trackingAngleV2 = true
    return name
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
-- /hui profile
--
-- Everything the profile system needs from the command line, in the shape every
-- other addon's profile UI has taught people to expect: see where you are, go
-- somewhere else, branch off a copy, throw one away.
--------------------------------------------------------------------------

function Config:ProfileCommand(rest)
    rest = rest or ""
    local sub, arg = rest:match("^(%S*)%s*(.-)$")
    arg = arg and arg:match("^%s*(.-)%s*$") or ""

    local function report()
        local names = Config:ProfileNames()
        local current = Config:ProfileName()
        local marked = {}
        for _, name in ipairs(names) do
            marked[#marked + 1] = (name == current) and ("|cffffd100" .. name .. "|r") or name
        end
        ns:Print("profile: |cffffd100%s|r", current)
        ns:Print("  |cff808080all: %s|r", table.concat(marked, ", "))
    end

    if sub == "use" or sub == "switch" then
        if arg == "" then ns:Print("usage: /hui profile use <name>") return end
        if not Config:ProfileExists(arg) then
            -- Deliberately not created here. `use` on a typo silently making a
            -- fresh profile of defaults is how you lose a set of settings and
            -- think the addon broke; `new` is one word away.
            ns:Print("|cffff8080no profile called %s|r - /hui profile new %s makes one", arg, arg)
            return
        end
        Config:UseProfile(arg)
        ns:ApplyAllWhenSafe()
        ns:Print("profile: switched to |cffffd100%s|r", arg)
        ns:Print("  |cff808080run /hui layout if you want this profile's bar arrangement too|r")
        if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
        return
    end

    if sub == "new" or sub == "copy" then
        local ok, err = Config:CopyProfile(arg)
        if not ok then ns:Print("|cffff8080%s|r", err) return end
        ns:ApplyAllWhenSafe()
        ns:Print("profile: |cffffd100%s|r created from the one you were on, and now in use", arg)
        if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
        return
    end

    if sub == "delete" or sub == "remove" then
        local ok, err = Config:DeleteProfile(arg)
        if not ok then ns:Print("|cffff8080%s|r", err) return end
        ns:ApplyAllWhenSafe()
        ns:Print("profile: deleted |cffffd100%s|r - this character is on %s", arg, Config:ProfileName())
        ns:Print("  |cff808080any other character still on it falls back to Default at its next login|r")
        if ns.Options and ns.Options.Refresh then ns.Options:Refresh() end
        return
    end

    report()
    ns:Print("usage: /hui profile |cff808080[use <name> | new <name> | delete <name>]|r")
end
