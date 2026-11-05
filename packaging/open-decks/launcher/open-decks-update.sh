#!/bin/bash
# Open Decks updater, run by open-decks.sh (beside it) before every launch (never while
# the app runs, so an update can't land mid-set). Asks GitHub for the latest
# release of the public repo and, when its AppImage differs from the
# installed one, downloads it, checks it against the sha256 GitHub lists for
# the asset, and swaps it in. The previous AppImage stays as
# open-decks.AppImage.prev (roll back: move it over open-decks.AppImage and
# create DEV_BUILD so the next launch doesn't update again).
#
# Skipped when:
#   - DEV_BUILD exists next to the AppImage (a development build is newer
#     than any release and must not be replaced; delete it to follow
#     releases again)
#   - OPEN_DECKS_NO_UPDATE=1
#   - GitHub doesn't answer within a few seconds (offline at a gig)
# Always exits 0: a failed update must never stop the app from starting.
#
# On an update, files that would hide the new release's own copies are moved
# aside: a res/ tree beside the launcher (open-decks.sh prefers it to the
# QML inside the AppImage) and gamepad mapping copies in the settings
# folders (Mixxx prefers them to the built-in one).
#
# Overrides for testing: OPEN_DECKS_DIR, OPEN_DECKS_API (the releases/latest
# URL), OPEN_DECKS_ASSET (asset name).

DIR="${OPEN_DECKS_DIR:-$(cd "$(dirname "$(readlink -f "$0")")" && pwd)}"
API="${OPEN_DECKS_API:-https://api.github.com/repos/Tuna-No-Crust/open-decks/releases/latest}"
ASSET="${OPEN_DECKS_ASSET:-OpenDecks-x86_64.AppImage}"
APP="$DIR/open-decks.AppImage"
LOG="$DIR/update.log"

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }
sha256() { { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -d' ' -f1; }

[ "${OPEN_DECKS_NO_UPDATE:-0}" = 1 ] && exit 0
[ -f "$DIR/DEV_BUILD" ] && exit 0
command -v curl >/dev/null || exit 0

JSON=$(curl -fsSL --connect-timeout 3 --max-time 6 \
  -H 'Accept: application/vnd.github+json' "$API" 2>/dev/null) || exit 0

# tag, download URL and sha256 of the asset, one per line
INFO=$(printf '%s' "$JSON" | python3 -c '
import json, sys
r = json.load(sys.stdin)
for a in r.get("assets", []):
    if a.get("name") == sys.argv[1]:
        print(r.get("tag_name", ""))
        print(a.get("browser_download_url", ""))
        print((a.get("digest") or "").removeprefix("sha256:"))
        break
' "$ASSET" 2>/dev/null)
{ read -r TAG; read -r URL; read -r SUM; } <<< "$INFO"
[ -n "$TAG" ] && [ -n "$URL" ] && [ -n "$SUM" ] || { log "no $ASSET with a digest in the latest release"; exit 0; }

# VERSION caches the tag of the installed AppImage, so the 80 MB file is
# hashed only when a release appears that we haven't checked yet.
[ "$(cat "$DIR/VERSION" 2>/dev/null)" = "$TAG" ] && exit 0
if [ -f "$APP" ] && [ "$(sha256 "$APP")" = "$SUM" ]; then
  echo "$TAG" > "$DIR/VERSION"
  exit 0
fi

log "updating to $TAG"
# Something to look at while 80 MB come down: Game Mode shows zenity
# windows like any other; without zenity the wait is just silent.
PROGRESS=
if command -v zenity >/dev/null; then
  # Its input ends (and --auto-close closes it) when this script exits; the
  # feeder's stderr is closed so it can't keep the caller's terminal open.
  zenity --progress --pulsate --no-cancel --auto-close --title="Open Decks" \
    --text="Updating Open Decks to $TAG…" \
    < <(while kill -0 $$ 2>/dev/null; do sleep 1; done 2>/dev/null) >/dev/null 2>&1 &
  PROGRESS=$!
fi
done_progress() { [ -n "$PROGRESS" ] && kill "$PROGRESS" 2>/dev/null; }

NEW="$APP.download"
rm -f "$NEW"
# Give up on a stalled download (under 10 kB/s for 30 s) rather than hang
# the launch; the next launch tries again.
if ! curl -fsSL --connect-timeout 5 --speed-limit 10000 --speed-time 30 -o "$NEW" "$URL"; then
  log "download failed: $URL"; rm -f "$NEW"; done_progress; exit 0
fi
GOT=$(sha256 "$NEW")
if [ "$GOT" != "$SUM" ]; then
  log "checksum mismatch: got $GOT, expected $SUM"; rm -f "$NEW"; done_progress; exit 0
fi
chmod +x "$NEW"
[ -f "$APP" ] && mv -f "$APP" "$APP.prev"
mv -f "$NEW" "$APP"
echo "$TAG" > "$DIR/VERSION"

STAMP=$(date +%Y%m%d-%H%M%S)
if [ -d "$DIR/res" ]; then
  mv "$DIR/res" "$DIR/res.pushed-$STAMP" && log "moved pushed res/ to res.pushed-$STAMP"
fi
for d in "$HOME/.open-decks/controllers" "$HOME/.mixxx/controllers"; do
  for f in "Gamepad DJ.gamepad.xml" "Gamepad-DJ-scripts.js"; do
    [ -f "$d/$f" ] && mv "$d/$f" "$d/$f.pushed-$STAMP" && log "moved $d/$f aside"
  done
done
log "updated to $TAG"
done_progress
exit 0
