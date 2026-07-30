# HelloUI

De-clutters the stock World of Warcraft Classic Era interface. No art overhaul
or reimplemented layout engine — 1.15.9 brought Blizzard Edit Mode to Era, so
every stock-frame position it sets is written into an Edit Mode layout rather
than anchored behind the client's back. The exception is a pair of compact,
addon-owned XP/reputation bars, used specifically to avoid mutating Blizzard's
taint-sensitive status manager.

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
- **Draws its own XP and watched-reputation bars** at 454×10px, matching the
  action stack instead of stretching Blizzard's 1024px bars. Values and
  percentages stay visible, rested XP extends behind the XP fill, and a lone
  bar compacts into the bottom slot. XP disappears explicitly at the player
  level cap, even on clients where `UnitXPMax()` remains nonzero there.
- **Class-colours the player health bar.**
- **Detects a detached target-of-target frame** after login and offers a
  user-confirmed repair. It never changes the protected frame or reloads from a
  timer. Classic Era can retain the stale saved entry for one reload; when it
  does, HelloUI presents a labelled second confirmation instead of attempting
  blocked protected work automatically.
- **A flat cast bar** — Blizzard's border art off, the spell name on the left and
  a countdown on the right, which the client itself has no region for. And when a
  sibling addon draws its own cast bar (HelloWarrior puts one at the top of its
  cluster, in the same strip), Blizzard's is switched off through the client's own
  setting for exactly that case, so the two never draw through each other.
- **A matching flat breath meter** — the same borderless 195×13 shape, label on
  the left, and tenths-of-a-second countdown on the right. It restyles all three
  interchangeable Blizzard mirror-timer slots, so breath still gets the look when
  fatigue or another timer is already active. Blizzard continues to own the timing,
  fill texture, and type colours. The stack uses HelloUI's lower top-centre
  position so it stays below the top button cluster.
- **Darkmode** — one switch. Desaturates and tints Blizzard's own frame art:
  unit frames, the minimap and its buttons, the action bar backdrop and the cast
  bars. Never a sibling addon's icons, and never anything that uses desaturation
  as a signal.
- **Puts the tracking button back on the minimap.** On Classic Era Blizzard
  declares it with no parent at all, so it strands itself in the top-left
  corner of the screen next to your player frame.
- **Keeps the minimap clock in front of rim icons** without moving it from
  Blizzard's original position.
- **Hides the minimap's time-of-day dial** (the sun/moon icon — on Classic Era
  it has no click action at all).
- **Builds DragonflightUI's bar layout** as a real Edit Mode layout named
  `HelloUI` — full-size bars stacked and centred 6px above the two status rows,
  with the equally sized stance buttons left-aligned above them — and switches
  to it once, on first login.
  The layout also covers the cast bar, the raised 250px-tall chat frame, the
  micro menu, the bags and the minimap's size — everything that would otherwise
  collide with the arrangement. The addon-owned XP/reputation bars sit below
  that layout. Your own layouts are never touched; switch back in
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

Seven of those are simply what the addon is, and have no switch: the gryphons and
bar backdrop, the compact XP/reputation bars, the time-of-day dial, the
class-coloured health bar, both cast bar behaviours, and the matching breath
meter. `/hui off` still hands all of them back.
Everything else in the panel is a checkbox.

## What it deliberately doesn't do

Party and raid frames belong to HelloHealer, the character panel and paperdoll to
HelloGear, per-session XP and reputation numbers to HelloLog, stance and totem
and ability bars to HelloWarrior / HelloTotems / HelloHealer, nameplates to
ThreatPlates, range to HelloRangeDisplay, and action button art to Masque.
HelloUI is the only addon in the family that modifies frames it did not create,
which makes it the only one that can break the others — so where something else
already covers a thing, that wins.

It does not position frames behind Edit Mode's back. Stock 1.15.9 already
anchors the minimap flush to the top right, and both `MinimapCluster` and
`ChatFrame1` are Edit Mode systems that revert direct changes. The HelloUI
layout therefore carries the chat frame's raised position and 250px height;
drag and resize it in Edit Mode afterward if you prefer something else.

## Commands

```
/hui                  open the settings panel   (or /helloui)
/hui on | off         master switch
/hui apply            re-apply everything
/hui status           what each feature found on this client
/hui reset            this profile's settings back to defaults
/hui profile          which profile this character uses, and what else exists
/hui profile use <name>
                      switch this character to another profile
/hui profile new <name>
                      branch a copy off the current one and switch to it
/hui profile delete <name>
/hui layout           build the bar layout - or reset it back after you have
                      dragged things around
/hui layout status    is it there, is it active, which profile
```

## Profiles

Every setting belongs to a **profile**, and each character picks which profile it
uses. Fresh installs get one called `Default` and every character on it, which is
the old behaviour — change something and it changes everywhere.

When that stops being what you want, `/hui profile new Raiding` branches a copy
off the one you are on and moves this character to it. Edit away; the characters
still on `Default` are untouched. The dropdown in the options panel does the same
thing.

The **bar layout follows the profile**, so this is one decision rather than two:
`Default` uses the Edit Mode layout named `HelloUI`, and a profile called
`Raiding` uses `HelloUI - Raiding`. Switching profile switches layout with it,
and a brand new profile gets its layout built there and then — but only if you
were already using HelloUI's layout, and switching to a profile that already has
one never rebuilds it, so anything you dragged stays put. Blizzard caps layouts at five per type, which
in practice caps how many profiles can each have their own arrangement.

The case this exists for: a warrior running HelloWarrior wants Blizzard's bar 1
and stance bar gone, because HelloWarrior binds its own ability grid to `1`–`7`
and packs stance buttons into its header. Everyone else keeps them.

Upgrading from a version before profiles: your account settings become `Default`,
and any character that had overrides gets a profile named after itself, seeded
with them. That is also what its Edit Mode layout was already called, so nothing
moves underneath it.

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
