#!/usr/bin/env bash
# Inside open-decks-appimage: configure, build and package the Linux x86_64
# AppImage (Steam Deck). Mirrors CI's "AppImage Linux x86_64" job, plus our
# gamepad backend (SDL3 from /opt/sdl3). Output: /work/build-appimage/*.AppImage
set -eo pipefail

# The release dependency bundle CI uses (tools/appimage_buildenv.sh with
# BUILDENV_RELEASE set). Read from the source so it tracks the branch.
SCRIPT=/work/src/tools/appimage_buildenv.sh
pick() { grep -m1 -E "^\s+: \"\\\$\{$1:=" "$SCRIPT" | sed -E 's/.*:=([^}]*)\}.*/\1/'; }
export VCPKG_TARGET_TRIPLET=$(pick VCPKG_TARGET_TRIPLET)
BUILDENV_BRANCH=$(pick BUILDENV_BRANCH)
export BUILDENV_NAME=$(pick BUILDENV_NAME)
export BUILDENV_SHA256=$(pick BUILDENV_SHA256)
export BUILDENV_URL="https://downloads.mixxx.org/dependencies/${BUILDENV_BRANCH}/Linux/${BUILDENV_NAME}.zip"
export MIXXX_VCPKG_ROOT="${BUILDENV_BASEPATH}/${BUILDENV_NAME}"
export CMAKE_PREFIX_PATH="${MIXXX_VCPKG_ROOT}/installed/${VCPKG_TARGET_TRIPLET}"
echo "deps: $BUILDENV_NAME ($VCPKG_TARGET_TRIPLET)"

B=/work/build-appimage
cmake -B "$B" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DCMAKE_TOOLCHAIN_FILE="$MIXXX_VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
  -DVCPKG_TARGET_TRIPLET="$VCPKG_TARGET_TRIPLET" \
  -DQT6=ON -DQML=ON -DMIXXX_APPIMAGE=ON -DINSTALL_USER_UDEV_RULES=OFF \
  -DCMAKE_CXX_FLAGS_RELWITHDEBINFO="-O2 -DNDEBUG" \
  -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib \
  -DCMAKE_EXE_LINKER_FLAGS="-Wl,--allow-shlib-undefined" \
  -DBUILD_TESTING=OFF -DBUILD_BENCH=OFF \
  -DGAMEPAD=ON -DSDL3_DIR=/opt/sdl3/lib/cmake/SDL3 \
  /work/src
cmake --build "$B" --parallel "${JOBS:-6}"
cd "$B"
cpack -G AppImage
ls -la "$B"/*.AppImage
