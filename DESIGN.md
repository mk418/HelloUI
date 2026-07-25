# HelloUI — Design Document

A de-clutter layer for the stock World of Warcraft Classic Era interface.
Replaces DragonflightUI, which broke on patch 1.15.9 — but deliberately does
not replace what DragonflightUI *was*.

---

## Why this exists

DragonflightUI stopped loading cleanly on 1.15.9. Four errors on every login:
`hooksecurefunc('Target_Spellbar_AdjustPosition')` on a function that no longer
exists, `StanceBarLeft` gone, `PartyMemberFrame1` gone (party frames are pooled
now), and `RegisterEvent('MINIMAP_PING')` on an event that was removed. All four
are the same root cause HelloBuffCap ran into: 1.15.9 moved Era onto the shared
modern UI codebase.

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
- **Bar visibility** — turn a whole bar off. Bar 4 was off everywhere; bar 1 and
  the stance bar were off on one character. This is the feature that makes room
  for the class addons: they are all purely additive by design and will never
  hide Blizzard's bars themselves, so somebody has to, and this is the addon
  whose job it is. See *Sibling addon boundaries*.
- **Status bar text** — force the XP and reputation bar text to be permanently
  readable instead of mouseover-only. Note this is what `alwaysShowXP` /
  `alwaysShowRep` actually did: they set the text's draw layer to `OVERLAY`
  instead of `HIGHLIGHT`. The bars themselves were always visible.
- **Class-coloured player health bar** — `PlayerFrameHealthBar` recoloured to
  class, re-applied after Blizzard's health update resets it to green. This was
  the *only* unit frame setting in the entire profile.
- **Darkmode** — desaturate + tint pass over stock frame art. Defaults matching
  the old ones: desaturate on, tint `0.4, 0.4, 0.4`.
- **Minimap** — hide the calendar button, keep the minimap tucked flush into the
  top-right corner.
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
- **Minimap buttons.** HelloGear, HelloStock and HelloWorldBuffs each park a
  `Hello*MinimapButton` on the minimap. HelloUI adds none and touches none.
- **Profiles, import/export, layout presets.** One account-wide layout plus one
  character override is the whole requirement.

---

## File structure

```
HelloUI/
├── HelloUI.toc
├── Core.lua        -- namespace, saved variables, event dispatcher, slash
│                      commands, the out-of-combat apply queue
├── Config.lua      -- defaults, per-character override resolution
├── Buttons.lua     -- keybind / macro text alpha across every bar
├── Bars.lua        -- per-bar enable/disable, out of combat only
├── StatusBars.lua  -- XP / reputation text draw layer
├── Player.lua      -- class-coloured player health bar
├── Darkmode.lua    -- desaturate + tint pass over stock frame art
├── Minimap.lua     -- calendar button, corner tuck
├── Chat.lua        -- ChatFrame1 anchor + size
├── Friends.lua     -- friends-list class colour, <3 heart
└── Options.lua     -- canvas options panel
```

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
fatal. HelloGear, HelloStock and HelloWorldBuffs create
`Hello*MinimapButton` parented directly to `Minimap`, so anything that iterates
minimap children greys out three sibling icons — which is exactly what
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

- **Flavour detection.** `EditModeManagerFrame ~= nil` or
  `StatusTrackingBarManager ~= nil`. Feature-detect, don't map interface
  versions — Blizzard is rolling the modern backport across flavours and the
  build number tells you less than the frame does.
- **Button text.** `_G[buttonName .. 'HotKey']` and `_G[buttonName .. 'Name']`
  still exist and are still the right handles. Guard both with `if el then` —
  pooled and modern-template buttons don't all carry them.
- **Player health.** `PlayerFrameHealthBar:SetStatusBarColor(...)`, re-applied on
  health update. Blizzard resets it, so this needs a hook rather than a one-shot.
- **Status tracking.** Keep `StatusTrackingBarManager`. DragonflightUI hid it and
  built replacement XP and reputation bars; on a stock client the modern bar is
  already there and already does the job, so the feature reduces to a text draw
  layer change.
- **Calendar button.** Stock is `GameTimeFrame`. DragonflightUI's `hideCalendar`
  hides its own `CalendarButtonFrame`, so this one does need real code.
- **Removed event.** `MINIMAP_PING` no longer exists. Gate any
  `RegisterEvent` behind `C_EventUtils.IsEventValid` — and prefer that pattern
  generally, since it's what stopped this exact crash in the fork.
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

- **Darkmode is the only feature that isn't close to a direct port.**
  DragonflightUI's pass runs largely over its own replacement art
  (`SubMinimap.MinimapBorderSquare`, `btn.DFDeco`) mixed with Blizzard globals
  like `MinimapCompassTexture` and the zoom button textures. Against stock
  1.15.9 art it needs a fresh inventory of what to desaturate and tint. Start
  narrow — minimap ring, action bar backdrop, buff borders — and grow it.
- **Verify what Edit Mode already does before writing Buttons.lua and Bars.lua.**
  Retail Edit Mode exposes per-bar "Hide Bar Art" and visibility settings
  natively. If the 1.15.9 backport includes keybind/macro text toggles too, two
  of the nine features collapse to a note in the README telling you which
  checkbox to click. Check in-game first; this is the highest-value unknown in
  the document.
- **Re-express the `Drikk-MR` layout.** Hiding bar 1 and the stance bar is
  HelloUI's job and stays here — the class addons are additive by design and
  won't do it. Only the two re-anchors need re-expressing, and since their
  targets were DragonflightUI frames, Edit Mode is where that now belongs.
  Open question worth answering once: whether a per-character "bars off" set
  should be keyed on class or set by hand.
- **The minimap tuck may also be an Edit Mode concern** on a client where
  `MinimapCluster` is layout-managed. Confirm before fighting it.
- **Check the tuck against the sibling minimap buttons.** They're parented to
  `Minimap` so they travel with it, but they sit around the ring by angle — a
  flush-to-corner minimap may push the top and right ones off-screen. Three
  addons' buttons ride on this.
- **`hideCalendar` on one account only.** It's set on account `83602#1` and on
  `Drikk-MR`, but not on `MABK`'s Default profile. Treat as intended-everywhere;
  the inconsistency is drift, not preference.
