# HelloUI — Design Document

A de-clutter layer for the stock World of Warcraft Classic Era interface.
Replaces DragonflightUI, which broke on patch 1.15.9 — but deliberately does
not replace what DragonflightUI *was*.

---

## Why this exists

DragonflightUI stopped loading cleanly on 1.15.9. Four errors on every login:
`hooksecurefunc('Target_Spellbar_AdjustPosition')` on a function that no longer
exists, `StanceBarLeft` gone, `PartyMemberFrame1` gone (party frames are pooled
now), and `RegisterEvent('MINIMAP_PING')` rejected outright — the client's own
words were `Attempt to register unknown event "MINIMAP_PING"`. The event itself
still exists and still carries a documented payload; what changed is that
Blizzard's minimap now reaches it through `RegisterEventCallback` instead, and
plain `RegisterEvent` no longer accepts it. All four failures are the same root
cause HelloBuffCap ran into: 1.15.9 moved Era onto the shared modern UI
codebase.

The more interesting reason is what the saved profile said. AceDB only writes
values that differ from defaults, so `DragonflightUI.lua` in each account's
SavedVariables *is* the complete list of what was actually wanted. Across two
accounts and 47 characters, that list is about fifteen entries — and every one
of them either removes something or makes some text permanently visible. No unit
frame was ever repositioned. Nothing in Tooltip, Buffs, Flyout or Bossframe was
ever set. A 72 MB retail-art overhaul was being run as a small behaviour layer.

Three of those fifteen entries are not even changes to Blizzard's UI — they are
DragonflightUI being told to stop adding its own art (`gryphons = 'NONE'`,
`hideArt = true`, `changeTradeskill = false`). On a stock client those are
satisfied by not writing the code in the first place.

And 1.15.9 brought Blizzard Edit Mode to Era. The layout engine DragonflightUI
reimplements — anchors, offsets, per-bar positioning, its own edit mode — now
ships in the client.

---

## Design philosophy

1. **Keep Blizzard's frames.** Change their appearance, never their identity. No
   texture set, no replacement unit frames, no reparenting. Masque is already
   installed and already owns button art.
2. **Delegate position to Edit Mode.** Every anchor / `x` / `y` / `anchorFrame`
   in the old profile is a job the client now does natively. Re-implementing it
   is how you end up with 3000-line action bar modules.
3. **Alpha, not Hide.** Blizzard's own update paths call `Show()` on their font
   strings, so hiding them starts a fight you re-lose on every action update.
   `SetAlpha(0)` survives untouched. This is the one trick DragonflightUI got
   exactly right and it's worth copying verbatim.
4. **No libraries.** Family rule: they're a future-patch breakage surface, and
   for an addon this size they buy nothing.
5. **One layout, account-wide.** 47 characters, one profile, one deliberate
   per-character override. That's the data model — a shared DB plus a
   per-character override, not a profile manager.
6. **Nothing secure touched in combat.** Enabling, disabling or re-anchoring a
   bar happens out of combat or not at all.
7. **Own only what no sibling owns.** HelloUI is the only addon in the family
   that modifies frames it didn't create, which makes it the only one that can
   break the others. Where a sibling already covers something, it wins — see
   *Sibling addon boundaries*.

---

## Current scope

Nine features, each independently toggleable, because the source profile is
effectively nine independent switches.

- **Button text stripping** — keybind text and macro name to alpha 0 across
  bars 1–8, the stance bar and the pet bar. The single most-set value in the old
  profile: every bar, both flags, no exceptions.
- **Bar visibility** — turn a whole bar off. One bar was off everywhere; bar 1
  and the stance bar were off on one character. This is the feature that makes
  room for the class addons: they are all purely additive by design and will
  never hide Blizzard's bars themselves, so somebody has to, and this is the
  addon whose job it is. See *Sibling addon boundaries*.

  Two mechanisms, because Blizzard only supplies one. Bars 2–8 have a native
  settings proxy (`PROXY_SHOW_ACTIONBAR_2`…`_8`) and driving it is exactly what
  Blizzard's own checkbox does. Bar 1, the stance bar and the pet bar have no
  native toggle at all, and hiding bar 1's *frame* is forbidden:
  `IsNormalActionBarState()` is literally `return MainActionBar:IsShown()` and
  every multibar is gated on it, so hiding it drags bars 2–8 down with it —
  precisely the case this feature exists to serve. Those three are made
  invisible and non-interactive instead.

  Mind the numbering. DragonflightUI bound its `bar4` to `MultiBarLeft`, which
  the game calls bar 5. HelloUI follows Blizzard, so the same physical bar is
  `bar5` here and the labels match the game's own options panel.
- **Status bar text** — make the XP and reputation bar numbers permanently
  readable instead of mouseover-only. This is one setting, not the profile's
  two, and it is a single CVar write: Blizzard's own
  `StatusTrackingBarMixin:ShouldBarTextBeDisplayed` is
  `GetCVarBool("xpBarText") or self.textLocked or manager:IsTextLocked()`, and
  the two `textLocked` terms are the mouseover machinery — set on enter, cleared
  on leave — so neither can be held. Both bars share that predicate, so there is
  one switch behind them and splitting it would be a lie.
- **Class-coloured player health bar** — `PlayerFrameHealthBar` recoloured to
  class. No hook required: `UnitFrameHealthBar_Update` guards its colour write
  with `if not statusbar.lockColor`, so setting `lockColor` makes Blizzard stop
  resetting it. This was the *only* unit frame setting in the entire profile.
- **Darkmode** — desaturate + tint pass over stock frame art, desaturate on and
  tint `0.4, 0.4, 0.4` as before, but over four areas rather than the old six.
  `buffs` is gone because there is no stock target — 1.15.9 aura buttons are
  anonymous pooled frames and their only border is dispel-type colour, i.e. live
  state — and `ui` is gone because it was already a no-op upstream:
  DragonflightUI's `UpdateUI` checked its flag and returned without touching a
  texture.
- **Minimap** — hide the time-of-day dial. Not a calendar: Era loads
  `GameTime_NoCalendar`, so `GameTimeFrame` here is the sun/moon indicator, with
  no click action at all. No positioning ships — see *Out of scope*.
- **Chat** — pin `ChatFrame1` to a fixed anchor and size on login.
- **Friends list class colour** — plus the heart icon for friends whose note
  contains `<3`, ported as-is because it's twenty lines and it's charming.
- **Options panel** — canvas panel, same shape as the other Hello addons.

## Out of scope

- **The Dragonflight texture set.** It's the bulk of DragonflightUI's 72 MB and
  nothing in the profile depends on it.
- **Unit frame layout and restyling**, beyond the player health bar colour.
  Untouched across 47 characters — no target, focus, party, raid or pet frame
  setting was ever changed.
- **Tooltips, buffs, flyouts, boss frames.** Same evidence: never configured.
- **Tradeskill reskin.** Explicitly disabled (`changeTradeskill = false`).
- **Party and raid frames.** HelloHealer owns these — `BlizzardFrames.lua`
  suppresses `CompactRaidFrameContainer`, `CompactRaidFrameManager`,
  `PartyFrame`, `CompactPartyFrame` and the legacy `PartyMemberFrame1..4`, with
  combat-safe alpha fallback, an idempotent `OnShow` hook and a re-hide pass on
  roster changes. It is more careful than anything worth rewriting here.
- **Character panel and paperdoll.** HelloGear owns these (`CharacterPanel.lua`,
  `Paperdoll.lua`), and CharacterStatsClassic is installed on top.
- **Stance bars, totem bars, healer grids, ability bars.** HelloWarrior,
  HelloTotems and HelloHealer own these. HelloUI hides Blizzard's; it never
  draws a replacement.
- **Recipe favourites** — Skillet-Classic and RecipeMaster are installed. The
  five saved favourites (Transmute: Arcanite, Dense Dynamite, Goblin Sapper
  Charge, Unstable Trigger, Solid Blasting Powder) are worth re-pinning by hand
  once, not worth an addon feature.
- **Nameplates** — TidyPlates_ThreatPlates is installed.
- **Range display** — RangeDisplay is installed, and HelloRangeDisplay exists.
- **XP and reputation tracking.** HelloLog owns the per-session numbers
  (`XP.lua`, `Rep.lua`, pure tracking, no frames). HelloUI only changes whether
  Blizzard's existing bar text is legible.
- **Minimap buttons.** Four siblings park a `Hello*MinimapButton` directly on
  the Minimap frame: HelloGear, HelloLog, HelloStock and HelloWorldBuffs.
  HelloUI adds none and touches none.
- **Minimap position.** Stock 1.15.9 already anchors the minimap TOPRIGHT at
  offset 0,0 — both Edit Mode preset layouts say so and the XML agrees — so
  there is nothing to tuck. DragonflightUI's `+7` was compensating for dead
  margin in a 178px frame it created and re-parented the minimap into, and does
  not transfer. And `MinimapCluster` is an Edit Mode system: `SetPoint` is
  replaced by an override that writes manager state in the caller's taint
  context, the frame is `clampedToScreen` so a positive offset on a TOPRIGHT
  anchor cannot move it anyway, and any anchor set is reverted on layout save,
  spec change and every close of Edit Mode. Drag it in Edit Mode.
- **Profiles, import/export, layout presets.** One account-wide layout plus one
  character override is the whole requirement.

---

## File structure

```
HelloUI/
├── HelloUI.toc
├── .luacheckrc     -- lua51, the family's ignore list; run `luacheck .`
├── Core.lua        -- namespace, saved variables, guarded event dispatcher,
│                      per-site error containment, slash commands, the
│                      out-of-combat apply queue
├── Config.lua      -- defaults, per-character override resolution
├── Buttons.lua     -- keybind / macro text alpha across every bar
├── Bars.lua        -- the bar table; native proxy for 2-8, alpha for the rest
├── StatusBars.lua  -- the xpBarText cvar
├── Player.lua      -- class-coloured player health bar via lockColor
├── Darkmode.lua    -- desaturate + tint over an explicit allowlist
├── Minimap.lua     -- time-of-day dial
├── Chat.lua        -- ChatFrame1 anchor + size, and `/hui chat save`
├── Friends.lua     -- friends-list class colour, <3 heart
├── Options.lua     -- canvas options panel
└── Tests/
    └── test_boot.lua  -- offline harness: stubs the API, loads all eleven
                          files in TOC order, drives ADDON_LOADED through
                          PLAYER_ENTERING_WORLD, asserts observable end state
```

Run the harness from the addon root with `lua Tests/test_boot.lua`. It is the
only verification available without the game, so it checks end state — alpha
values, cvars, anchors, vertex colours — rather than whether a function was
called, and it is mutation-tested to confirm it fails when the code is wrong.

---

## Sibling addon boundaries

Every Hello addon in `~/code/mk418` was checked against the nine features. None
of them overlap: no sibling touches `HotKey`, `MainMenuBar`, `MultiBar`,
`StanceBar`, `PlayerFrame`, `MinimapCluster`, `GameTimeFrame`,
`StatusTrackingBarManager`, or repositions `ChatFrame1`. So nothing here is
dropped in favour of a sibling — but three of them are close enough to demand
rules, because HelloUI is the only one of the family that modifies frames it
doesn't own.

**Darkmode allowlists Blizzard textures. It never sweeps.** Two reasons, both
fatal. HelloGear, HelloLog, HelloStock and HelloWorldBuffs all create
`Hello*MinimapButton` parented directly to `Minimap`, so anything that iterates
minimap children greys out four sibling icons — which is exactly what
DragonflightUI's `UpdateMinimapButton` did. And HelloWarrior and HelloTotems
both use `SetDesaturated` on their own buttons as *live state*: HelloWarrior for
its out-of-range tint, HelloTotems for empty-slot placeholder icons. A second
desaturation pass over those doesn't just look wrong, it corrupts a signal the
user reads mid-fight. Name the Blizzard textures to touch; touch nothing else.

**Button text stripping enumerates Blizzard's bars by name.** Never a global
button sweep, and never "blank every FontString on every button". HelloWarrior
paints its own compact hotkey label onto its buttons as `btn._hwKeyLabel` (a
`NumberFontNormalSmallGray` FontString, not a global `<name>HotKey`), so the
`_G[name .. 'HotKey']` approach is safe as written — but only because it's
name-based. Keep it that way.

**Never earn a place in HelloHealer's conflict list.** `BlizzardFrames.lua`
carries `CONFLICTING_UIS = { "DragonflightUI", "ElvUI" }` and a
`DetectedConflict()` that warns the user when one is loaded. That list is the
family's canonical registry of UIs that break the healer grid, and it exists
because full-UI overhauls fight frame suppression. HelloUI staying off party and
raid frames entirely is what keeps it off that list.

**Slash command.** `/helloui` and `/hui`. The family has taken every short form
worth having — `/hbc /hg /hh /hl /hrd /hs /ht /hw /hwb` — and `/hu` and `/hui`
are the survivors.

---

## What the DragonflightUI profile actually said

The full deviation set, both accounts. Read straight out of
`WTF/Account/<acct>/SavedVariables/DragonflightUI.lua`.

| Setting | Value | Becomes |
| --- | --- | --- |
| `bar1`–`bar8`, `stance`: `hideKeybind`, `hideMacro` | `true` | Buttons.lua |
| `bar4.activate` | `false` | Bars.lua |
| `xp.alwaysShowXP`, `rep.alwaysShowRep` | `true` | StatusBars.lua |
| `player.classcolor` | `true` | Player.lua |
| `minimap.hideCalendar` | `true` | Minimap.lua |
| modules `Darkmode`, `Chat`, `Utility` | `true` (all default `false`) | Darkmode.lua, Chat.lua, Friends.lua |
| `bar1.gryphons` | `'NONE'` | nothing to do — DFUI's own art |
| `bar1.hideArt` | `true` | nothing to do — DFUI's own decoration |
| `UI.first.changeTradeskill` | `false` | nothing to do — out of scope |
| `CharacterStatsPanel.collapsed.attributes` | `true` | out of scope |
| `RecipeFavorite.favorite` | 5 recipes | out of scope |

Two caveats on reading that file:

- `minimap.x = 7` is **not** a preference. The era-1159 fork's one-time
  `minimapTuckV1` migration wrote it, along with a TOPRIGHT anchor, to sit the
  visible ring flush against the screen edge (the ring art is 156px inside a
  178px container, so +7 leaves 4px of bleed). The *outcome* is worth keeping;
  the number is an implementation detail of someone else's art.
- The `Drikk - Mirage Raceway` profile (`Drikk-MR`) is the one real per-character
  divergence: bar 1 and the stance bar off, `bar1.stateDriver = 'DEFAULT'`,
  bar 2 anchored to `DragonflightUIRepBar`, bar 5 to
  `DragonflightUIActionbarFrame3`, player castbar at `y = 395`, vehicle-leave
  button moved.

  That character is a Warrior, and it is not a layout experiment — it is a
  HelloWarrior accommodation. `HelloWarriorCharDB` has `role = "dps"` and binds
  its ability grid to `1`–`7` and `SHIFT-1`–`SHIFT-7`: the default action bar
  keys. So Blizzard's bar 1 is redundant *and* its keybinds have been taken over
  by HelloWarrior's override bindings, the stance bar is redundant because
  HelloWarrior packs stance buttons into its header, and bars 2 and 5 were
  re-anchored to close the resulting gap.

  This generalises. Every character running a class addon wants the same
  treatment, so "bars off, per character" is a designed feature rather than a
  one-off — the anchor *targets* are what can't be ported, not the intent.

---

## API notes for 1.15.9

Everything below was read out of Blizzard's own shipping UI source for this
exact build — `Gethe/wow-ui-source` branch `classic_era`, whose `version.txt`
is `1.15.9.68808`, matching `.build.info` for `wow_classic_era`. Where the
source and an assumption disagreed, the source won.

- **Flavour detection.** `EditModeManagerFrame ~= nil` or
  `StatusTrackingBarManager ~= nil`. Feature-detect, don't map interface
  versions — Blizzard is rolling the modern backport across flavours and the
  build number tells you less than the frame does.
- **Button text.** Prefer the object fields `button.HotKey` and `button.Name`.
  Both globals do also resolve: `$parentName` is a direct child of the button,
  and `$parentHotKey` lives inside an unnamed `TextOverlayContainer` but still
  reaches the global namespace because `$parent` resolves past unnamed ancestors
  to the nearest named one — Blizzard relies on that themselves, and the working
  fork dereferences `_G[name .. 'Count']` out of that same container unguarded.
  The object fields are preferred anyway because Blizzard installs them
  deliberately (`ActionButtonTextOverlayContainerMixin:OnLoad`) and they don't
  depend on naming semantics.
- **No native text toggle.** A full-tree search for a keybind- or macro-text
  setting comes back empty. Blizzard's Action Bars panel offers per-bar
  visibility, Lock Action Bars and cooldown numbers; Edit Mode offers
  Orientation, NumRows, NumIcons, IconSize, IconPadding, VisibleSetting,
  HideBarArt, HideBarScrolling and AlwaysShowButtons. So that feature is real
  work, and it is the one place the "check Blizzard first" instinct came back
  negative.
- **Bar visibility is native for 2–8 only.** `PROXY_SHOW_ACTIONBAR_2`…`_8`, via
  `Settings.SetValue`, which is what Blizzard's own checkbox drives. `MainBar`
  has no `VisibleSetting` in either Edit Mode preset map, and neither do the
  stance, pet or possess bars.
- **Never `Hide()` `MainActionBar`.** `IsNormalActionBarState()` is
  `return MainActionBar:IsShown()`, and `UpdateMultiActionBar` gates every
  multibar on it, so the next update takes bars 2–8 down too.
  `MainActionBar.visibility` stays nil forever — it is only ever assigned from a
  `VisibleSetting` the main bar doesn't have — so `IsShown()` reports the real
  state and there is no override to hide behind.
- **`RegisterStateDriver(bar, "visibility", "hide")` is expensive.** It works and
  self-heals every 0.2s, but each evaluation runs `HideOverride` →
  `UpdateVisibility` → `UpdateActionBarLayout`, and for a bottom-anchored bar
  that ends in an unconditional `UIParent_ManageFramePositions()`. A permanent
  driver runs that pass five times a second forever.
- **Player health.** `PlayerFrameHealthBar` is still a named global and
  `PlayerFrame.HealthBar` also resolves. No hook needed:
  `UnitFrameHealthBar_Update` guards its colour write with
  `if not statusbar.lockColor`, on both the connected and disconnected paths, so
  `lockColor = true` is Blizzard handing the colour over.
- **Status tracking.** Keep `StatusTrackingBarManager` — DragonflightUI hid it
  and built replacements, which is the opposite of what's wanted. Text
  visibility is `GetCVarBool("xpBarText")`; the per-bar and per-manager
  `textLocked` flags are the mouseover path and are cleared on mouse-out.
- **Time-of-day dial, not a calendar.** Era loads `GameTime_NoCalendar`, so
  `GameTimeFrame` is a `Frame` (not a `Button`) showing `UI-TOD-Indicator`, with
  no `OnClick` and no `EnableMouse` anywhere — its tooltip script is unreachable.
  Safe to `Hide()`, and `ToggleMinimap` is the only thing in the tree that
  re-shows it, so hook that.
- **`MinimapCluster` is an Edit Mode system.** `EditModeSystemMixin:OnSystemLoad`
  replaces `SetPoint`, `ClearAllPoints`, `SetScale`, `SetShown` and `Hide` with
  overrides, the frame is `clampedToScreen`, and `ApplySystemAnchor` reverts
  whatever you set. Don't fight it.
- **Callback-only events.** `RegisterEvent` and "the event exists" have come
  apart. Gate on `C_EventUtils.IsEventValid`, wrap the `RegisterEvent` itself in
  `pcall`, and fall back to `RegisterEventCallback` when
  `C_EventUtils.IsCallbackEvent` says so — callbacks receive the owner as the
  first argument, so strip it.
- **Party frames are pooled.** `PartyFrame.PartyMemberFramePool`, enumerated via
  `EnumerateActive()`. Never index `PartyMemberFrame1..4`. Not needed in current
  scope, but it's the trap that killed DragonflightUI's party module.
- **Deprecated aura API.** `UnitBuff` / `UnitDebuff` / `UnitAura` are
  deprecation shims in `Blizzard_Deprecated` behind the
  `loadDeprecationFallbacks` CVar. Not needed here; noted so it stays not-needed.
- **Taint.** Bar enable/disable and any re-anchor of a secure frame must be
  `InCombatLockdown()`-gated and replayed on `PLAYER_REGEN_ENABLED`. This is what
  the out-of-combat apply queue in Core.lua is for.

---

## Boot sequence

1. `ADDON_LOADED` — saved variables, defaults, resolve the per-character
   override against the account layout.
2. `PLAYER_LOGIN` — install hooks (button update, player health, friends list),
   register the options panel.
3. `PLAYER_ENTERING_WORLD` — first full apply: button text, status bar text,
   darkmode, minimap, chat. Bar enable/disable goes through the apply queue.
4. `PLAYER_REGEN_ENABLED` — drain the apply queue.

---

## Known issues / TODO

Nothing here has been run in the game yet. The offline harness covers the logic
and the end state against a stubbed API, but it cannot tell you whether a frame
looks right, so everything below wants one login to settle.

- **Darkmode's allowlist is the thinnest part.** Fourteen named Blizzard
  textures across four areas, all verified to exist in the 1.15.9 source, but
  "exists" is not "reads well when greyed". Expect to add and remove entries by
  eye. Two known interactions: Leatrix_Plus also re-textures
  `PlayerFrameTexture` under its player-frame options and blanks
  `MinimapCluster.BorderTop`, so that is the first place to look if a tint
  stops applying; and whether `SetTexture` clears the desaturation flag is not
  answerable from the Lua source, which is why the pass re-runs on the events
  that drive Blizzard's re-textures.
- **The `Drikk-MR` re-anchors are not ported.** Hiding bar 1 and the stance bar
  is HelloUI's job and is implemented. The two bar re-anchors pointed at
  DragonflightUI frames that no longer exist, and re-anchoring a bar is Edit
  Mode's job now. Open question worth answering once: whether a per-character
  "bars off" set should be keyed on class or just set by hand — right now it is
  by hand, via `/hui char barsoff bar1 stance`.
- **Bar 2 can be switched back on by the game.** On `ACTIONBAR_SHOW_BOTTOMLEFT`
  Blizzard force-sets `PROXY_SHOW_ACTIONBAR_2` to true. Nothing in the current
  defaults touches bar 2, so this is a latent issue rather than a live one, but
  it is the one bar whose native toggle is not durable.
- **Invisible is not gone.** Bar 1, stance and pet are alpha-0 rather than
  hidden, for the `IsNormalActionBarState` reason above, so they still occupy
  their slot in Blizzard's layout. In practice Edit Mode owns position and the
  class addons draw wherever they like, so this has cost nothing — but it is a
  deliberate compromise, not an oversight.
- **`hideCalendar` on one account only.** It was set on account `83602#1` and on
  `Drikk-MR`, but not on `MABK`'s Default profile. Treated as
  intended-everywhere; the inconsistency reads as drift, not preference.
- **Sibling minimap buttons are fine, but tight.** All four are children of
  `Minimap` so they travel with it and with Edit Mode's size scale — no work
  needed. Worth knowing that a 31px button placed by angle at r=75 reaches about
  90px from the map centre against roughly 88px of stock margin to the right
  screen edge, so a button dragged to due-right already hangs slightly
  off-screen at stock. All four stored defaults are lower-left and safe.
