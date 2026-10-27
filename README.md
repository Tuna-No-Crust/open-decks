# Open Decks

DJ on a Steam Deck. Open Decks turns a handheld with a touchscreen between
its controls into a two-deck DJ rig: your rekordbox USB stick, jog wheels
and faders on the sticks, touch for the rest. It is a fork of
[Mixxx](https://mixxx.org) (GPL-2.0-or-later) with its own touch UI, a
gamepad controller backend and rekordbox-first library handling.

**Status: proof of concept.** It plays sets today on a Steam Deck and that
is the only supported device. Expect rough edges; see *What it is not*
and the open items below. Website: <https://www.makestupidstuff.com/opendecks/>.

## What it does

- Reads a **rekordbox USB export** (the classic `PIONEER/rekordbox/export.pdb`
  + `USBANLZ` analysis files): playlists, beatgrids, BPM, key, hot cues and
  memory cues come along when a track is loaded.
- **Mounts sticks itself, read-only.** Plug one in while the app runs; the
  Library refreshes on its own. The app never writes to a stick, so pulling
  it mid-set is as harmless as on a CDJ.
- **Controller**: the Deck's sticks are jog wheels (CDJ-style nudge / scrub /
  scratch), stick clicks play, bumpers cue, the trackpads play the FX pads.
  Any SDL game controller works (DualSense tested); the mapping is a normal
  Mixxx controller mapping (`res/controllers/Gamepad DJ.gamepad.xml` +
  `Gamepad-DJ-scripts.js`), editable without a rebuild.
- **Touch**: library browsing and drag-to-load, mixer (faders, EQ, filter,
  crossfader), hot cue pads, loops, sync / vinyl / key lock, FX XY pads,
  audio settings.
- Audio: main out and headphone cue on any devices PipeWire exposes,
  including class-compliant USB interfaces (Scarlett 4i4 tested: main on
  1-2, cue on 3-4).

## What it is not

- Not a library manager: nothing is written to the stick, no USB export, no
  track editing. Analysis happens in rekordbox.
- Legacy rekordbox export only. The encrypted `exportLibrary.db` (rekordbox
  7's "OneLibrary") is not read. rekordbox 7.2.11+ still writes the legacy
  export by default. No Serato, no Traktor.
- Steam Deck only for now. Android and iPhone are the next targets; the
  macOS build is a development stand-in, not a product.
- Not in any store, and no plans for one.

## Install on a Steam Deck

You need: a Steam Deck (SteamOS 3.x), headphones, a USB stick with a
rekordbox export, and optionally a USB-C audio interface. Everything below
happens once, in Desktop Mode.

1. **Download** `OpenDecks-x86_64.AppImage` from the
   [latest release](https://github.com/Tuna-No-Crust/open-decks/releases/latest)
   into a folder of your choice, e.g. `~/Applications/open-decks/`, and
   make it executable (right-click → Properties → Permissions → *Is
   executable*, or `chmod +x`).
2. **Add it to Steam**: Steam → *Games* → *Add a Non-Steam Game to My
   Library* → *Browse*, pick the AppImage, name it "Open Decks". Steam Input
   then owns the controller when the app runs, which is what you want.
3. **Controller layout**: in the game's *Controller Settings* pick the
   **"Gamepad with Joystick Trackpad"** template. The app takes the raw
   Steam Deck controller back from Steam at start so the trackpads reach the
   FX pads; the template keeps Steam from turning them into a mouse.
4. **Touch without a pointer** (recommended): in the same layout, *Edit
   Layout* → *Action Sets* → the cog next to "Default" → *Add Always-On
   Command* → *System* tab → **Touchscreen Native Support**. Without it
   Steam turns touches into a single mouse pointer; with it, two fingers
   work (both FX pads at once, pad + fader).
5. **Launch** from Game Mode or Desktop Mode. First start:
   - The app picks outputs by name: the Deck's speaker (or a USB interface
     with 4 outputs) as main and the headphone jack as cue. Change it in the
     ⋯ menu → *Settings* (device and channel pair per output, buffer size),
     then *Apply*. Aim for a buffer of 5–10 ms.
   - Plug the stick in. The Library tab lists it; tap it to parse the export
     (a few seconds for a few hundred tracks), tap a playlist, drag a track
     to the left or right edge to load it.
6. **Volume**: the Deck's volume buttons act on PipeWire's *default* sink,
   which Steam points at the newest device. If cue is quiet, raise the
   headphone sink once: Quick Access → Audio, or
   `pactl set-sink-volume <headphone sink> 100%`.

Settings live in `~/.open-decks/` (a Mixxx install on the same machine
keeps its own `~/.mixxx/`). Logs: `~/.open-decks/mixxx.log`.

### Other Linux

The AppImage runs on any x86_64 Linux with glibc 2.35+ (Ubuntu 22.04 and
newer). Controllers need hidraw access for SDL: install
`res/linux/mixxx-usb-uaccess.rules` into `/etc/udev/rules.d/` or run as a
user that can read `/dev/hidraw*`. Sticks are mounted through UDisks2; if
your session has no polkit agent, mount the stick yourself (`udisksctl
mount -b /dev/sdX1 -o ro`) and press *Refresh* in the Library.

## Controls (Steam Deck, default mapping)

| Control | Deck 1 (left) | Deck 2 (right) |
|---|---|---|
| Stick turn / click | jog / **play** | jog / **play** |
| Stick straight up/down (no modifier) | channel fader | channel fader |
| L1 / R1 | cue; tap while the stick holds the platter = set cue | same |
| A / B / Y | pick low / mid / high EQ band (both decks) | |
| L2 + stick | ↕ picked band (slam down = kill, up = neutral), ↔ filter | same |
| D-pad left / X | FX unit on/off | |
| Trackpad | FX XY pad deck 1 | FX XY pad deck 2 |
| Options + D-pad | ↑↓ browse the library, ←→ load to deck 1 / 2 | |
| Back (Create) | load to an empty, else a stopped deck | |
| L1 / R1 with the top bar focused | previous / next tab | |

Hot cues, loops, sync, vinyl mode, key lock, tempo, PFL, mixer and FX are
on the touchscreen. Every binding is in `Gamepad-DJ-scripts.js`; the jog
feel (seconds per turn, nudge strength, grab radius, filter) is in the
mapping's settings block.

## Building

Open Decks builds like Mixxx (see upstream's
[build instructions](https://github.com/mixxxdj/mixxx/wiki/Compiling-on-Linux))
with two extra CMake options: `-DQML=ON` (the touch UI) and `-DGAMEPAD=ON
-DSDL3_DIR=<path to SDL3's cmake folder>` (the gamepad backend; SDL3 ≥ 3.2,
joystick/HIDAPI parts are enough). `packaging/open-decks/` has the
Docker-based recipe that produces the Steam Deck AppImage.

The touch UI is QML under `res/qml/OpenDecks/`; a `--developer` build reads
it from the source tree and reloads files on save. `--classic-ui` starts
Mixxx's widget UI instead (diagnosis only).

## Licence and credits

Open Decks is free software under the GNU GPL, version 2 or later, like
Mixxx (`COPYING`). Built on Mixxx by the Mixxx developers. The handheld UI
uses IBM Plex (SIL Open Font License, `res/fonts/IBMPlex.LICENSE.txt`).
rekordbox is a trademark of AlphaTheta; this project is not affiliated with
it and reads the export format through the community's `rekordbox-metadata`
library. Built with Claude Code; the maintainer made the calls and played
every mapping on the Deck.
