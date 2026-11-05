#!/bin/bash
# Open Decks launcher for Steam on the Steam Deck. Lives next to
# open-decks.AppImage and open-decks-update.sh (install.sh puts all three in
# ~/Applications/open-decks/); the "Open Decks" non-Steam shortcut runs it.
# Updates the AppImage from the latest GitHub release before starting, then
# runs it with settings in ~/.open-decks. A res/ folder beside it (a
# development push) overrides the QML inside the AppImage.
#
# Why launch through Steam even in Desktop Mode: Steam Input then applies the
# app's own controller layout ("Gamepad with Joystick Trackpad", set in
# configset_controller_neptune.vdf) instead of the desktop layout, whose right
# trackpad is a mouse. Steam hides the raw "Steam Deck Controller" from games
# it launches (SDL_GAMECONTROLLER_IGNORE_DEVICES=28de:1205) and offers its
# virtual Xbox pad instead; that pad has no trackpads, and the FX XY pads are
# played from the trackpads, so take the raw controller back and ignore the
# virtual pad (Valve 28de:11ff) so the sticks aren't read twice.
export SDL_GAMECONTROLLER_IGNORE_DEVICES="0x28de/0x11ff"
unset SDL_GAMECONTROLLER_IGNORE_DEVICES_EXCEPT
export SDL_JOYSTICK_HIDAPI_STEAMDECK=1
DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LOG="$DIR/steam-run.log"
# Swap in a newer release before starting (see open-decks-update.sh). Before
# RES below: an update moves a pushed res/ tree aside.
[ -x "$DIR/open-decks-update.sh" ] && "$DIR/open-decks-update.sh"
RES=()
# --developer: Mixxx then reloads QML files when they change on disk.
[ -f "$DIR/res/qml/main.qml" ] && RES=(--developer --resource-path "$DIR/res/")

# Desktop Mode: maximise once the UI window is up (upstream's --full-screen is
# ignored by the QML app, and the touch UI has no way out of fullscreen).
# Game Mode's gamescope fullscreens it on its own, and has no plasmashell.
if pgrep -u "$USER" -x plasmashell >/dev/null; then
  (
    for i in $(seq 1 90); do
      grep -q 'QmlWaveformDisplay ready' "$LOG" 2>/dev/null && break
      sleep 2
    done
    for i in $(seq 1 10); do
      sleep 6
      W=$(xdotool search --class mixxx 2>/dev/null | tail -1)
      [ -n "$W" ] && xdotool windowactivate --sync "$W" \
        && xdotool windowstate --add MAXIMIZED_VERT "$W" \
        && xdotool windowstate --add MAXIMIZED_HORZ "$W" && break
    done
  ) >/dev/null 2>&1 &
fi

exec "$DIR/open-decks.AppImage" "${RES[@]}" > "$LOG" 2>&1
