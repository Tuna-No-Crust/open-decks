# Steam Deck AppImage

A Docker recipe for the Linux x86_64 AppImage, mirroring upstream Mixxx's
"AppImage Linux x86_64" CI job (Ubuntu 22.04, CMake 4.2, appimagetool
1.9.1) plus SDL3 built static for the gamepad backend. Works on an Apple
silicon Mac with Docker Desktop's Rosetta emulation (slow, hours for a cold
build) or on any x86_64 Linux with Docker.

```bash
docker build --platform linux/amd64 -f packaging/open-decks/Dockerfile.appimage -t open-decks-appimage packaging/open-decks
docker volume create open-decks-linux
docker run --rm --platform linux/amd64 --user 0 -v open-decks-linux:/work open-decks-appimage chown 1000:1000 /work
docker run --rm --platform linux/amd64 -v open-decks-linux:/work -v "$PWD:/work/src:ro" \
  -v "$PWD/packaging/open-decks/build-appimage.sh:/usr/local/bin/build-appimage.sh:ro" \
  -e JOBS=6 open-decks-appimage build-appimage.sh
docker run --rm --platform linux/amd64 -v open-decks-linux:/work -v "$PWD/dist:/dist" open-decks-appimage \
  bash -c 'cp "$(ls -t /work/build-appimage/*.AppImage | head -1)" /dist/OpenDecks-x86_64.AppImage'
```

Run from the repository root. The volume keeps the downloaded dependency
bundle, the build tree and ccache, so later builds take minutes. The
dependency bundle is the one upstream's `tools/appimage_buildenv.sh` names,
downloaded from downloads.mixxx.org.

## Steam artwork

`steam-art/` holds covers for the non-Steam shortcut: copy them into
`~/.steam/steam/userdata/<your id>/config/grid/` named after the shortcut's
app id (`<appid>p.png` portrait, `<appid>.png` wide, `<appid>_hero.png`,
`<appid>_logo.png`, `<appid>_icon.png`). Steam shows the id in its logs
(`console-linux.txt`, "AppId"), or use Decky's SteamGridDB plugin to set
them by hand.
