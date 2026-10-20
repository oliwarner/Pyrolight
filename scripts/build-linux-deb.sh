#!/usr/bin/env bash

set -euo pipefail

fail()
{
  echo "$1" >&2
  exit 1
}

[ $# -eq 3 ] || fail "Usage: $0 <binary> <PyroWave-prefix> <output-dir>"

SOURCE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BINARY=$(readlink -f "$1")
PYROWAVE_PREFIX=$(readlink -f "$2")
VERSION=${VERSION:-${CI_VERSION:-$(<"$SOURCE_ROOT/app/version.txt")}}
OUTPUT_DIR=$3

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] || fail "Invalid package version: $VERSION"
[ "$(dpkg --print-architecture)" = arm64 ] || fail "Build this package on an arm64 runner"
[ -x "$BINARY" ] || fail "Missing executable: $BINARY"
[ -f "$PYROWAVE_PREFIX/lib/libpyrowave-shared.so.1" ] || fail "PyroWave library not found under $PYROWAVE_PREFIX"
[ -s "$PYROWAVE_PREFIX/share/licenses/pyrowave/LICENSE" ] || fail "PyroWave license not found under $PYROWAVE_PREFIX"

ELF_MACHINE=$(LC_ALL=C readelf -h "$BINARY" | sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')
[ "$ELF_MACHINE" = AArch64 ] || fail "Expected an AArch64 executable, got ${ELF_MACHINE:-unknown}"

mkdir -p "$OUTPUT_DIR" "$SOURCE_ROOT/build"
OUTPUT_DIR=$(readlink -f "$OUTPUT_DIR")
STAGE=$(mktemp -d "$SOURCE_ROOT/build/pyrolight-deb.XXXXXX")
SHLIBDEPS=$(mktemp -d "$SOURCE_ROOT/build/pyrolight-shlibdeps.XXXXXX")
trap 'rm -rf "$STAGE" "$SHLIBDEPS"' EXIT

mkdir -p "$STAGE/DEBIAN" "$STAGE/opt/pyrolight/bin" "$STAGE/opt/pyrolight/lib" \
         "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons/hicolor/scalable/apps" \
         "$STAGE/usr/share/metainfo" "$STAGE/usr/share/doc/pyrolight"
install -m 0755 "$BINARY" "$STAGE/opt/pyrolight/bin/pyrolight"
install -m 0644 "$PYROWAVE_PREFIX/lib/libpyrowave-shared.so.1" "$STAGE/opt/pyrolight/lib/"
install -m 0755 "$SOURCE_ROOT/app/deploy/linux/pyrolight-system-launcher.sh" "$STAGE/usr/bin/pyrolight"
install -m 0644 "$SOURCE_ROOT/app/deploy/linux/com.moonlight_stream.Moonlight.desktop" \
  "$STAGE/usr/share/applications/"
install -m 0644 "$SOURCE_ROOT/app/res/moonlight.svg" \
  "$STAGE/usr/share/icons/hicolor/scalable/apps/pyrolight.svg"
install -m 0644 "$SOURCE_ROOT/app/deploy/linux/com.moonlight_stream.Moonlight.appdata.xml" \
  "$STAGE/usr/share/metainfo/"
install -m 0644 "$SOURCE_ROOT/LICENSE" "$STAGE/usr/share/doc/pyrolight/copyright"
install -m 0644 "$PYROWAVE_PREFIX/share/licenses/pyrowave/LICENSE" \
  "$STAGE/usr/share/doc/pyrolight/PyroWave-LICENSE"

# Let dpkg derive versioned dependencies from the libraries on this Ubuntu runner.
mkdir -p "$SHLIBDEPS/debian"
printf 'Source: pyrolight\nSection: games\nPriority: optional\n\nPackage: pyrolight\nArchitecture: arm64\nDescription: Pyrolight\n' \
  > "$SHLIBDEPS/debian/control"
SHLIB_DEPENDS=$(cd "$SHLIBDEPS" && dpkg-shlibdeps -O --ignore-missing-info \
  -l"$PYROWAVE_PREFIX/lib" -e "$STAGE/opt/pyrolight/bin/pyrolight" \
  | sed -n 's/^shlibs:Depends=//p')
[ -n "$SHLIB_DEPENDS" ] || fail "Unable to determine shared-library dependencies"

cat > "$STAGE/DEBIAN/control" <<EOF
Package: pyrolight
Version: ${VERSION}-1
Section: games
Priority: optional
Architecture: arm64
Maintainer: Pyrolight contributors
Description: Game-streaming client with PyroWave support
 A Moonlight Qt fork for Pyroshine and other compatible hosts.
Depends: ${SHLIB_DEPENDS}, qml6-module-qtquick, qml6-module-qtquick-controls,
 qml6-module-qtquick-templates, qml6-module-qtquick-layouts,
 qml6-module-qtqml-workerscript, qml6-module-qtquick-window,
 qt6-qpa-plugins, qt6-wayland
Recommends: mesa-vulkan-drivers | vulkan-icd
Conflicts: moonlight-qt
EOF

"$SOURCE_ROOT/scripts/check-linux-icons.sh" "$STAGE"
dpkg-deb --build --root-owner-group "$STAGE" \
  "$OUTPUT_DIR/pyrolight_${VERSION}-1_arm64.deb"