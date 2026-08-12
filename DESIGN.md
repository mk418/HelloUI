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

One of those fifteen entries is not a change to Blizzard's UI at all — it is
DragonflightUI being told to stop reskinning the tradeskill window
(`changeTradeskill = false`), satisfied on a stock client by not writing the
code. Two more looked like that and were not: `gryphons = 'NONE'` and
`hideArt = true` were DFUI declining to draw art *of its own*, which is true
and beside the point, because Blizzard's gryphons and bar backdrop are right
there on a stock client. Reading the mechanism and losing sight of the intent
cost a real feature; it is implemented now. See *Current scope*.

And 1.15.9 brought Blizzard Edit Mode to Era. The layout engine DragonflightUI
reimplements — anchors, offsets, per-bar positioning, its own edit mode — now
ships in the client.

---

## Design philosophy

1. **Keep Blizzard's frames unless replacing one is the safer boundary.** No
   texture set, no replacement unit frames, no reparenting. The narrow exception
   is XP/reputation: changing Blizzard's status-manager geometry tainted the Game
   Menu, so two isolated addon-owned bars replace only that display. Masque is
   already installed and already owns button art.
2. **Delegate position to Edit Mode.** Every anchor / `x` / `y` / `anchorFrame`
   in the old profile is a job the client now does natively. Re-implementing it
   is how you end up with 3000-line action bar modules.
3. **Alpha, not Hide.** Blizzard's own update paths call `Show()` on their font
   strings, so hiding them starts a fight you re-lose on every action update.
   `SetAlpha(0)` survives untouched. This is the one trick DragonflightUI got
   exactly right and it's worth copying verbatim.
4. **No libraries.** Family rule: they're a future-patch breakage surface, and
   for an addon this size they buy nothing.
5. **Profiles, one per set of preferences.** This started as a shared DB plus a
   sparse per-character override list, on the evidence that 47 characters shared
   one arrangement and exactly one diverged. That was true of the profile being
   ported and false of how the addon gets used: alts you play differently want
   different settings, and an exception list makes you enumerate the exceptions.
   Settings now live in named profiles, each character picks one, and the Edit
   Mode layout follows the profile so the two cannot disagree.
6. **Nothing secure touched in combat.** Enabling, disabling or re-anchoring a
   bar happens out of combat or not at all.
7. **Own only what no sibling owns.** HelloUI is the only addon in the family
   that modifies frames it didn't create, which makes it the only one that can
   break the others. Where a sibling already covers something, it wins — see
   *Sibling addon boundaries*.

---

## Current scope

Twelve features. Four are switches; the other eight are simply what the addon does
— hiding the gryphons and bar backdrop, compact XP and reputation bars,
hiding the time-of-day dial, class-colouring the player health bar, yielding the
cast bar to a sibling that draws its own, the flat cast bar, and the matching flat
breath meter, plus fitting the stock auto-attack flash to its button. Those
started as settings because everything did, and a switch
implies a decision worth making: nobody installs this and then turns the
de-clutter off. They run whenever the addon is enabled, `/hui off` still hands
every one of them back, and their keys are deleted from saved variables on sight
so a stale `false` cannot read as a setting that broke. Three changes from the first
count: pinning the chat frame turned out to belong to Edit Mode, for the same
reason the minimap tuck did — both are placed by the layout now, which is Edit
Mode's own data rather than an anchor of ours (see *Out of scope*); hiding the main bar art
turned out to be real work rather than the no-op it first looked like; and the
bar *arrangement* turned out to matter as much as the de-clutter, which the
saved-profile method could never have revealed — AceDB records deviations, and
DragonflightUI's layout was its default.

- **Button text stripping** — keybind text and macro name to alpha 0 across
  bars 1–8, the stance bar and the pet bar. The single most-set value in the old
  profile: every bar, both flags, no exceptions.
- **Auto-attack flash bounds** — Era gives the normal action-button flash its
  atlas's native size and only a top-left anchor, so the red attack pulse is
  larger than the 36px button. HelloUI fits the stock flash to buttons on bars
  1–8, leaves the deliberately sized stance/pet flashes and non-stock skin art
  alone, and restores Blizzard's original geometry on `/hui off`.
- **Bar visibility** — turn a whole bar off. One bar was off everywhere; bar 1
  and the stance bar were off on one character. This is the feature that makes
  room for the class addons: they are all purely additive by design and will
  never hide Blizzard's bars themselves, so somebody has to, and this is the
  addon whose job it is. See *Sibling addon boundaries*.

  `barsOff` is **authoritative**: anything in it is hidden, anything not in it
  is shown. That reverses an earlier, more timid rule which would only ever
  turn a bar *off*, on the grounds that Blizzard's setting was not ours to
  overwrite. Reproducing DragonflightUI's base UI means deciding which bars are
  up, and a rule that can only hide cannot do that — it left bar 5 dark forever
  because the player's stored Blizzard setting happened to have it off. What
  made the old behaviour a bug was that it was silent and unasked-for; what
  makes this acceptable is that it is the documented job of the feature, every
  bar is individually switchable, and the pre-existing value is remembered in
  saved variables so `/hui off` hands it straight back.

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
- **Three Blizzard minimap bugs on Era, all in one 33-line file.** The tracking
  button is declared with no `parent` in `MinimapTracking_Simple.xml`, so it
  strands itself in the screen's top-left corner; `MinimapTrackingSimpleMixin`
  only shows it from `MINIMAP_UPDATE_TRACKING`, which fires when tracking
  *changes*, so a character logging in with tracking already active leaves it
  hidden indefinitely; and its ring is declared `64x64` where `LFGMinimapFrame`,
  `MiniMapMailBorder`, `MiniMapBattlefieldBorder` and `MiniMapWorldBorder` all
  declare the same `MiniMap-TrackingBorder` texture at `52x52` on the same
  `33x33` frame — so it drew 23% oversized and overflowed its own frame.
  (`64/52 = 1.2308`; measured off a screenshot by sub-pixel circle fit before
  the change at `1.227 ± 0.008`. It is not the client's only 64 declaration of
  that texture — `Blizzard_HelpPlate` has one — but it is the only 33×33 minimap
  button carrying one.) Matching the eye means copying its `TOPLEFT (1,-1)`
  inset too, not just the size: the ring art is not centred in its file, so a
  resize alone slides the ring 3.47 units off the icon. All three
  are invisible in the shipped client because only classes with an active
  tracking ability ever see the thing. HelloUI reparents it, supplies the
  initial visibility Blizzard never sets, and places it *polar*: the LFG eye's
  own offset from the map's centre, rotated 19° around that centre. Rotation is
  the point — the rim is a circle, so translating a button "straight down" from
  the eye cuts the chord and lands it 57 units out on a map whose rim is at 70,
  drawn on the map rather than on its edge. Neither of Blizzard's own declared
  offsets survives contact either: the vanilla one overlaps the eye and the
  non-vanilla one is the 57. The angle is a setting (`/hui tracking <deg>`)
  because the rim is shared with every other addon's minimap button.
  The size is matched by resizing the two *regions*, never by scaling the frame:
  `SetPoint` offsets live in the anchored frame's own coordinate space, so
  `SetScale(52/64)` would render that same 75-unit polar vector at 61 against a
  rim at 70 and put the button back on the map — correct-looking art, broken
  placement, and the existing radius assertions would not have caught it because
  they read the raw offsets. Blizzard divides its own cached offsets by
  `GetScale()` for exactly this reason in `MinimapClusterMixin:ResetFramePoints`.
  The target is read live off `LFGMinimapFrameBorder` and converted through both
  effective scales, so "match the eye" stays true if anything ever scales it.
  The 19° is the rim's own measured pitch, not a derivation: the twelve buttons
  on this minimap ride one circle (fit rms 0.30px) and the packed pairs sit a
  median 24.9 units apart, essentially touching. The first attempt used 30°,
  reasoned from the 33×33 *frames* — but the visible ring is only ~26.5 units, so
  frame-tangent still left a 15.7-unit hole. Art, not hit rects, is what a gap
  looks like.
- **Button borders — tried and removed.** Blizzard ships
  `ActionButtonTemplate`'s `NormalTexture` (`UI-Quickslot2`) at `alpha="0.5"`,
  because it was only ever meant to sit on the bar backdrop that draws the
  per-slot recesses; hide the bar art and the icons float on a half-transparent
  outline. Taking it to full alpha shipped for a while and was then removed after
  looking at it, which is the only thing that settles a look. Nothing writes that
  texture now, in either direction, so the buttons carry exactly Blizzard's own
  art at Blizzard's own alpha.
- **Main bar art** — hide the gryphons and the bar backdrop. Appearance rather
  than position, so this is HelloUI's job and not Edit Mode's; the
  delegate-to-Edit-Mode rule is about anchors. It drives the same two frames
  Blizzard's own `HideBarArt` drives (`MainMenuBar` and `MainActionBar.EndCaps`,
  via `MainActionBarMixin:UpdateEndCaps`) by hiding them directly, rather than
  through `OnSystemSettingChange` — which would write manager state in our taint
  context and persist into the player's saved layout. Takes the latency strip
  with it exactly as Blizzard's setting does; the micro menu and bag bar are
  children of `UIParent` and unaffected.
- **XP and reputation bars** — two addon-owned 454×10px bars match the action
  stack without writing geometry into `StatusTrackingBarManager`. The stock
  manager remains alive for Blizzard's bookkeeping and is made transparent;
  its containers are never resized, hidden, re-anchored or hooked. That avoids
  feeding addon-written dimensions back into UI panel positioning, which can
  taint the Game Menu's protected Logout/Exit callback.

  The XP bar reads `UnitXP`, `UnitXPMax` and `GetXPExhaustion`; only earned XP
  fills the bar. That fill is blue while rested XP is available and purple
  otherwise, while the rested amount remains available in its tooltip. The
  reputation bar reads the watched faction through
  `C_Reputation.GetWatchedFactionData`, with the legacy
  `GetWatchedFactionInfo` as a feature-detected fallback, and normalizes the
  value to the current standing's thresholds. Values and percentages are
  always printed on the addon-owned bars, so HelloUI no longer changes the
  player's `xpBarText` CVar. Max level is checked explicitly against the
  client's player-level cap rather than inferred solely from `UnitXPMax == 0`.
  When only one bar exists it occupies the bottom slot; with both present,
  reputation stacks immediately above XP. Their top edge is 24px above the
  screen and the action stack starts at 30px, leaving a 6px separation.
- **Class-coloured player health bar** — `PlayerFrameHealthBar` recoloured to
  class through a secure post-hook on `UnitFrameHealthBar_Update`. HelloUI does
  not write the shared `lockColor` field: Blizzard reads it as control flow in
  the same unit-frame update path that manages `TargetFrameToT`, so tainting it
  can break target-of-target visibility and positioning. This was the *only*
  unit frame setting in the entire profile.
- **Darkmode** — one switch: on desaturates and tints every texture on the
  allowlist `0.4, 0.4, 0.4`, off hands them all back. The old profile's per-area
  picks, its desaturate toggle and its tint colour are gone — nobody was going to
  tint the minimap but not the cast bar, and the grey is a constant in
  `Darkmode.lua` now. Two of the old six areas never made it either: `buffs`
  because 1.15.9 aura buttons are anonymous pooled frames whose only border is
  dispel-type colour (live state), and `ui` because it was already a no-op
  upstream — DragonflightUI's `UpdateUI` checked its flag and returned without
  touching a texture.
- **Minimap** — hide the time-of-day dial. Not a calendar: Era loads
  `GameTime_NoCalendar`, so `GameTimeFrame` here is the sun/moon indicator, with
  no click action at all. No positioning ships — see *Out of scope*.
- **The bar layout** — reproduces DragonflightUI's default arrangement: action
  bars stacked and centred above the custom status bars, with two 3-row flank
  blocks, full-size icons and 2px padding.

  This is not a contradiction of "delegate position to Edit Mode" — it is that
  rule taken seriously. Instead of fighting Edit Mode with `SetPoint` on frames
  it will silently re-anchor, HelloUI writes a real Edit Mode layout named
  `HelloUI` and lets Edit Mode apply it. Afterwards the addon is not involved:
  it is the player's layout, editable and persistent like any other. Existing
  layouts are never modified, so switching back is one dropdown.

  **Asked, never applied silently** — once per session, and only when the
  layout is not already active, so accepting retires the question permanently
  and declining costs one dismissal. Applying on a schedule would undo any bar
  the player had since dragged, which is the "addon owns your layout" behaviour
  the whole design is written against. Because Edit Mode saves that dragging
  into the layout, re-applying on demand *is* the reset — no separate restore
  path to get wrong.

  Layout is deliberately **not** in `ns.MODULES`. `ApplyAll` runs on every
  `PLAYER_ENTERING_WORLD` and every options change, and a listed module has its
  `Apply` called each time — which here would mean rewriting the layout
  constantly. The harness caught that as a real bug and now guards it.

  Bars are anchored to `UIParent` at explicit offsets, not chained bar-to-bar.
  Chaining was the first attempt and it overlapped on screen: an Edit Mode
  action bar frame is shorter than the buttons it contains, so a 2px gap from
  the frame's top edge lands inside the row above.

  The XP and reputation bars are not Edit Mode systems at all now. They are
  addon-owned frames anchored directly below the stack, while the untouched
  stock systems remain in the copied layout and are visually suppressed.

  Named after the profile: `Default` keeps the bare `HelloUI`, anything else
  gets `HelloUI - <profile>`. Changing profile changes layout with it —
  `Layout:FollowProfile`, called from `Config`'s profile writes. It **activates**
  an existing layout rather than re-applying it, because Edit Mode saves dragging
  into the layout and a rebuild would throw those adjustments away; only a
  profile with no layout yet gets one built. Gated on whether our layout was
  active *before* the switch, read before the profile changes, so "asked, never
  applied silently" survives: consent carries across a switch, it is not assumed
  by one. Always an `Account` layout, because a profile is
  shareable and a character is not — two characters on `Raiding` share its
  arrangement. A `Character`-typed layout left over from the old per-character
  mode is still found by name and refreshed in place, so the migration does not
  strand anyone with two. Blizzard caps layouts at 5 per type, so creation can
  genuinely fail and says so.
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
  draws a replacement. HelloWarrior, HelloMage, HelloDruid and HelloRogue can
  register their cluster through `HelloUIClassBarAPI`: while that cluster is
  visible, bars 1-3 are effective additions to `barsOff` without mutating the
  profile (Mage also adds bar 4), and an untouched cluster follows
  MainActionBar's bottom anchor. Hiding the cluster or disabling HelloUI hands
  the configured bars back.
  HelloHealer's `HelloHealerMainHeader1` is the corresponding runtime signal on
  supported healer classes: while it exists, the bottom-left bar 5 is an
  effective addition to `barsOff`. Its presence also selects the low chat
  anchor when the Edit Mode layout is built, using the space bar 5 vacates and
  keeping the healing grid clear on short screens. That geometry is saved as a
  separate `HelloUI - Healer` layout (with the profile name included when
  applicable), so the shared base layout remains valid on other classes. The
  named frame is used instead of `IsAddOnLoaded` so an inert HelloHealer install
  on another class changes nothing.
- **Recipe favourites** — Skillet-Classic and RecipeMaster are installed. The
  five saved favourites (Transmute: Arcanite, Dense Dynamite, Goblin Sapper
  Charge, Unstable Trigger, Solid Blasting Powder) are worth re-pinning by hand
  once, not worth an addon feature.
- **Nameplates** — TidyPlates_ThreatPlates is installed.
- **Range display** — RangeDisplay is installed, and HelloRangeDisplay exists.
- **XP and reputation tracking.** HelloLog owns the per-session numbers
  (`XP.lua`, `Rep.lua`, pure tracking, no frames). HelloUI only renders current
  progress bars; it stores no history and computes no session totals.
- **Minimap buttons.** Four siblings park a `Hello*MinimapButton` directly on
  the Minimap frame: HelloGear, HelloLog, HelloStock and HelloWorldBuffs.
  HelloUI adds none and touches none.
- **Chat frame size and position.** `ChatFrame1` inherits
  `EditModeChatFrameSystemTemplate` on 1.15.9, and Edit Mode's preset carries
  its anchor *and* its width and height. The bar layout therefore writes the
  chat position and a 250px height into the layout itself, lifting its bottom
  edge clear of both the bottom-left flank block and the left-aligned stance
  bar. With HelloHealer active, that flank block is suppressed and the layout
  instead uses a 56px bottom offset: HelloBuffCap's default 8px offset plus its
  40px HUD and an 8px gap. Its height drops by the same 40px, from 250 to 210,
  so the chat top remains at 266px and does not move back toward the healer
  grid. This keeps the buff-cap readout out of chat without trading it for the
  original overlap. The geometry lives in the dedicated healer layout rather
  than rewriting the profile's base layout. It preserves the preset's width.
  This is Edit Mode's own data written
  through `C_EditMode.SaveLayouts`, not a `SetPoint` or `SetHeight` made behind
  its back, so the result remains editable and persistent in Edit Mode.
- **Minimap position.** Stock 1.15.9 already anchors the minimap TOPRIGHT at
  offset 0,0 — both Edit Mode preset layouts say so and the XML agrees — so
  there is nothing to tuck. DragonflightUI's `+7` was compensating for dead
  margin in a 178px frame it created and re-parented the minimap into, and does
  not transfer. And `MinimapCluster` is an Edit Mode system: `SetPoint` is
  replaced by an override that writes manager state in the caller's taint
  context, the frame is `clampedToScreen` so a positive offset on a TOPRIGHT
  anchor cannot move it anyway, and any anchor set is reverted on layout save,
  spec change and every close of Edit Mode.

  Same caveat as the chat frame: the layout does carry a minimap entry, both an
  anchor and its `Size` setting (110%), for the same reason and by the same
  sanctioned route. "Out of scope" here means HelloUI never calls `SetPoint` on
  `MinimapCluster`, not that the arrangement ignores the minimap.
- **Import/export and layout presets.** Profiles exist now; shipping them
  between accounts, or curating preset arrangements, does not.

---

## File structure

```
HelloUI/
├── HelloUI.toc
├── .luacheckrc     -- lua51, the family's ignore list; run `luacheck .`
├── Core.lua        -- namespace, saved variables, guarded event dispatcher,
│                      per-site error containment, slash commands, the
│                      out-of-combat apply queue
├── Config.lua      -- defaults, profiles, the migration into them
├── Buttons.lua     -- keybind / macro text alpha across every bar
├── Bars.lua        -- the bar table; native proxy for 2-8, alpha for the
│                      rest; gryphons and backdrop
├── StatusBars.lua  -- addon-owned XP and watched-reputation bars
├── Player.lua      -- player health colour and safe target-of-target warning
├── Darkmode.lua    -- desaturate + tint over an explicit allowlist
├── Minimap.lua     -- time-of-day dial, the tracking button, the clock
├── CastBar.lua     -- yields Blizzard's cast bar to a sibling's, and flattens
│                      the one that remains
├── MirrorTimer.lua -- gives breath/fatigue/death timers the same flat style
├── Layout.lua      -- the DragonflightUI bar arrangement, as an Edit Mode layout
├── Options.lua     -- canvas options panel
└── Tests/
    └── test_boot.lua  -- offline harness: stubs the API, loads all twelve
                          files in TOC order, drives ADDON_LOADED through
                          PLAYER_ENTERING_WORLD, asserts observable end state
```

Run the harness from the addon root with `lua Tests/test_boot.lua`. It is the
only verification available without the game, so it checks end state — alpha
values, cvars, anchors, vertex colours — rather than whether a function was
called, and it is mutation-tested to confirm it fails when the code is wrong.

---

## Sibling addon boundaries

Every Hello addon in `~/code/mk418` was checked against these features. None
of them overlap: no sibling touches `HotKey`, `MainMenuBar`, `MultiBar`,
`StanceBar`, `PlayerFrame`, `MinimapCluster`, `GameTimeFrame`,
the XP/reputation APIs, or repositions `ChatFrame1`. So nothing here is dropped
in favour of a sibling — but three of them are close enough to demand rules,
because HelloUI is the only one of the family that modifies frames it doesn't
own.

**Darkmode allowlists Blizzard textures. It never sweeps.** Two reasons, both
fatal. HelloGear, HelloLog, HelloStock and HelloWorldBuffs all create
`Hello*MinimapButton` parented directly to `Minimap`, so anything that iterates
minimap children greys out four sibling icons — which is exactly what
DragonflightUI's `UpdateMinimapButton` did. And HelloWarrior and HelloTotems
both use `SetDesaturated` on their own buttons as *live state*: HelloWarrior for
its out-of-range tint, HelloTotems for empty-slot placeholder icons. A second
desaturation pass over those doesn't just look wrong, it corrupts a signal the
user reads mid-fight. Name the Blizzard textures to touch; touch nothing else.

The minimap area therefore covers Blizzard's own gold and stops there: the map's
ring and header, both zoom buttons, the four button rings that share
`MiniMap-TrackingBorder` (tracking, LFG, mail, battlefield), the minimise button
in the header, and the compass pair. **Tint bezels, never payloads** — a texture
belongs on the list only if its pixels are fixed for the session. `MiniMapTrackingIcon`
is `SetTexture`d from `GetTrackingTexture()` and the LFG eye is TexCoord-animated,
so both stay coloured inside grey rings, the same relationship an action button
has to its bar. And the honest limit: on a rim carrying a dozen third-party
buttons, Blizzard's art is a minority of the gold on screen. The rest belongs to
the addons that drew it, three of the four sibling buttons build their ring
anonymously, and greying them from here would mean the sweep this rule forbids.

**The cast bar yields to a sibling that draws its own — by frame, not by addon.**
`CastBar.lua` is the family's first executable cross-addon link, and it is
deliberately the mildest shape available. HelloUI's layout parks
`PlayerCastingBarFrame` in the strip HelloWarrior's cluster occupies, and moving
either is the hard version (an Edit Mode system, reverted on every close of Edit
Mode). So HelloWarrior draws its own bar at the top of its cluster and HelloUI
switches Blizzard's off through `CastingBarMixin:SetAndUpdateShowCastbar` — the
client's own call for "another bar is replacing this one", used by
`OverlayPlayerCastingBarMixin`. The test is `_G.HelloWarrior_CastBar` existing
and `HelloWarrior_Container` being shown, **not** `IsAddOnLoaded("HelloWarrior")`:
the addon is inert on non-Warriors, and a Priest with it installed must not lose
their cast bar. Two named globals, read-only, no reciprocation — HelloWarrior
does not know this file exists.

**The cast bar is restyled, not replaced.** Blizzard's Classic-style bar already
uses the same fill texture HelloWarrior's does (`CastingBarMixin:UpdateBarFillTexture`
sets `Interface\TargetingFrame\UI-StatusBar` on that path), so matching the family
look is the `hideBarArt` pattern: hide the 256x64 border and its flash, put a flat
colour behind the fill, move the spell name left. The countdown is the one added
thing, because this build has no `CastTimeText` at all — `UpdateCastTimeTextShown`
opens with `if not self.CastTimeText then return end` and the Classic template
declares none. Two things fight back and are handled differently. The colour is re-applied by
`UpdateBarFillTexture` on every cast, so it is re-asserted from a hook on the
instance. The border art is worse: a completed cast runs `Flash:Show()` and then
`FlashAnim`, an `<Alpha ... setToFinalAlpha="true">` group that drives the same
256x64 outline to full alpha and leaves it there — so `Hide()` loses to the Show
and `SetAlpha(0)` loses to the animation, and the outline flashed back for a
second on every finished cast. The regions are therefore **blanked**
(`SetTexture(nil)`), not hidden: Blizzard's Show, alpha and animation all still
run and all still paint nothing. Files are remembered so the art comes back.
And blanking alone still is not enough, because `CastingBarMixin:SetLook`
rebuilds the appearance wholesale — border texture, font object and text anchor —
and `PlayerFrame_DetachCastBar` calls it from
`EditModeCastBarSystemMixin:ApplySystemAnchor` on every Edit Mode layout update,
including the one at login that lands after our styling pass. So the style is
re-applied from a hook on `SetLook`. It is a *partial* undo, which is what made
it hard to see: justification and the countdown survive it, so the result read as
a styled bar whose border had inexplicably returned. Size and position stay Edit Mode's.

**The breath meter is restyled, not reimplemented.** Classic's breath, fatigue,
and death displays are the three interchangeable `MirrorTimer1`–`MirrorTimer3`
frames. `MirrorTimer_Show` takes the first hidden slot, so BREATH is not reliably
`MirrorTimer1`; all three receive the same treatment. Each already contains the
same 195×13 `Interface\TargetingFrame\UI-StatusBar` fill and 256×64 casting-bar
border as the player cast bar. `MirrorTimer.lua` blanks that border, puts the
stock label on the left in the small font, and adds the current `frame.value` on
the right after the stock `MirrorTimerFrame_OnUpdate` has refreshed it. The
client still owns `GetMirrorTimerProgress`, pause/stop events, fill, and type
colour — breath stays blue, fatigue yellow, death orange. `MirrorTimer1` uses a
fixed top-centre anchor at `y = -124`, low enough to clear the top button cluster,
and Blizzard's existing anchors continue to stack `MirrorTimer2` and
`MirrorTimer3` beneath it. `/hui off` restores the remembered texture, font,
label anchor, and frame anchor and hides only HelloUI's countdown.

**The options panel scrolls.** The Settings canvas is a fixed ~580 units tall
(UIParent is always 768, whatever the resolution) and this panel's left column
alone exceeds that — and the canvas does not clip, so the overflow drew straight
over the game. Everything is parented to a scroll child inside a
`UIPanelScrollFrameTemplate`, the same wrapper HelloHealer's settings panel uses.
The scroll child's height is measured from the lowest element on each refresh
rather than hard-coded, since the status line grows when the character has
overrides. A widget parented to the panel instead of the scroll child escapes
the scroll frame and floats over the game again, so the harness asserts the
panel has exactly one child.

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
| `bar4.activate` | `false` | superseded — the default is DragonflightUI's base set (1–5 on, 6–8 off) rather than this profile's deviations |
| `xp.alwaysShowXP`, `rep.alwaysShowRep` | `true` | StatusBars.lua |
| `player.classcolor` | `true` | Player.lua |
| `minimap.hideCalendar` | `true` | Minimap.lua |
| modules `Darkmode`, `Utility` | `true` (both default `false`) | Darkmode.lua; the `Utility` half was the friends list, since removed |
| module `Chat` | `true` (default `false`) | nothing to do — Edit Mode owns it |
| `bar1.gryphons` | `'NONE'` | Bars.lua |
| `bar1.hideArt` | `true` | Bars.lua |
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
- **Auto-attack flash.** `ActionButtonTemplate` declares `Flash` with the
  `UI-HUD-ActionBar-IconFrame-Flash` atlas, `useAtlasSize="true"`, and only a
  `TOPLEFT` anchor. `ActionButton.lua` toggles that region specifically for
  attack and auto-repeat actions. Constraining the stock atlas to all points of
  its 36px button removes the oversized pulse without suppressing the state
  indicator. `SmallActionButtonMixin` assigns stance/pet flashes its own size,
  so those buttons are intentionally outside this fix.
- **Alpha on button text needs no re-assertion at all.** Blizzard reaches those
  two font strings through `Show`, `Hide`, `SetText` and `SetVertexColor` only.
  A full-tree search finds no `SetAlpha` on an action button's `HotKey` or
  `Name` anywhere — the only hits belong to the raid pullout buttons and the
  commentator UI. So an alpha set once stays set, which is the real reason alpha
  beats `Hide` here rather than merely a way to dodge a fight.

  Corollary: do **not** hook `ActionBarActionButtonMixin.UpdateHotkeys` to
  re-apply. `Mixin()` copies function references onto each button as it is
  created, so hooking the mixin table afterwards reaches no existing button. It
  would look like it worked and do nothing.
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
  `PlayerFrame.HealthBar` also resolves. A secure post-hook recolours only that
  status bar after `UnitFrameHealthBar_Update`; `lockColor` stays untouched so
  Blizzard's shared unit-frame control flow never reads addon-written state.
- **Target of target.** Detection is read-only and requires two bad samples
  three seconds apart. Repairing `TargetFrameToT` and calling `C_UI.Reload()`
  are protected operations: they run only directly from a StaticPopup button's
  hardware click, never from a timer, `PLAYER_REGEN_ENABLED`, `ns:WhenSafe` or
  another post-reload continuation. Classic Era can retain its layout-local
  entry once, so a persisted stage changes the second dialog to an explicit
  “Finish repair” confirmation. That second click is intentional; removing it
  caused `ADDON_ACTION_BLOCKED` for both `Reload()` and `CancelLogout`.
- **Status tracking.** Keep `StatusTrackingBarManager` alive but transparent,
  and render XP/reputation in addon-owned frames. Never resize its containers,
  hook `UpdateBarVisuals`, call manager refresh methods, or modify its Edit Mode
  entries: Blizzard reaches the manager from UI panel positioning, so values it
  reads back can taint the Game Menu before its protected Logout/Exit callback.
- **Time-of-day dial, not a calendar.** Era loads `GameTime_NoCalendar`, so
  `GameTimeFrame` is a `Frame` (not a `Button`) showing `UI-TOD-Indicator`, with
  no `OnClick` and no `EnableMouse` anywhere — its tooltip script is unreachable.
  Safe to `Hide()`, and `ToggleMinimap` is the only thing in the tree that
  re-shows it, so hook that.
- **`ChatFrame1` is an Edit Mode system too.** It inherits
  `EditModeChatFrameSystemTemplate` (`FloatingChatFrame.xml:716`), and the
  preset layouts set `WidthHundreds`/`WidthTensAndOnes` and the matching height
  keys, so Edit Mode owns its size as well as its anchor. Easy to miss because
  the frame is not obviously "a UI system" the way the minimap is.
- **`GetLayouts` and `SaveLayouts` are asymmetric, and it is not guessable.**
  `C_EditMode.GetLayouts()` returns only the *saved* layouts, but `activeLayout`
  — and every index `SaveLayouts` cares about — counts the **preset** layouts
  first. So the list must be rebuilt as `[presets..., saved...]` before any
  index means anything, and that combined list is what `SaveLayouts` wants
  back. Getting this wrong silently activates a Blizzard preset instead of your
  layout — and it bites twice. The second time was `Layout:IsActive`, which
  compared a saved-only index against `activeLayout`, answered "not active" for
  a layout that plainly was, and re-asked the login question every single
  session. Both callers share one `combinedLayouts` helper now, because having
  the rebuild in one and not the other is the whole failure mode.
  Saving also does not *apply*: opening and immediately closing
  `EditModeManagerFrame` is what makes Edit Mode re-read. This sequence is
  lifted from LibEditModeOverride (plusmouse, MIT), the known-working
  implementation, reimplemented rather than vendored under the no-libraries
  rule.
- **Writing an Edit Mode layout.** `C_EditMode.GetLayouts` / `SaveLayouts` /
  `SetActiveLayout` all exist on Era. Two shape traps:
  `settings` is an **array of `{setting, value}` pairs**, not the map form the
  preset files use, and `anchorInfo.relativeTo` is a frame **name string**.
  Base the systems array on `EditModePresetLayoutManager:GetCopyOfPresetLayouts()`
  rather than hand-building it, so every system you don't care about carries
  Blizzard's own correct entry. Set `isInDefaultPosition = false` on anything
  you move, or Edit Mode treats the system as untouched and re-slams it to the
  preset anchor. Icon size and padding are stored pre-conversion:
  `display = raw * stepSize + minValue`, so 80% is raw 3 and 2px padding raw 0.
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
  the out-of-combat apply queue in Core.lua is for. Layout activation stops at
  `C_EditMode.SaveLayouts` / `C_EditMode.SetActiveLayout`; never synthesize a
  `ShowUIPanel` / `HideUIPanel` Edit Mode refresh from addon code. The profile
  selector uses addon-owned buttons instead of `UIDropDownMenuTemplate`, so it
  never writes into the shared `DropDownList1` pool. Popup definitions add only
  `HELLOUI_*` keys to `StaticPopupDialogs`; they never reassign that Blizzard-
  owned global binding, which the Game Menu and QUIT dispatcher both read on
  their protected callback paths. Each of those older mechanisms can propagate
  addon taint into GameMenuFrame's protected callbacks.

---

## Boot sequence

1. `ADDON_LOADED` — saved variables, defaults, resolve the per-character
   override against the account layout.
2. `PLAYER_LOGIN` — install hooks (button update, player health, cast bar,
   mirror timers), register the options panel.
3. `PLAYER_ENTERING_WORLD` — first full apply: button text, custom status bars,
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
