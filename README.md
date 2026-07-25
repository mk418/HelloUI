# HelloUI

De-clutters the stock World of Warcraft Classic Era interface. No art overhaul,
no replacement frames, no reimplemented layout engine — 1.15.9 brought Blizzard
Edit Mode to Era, so position is Edit Mode's job and this addon stays out of it.

Replaces DragonflightUI, which broke on 1.15.9. Its scope came from reading that
addon's saved profile across 47 characters: AceDB only writes non-default
values, so the saved file *was* the list of what was actually wanted, and it came
to about fifteen entries — every one of which removes something or makes some
text permanently readable. See `DESIGN.md` for the evidence and the reasoning.

## What it does

- **Hides keybind and macro text** on every action button — bars 1–8, stance and
  pet. There is no Blizzard setting for this; it is the one feature here that is
  genuinely unavailable natively.
- **Owns which bars are up.** The default is DragonflightUI's base set — bars
  1–5 shown, 6–8 hidden, stance and pet shown. Bars 2–8 go through Blizzard's
  own per-bar setting; bar 1, stance and pet are made invisible and
  non-interactive instead, because Blizzard offers no toggle for those three and
  hiding bar 1's *frame* would drag bars 2–8 down with it. Whatever your bars
  were set to before is remembered, and `/hui off` hands it back.
- **Hides the gryphons and the main bar backdrop** — the same two frames
  Blizzard's Edit Mode "Hide Bar Art" drives. The latency strip goes with them,
  as it does under Blizzard's own setting; the micro menu and bags stay.
- **Solid borders on every button.** Blizzard ships the button border at half
  alpha because it was meant to sit on the bar backdrop; with the backdrop gone
  that reads as no border at all. This takes it to full alpha — Blizzard's own
  texture, just actually visible.
- **Keeps the XP and reputation bar numbers on screen** instead of
  mouseover-only. This is Blizzard's `xpBarText` setting, and it covers both
  bars together.
- **Class-colours the player health bar.**
- **Darkmode** — desaturates and tints Blizzard's frame art across unit frames,
  the minimap, action bar art and cast bars.
- **Hides the minimap's time-of-day dial** (the sun/moon icon — on Classic Era
  it has no click action at all).
- **Class-colours the friends list**, and shows a heart next to friends whose
  note contains `<3`.
- **Builds DragonflightUI's bar layout** as a real Edit Mode layout named
  `HelloUI` — bars stacked and centred, 80% icons, 2px padding — and switches to
  it once, on first login. Your own layouts are never touched; switch back in
  Edit Mode any time.

  Because Edit Mode saves your dragging into the layout itself, **`/hui layout`
  is also the reset** — run it again and the bars go back to the shipped
  arrangement.

  It is **asked, never applied silently** — once per session, and only when the
  HelloUI layout is not already active, so saying yes retires the question.
  "Never" on the prompt stops it for good.

  Everyone shares one account-wide layout by default. Opting a single character
  out is a **per-character** choice: tick *...but give THIS character its own*
  (or `/hui layout char`) on that character only. Blizzard allows five layouts
  of each kind.

Defaults reproduce the layout that was already in use, so a fresh install should
look like the thing it replaced rather than a blank slate.

## What it deliberately doesn't do

Party and raid frames belong to HelloHealer, the character panel and paperdoll to
HelloGear, per-session XP and reputation numbers to HelloLog, stance and totem
and ability bars to HelloWarrior / HelloTotems / HelloHealer, nameplates to
ThreatPlates, range to HelloRangeDisplay, and action button art to Masque.
HelloUI is the only addon in the family that modifies frames it did not create,
which makes it the only one that can break the others — so where something else
already covers a thing, that wins.

It also ships no positioning of any kind. Stock 1.15.9 already anchors the
minimap flush to the top right, and both `MinimapCluster` and `ChatFrame1` are
Edit Mode systems that revert whatever an addon sets — Edit Mode even owns the
chat frame's width and height. Drag and resize them there.

## Commands

```
/hui                  open the settings panel   (or /helloui)
/hui on | off         master switch
/hui apply            re-apply everything
/hui status           what each feature found on this client
/hui reset            account settings back to defaults
/hui char             show this character's overrides
/hui char clear       drop them
/hui char barsoff bar1 stance
                      toggle bars off for THIS character only
/hui layout           build the bar layout - or reset it back after you have
                      dragged things around
/hui layout char      this character gets its own layout (character override)
/hui layout account   this character follows the shared one again
/hui layout status    is it there, is it active, which mode
```

## Per-character overrides

47 characters shared one layout and exactly one diverged, so this is an
exception list rather than a profile manager. Account settings apply everywhere;
a character only differs where you have explicitly overridden a key.

The case it exists for: a warrior running HelloWarrior wants Blizzard's bar 1 and
stance bar gone, because HelloWarrior binds its own ability grid to `1`–`7` and
packs stance buttons into its header. Everyone else keeps them.

```
/hui char barsoff bar1 stance
```

## Requirements

Classic Era 1.15.9 or later. No libraries — family rule: they're a future-patch
breakage surface, and for an addon this size they buy nothing.

## Development

```
luacheck .              lint (config in .luacheckrc)
lua Tests/test_boot.lua  offline harness
```

The harness stubs the 1.15.9 API, loads every file in TOC order, drives
`ADDON_LOADED` through `PLAYER_ENTERING_WORLD`, and asserts observable end state
— alpha values, cvars, anchors, vertex colours — rather than whether a function
was called.

## Licence

MIT.
