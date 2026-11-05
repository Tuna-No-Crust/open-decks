#!/bin/bash
# Installs Open Decks for Steam into ~/Applications/open-decks/: the
# launcher (open-decks.sh, the file to add to Steam), the updater it runs
# before every start, and the latest release's AppImage. Run it again any
# time to repair an install; it never touches settings (~/.open-decks).
#
#   curl -fsSL https://raw.githubusercontent.com/Tuna-No-Crust/open-decks/main/packaging/open-decks/launcher/install.sh | bash
set -euo pipefail
DIR="${OPEN_DECKS_DIR:-$HOME/Applications/open-decks}"
SRC="${OPEN_DECKS_SRC:-https://raw.githubusercontent.com/Tuna-No-Crust/open-decks/main/packaging/open-decks/launcher}"

mkdir -p "$DIR"
for f in open-decks.sh open-decks-update.sh; do
  curl -fsSL -o "$DIR/$f.new" "$SRC/$f"
  chmod +x "$DIR/$f.new"
  mv -f "$DIR/$f.new" "$DIR/$f"
done

# An AppImage installed by hand under the release name becomes the
# launcher's open-decks.AppImage; the updater then only replaces it when
# the release differs.
[ ! -f "$DIR/open-decks.AppImage" ] && [ -f "$DIR/OpenDecks-x86_64.AppImage" ] \
  && mv "$DIR/OpenDecks-x86_64.AppImage" "$DIR/open-decks.AppImage"

echo "Downloading the latest release (about 85 MB)…"
"$DIR/open-decks-update.sh"
if [ ! -x "$DIR/open-decks.AppImage" ]; then
  echo "The download didn't finish; see $DIR/update.log. Run this again to retry." >&2
  exit 1
fi
echo "Installed: $(cat "$DIR/VERSION" 2>/dev/null || echo "?") in $DIR"
echo "Add $DIR/open-decks.sh to Steam (Add a Non-Steam Game, file type: All Files)."
