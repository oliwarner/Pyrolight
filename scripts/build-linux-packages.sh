#!/bin/bash
# Build the Pyrolight .deb, .rpm and Arch packages from an AppDir: the
# extracted release AppImage (squashfs-root) or build/deploy-release. The
# packages install that payload in /opt/pyrolight; see
# app/deploy/linux/nfpm.yaml and docs/LINUX_DISPLAY.md.
#
# Usage: scripts/build-linux-packages.sh <AppDir> <output-dir>
# Set VERSION or CI_VERSION to override the version in app/version.txt.
# Requires nfpm (see .github/workflows/build-appimage.yml for the pinned version).

set -euo pipefail

fail()
{
  echo "$1" >&2
  exit 1
}

[ $# -eq 2 ] || fail "Usage: $0 <AppDir> <output-dir>"
SOURCE_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=${VERSION:-${CI_VERSION:-$(<"$SOURCE_ROOT/app/version.txt")}}
command -v nfpm >/dev/null 2>&1 || fail "Unable to find 'nfpm' in your PATH!"

APPDIR=$(readlink -f "$1")
mkdir -p "$2"
OUTPUT=$(readlink -f "$2")
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

[ -x "$APPDIR/AppRun" ] && [ -x "$APPDIR/usr/bin/pyrolight" ] || fail "$APPDIR is not a Pyrolight AppDir"
ELF_MACHINE=$(LC_ALL=C readelf -h "$APPDIR/usr/bin/pyrolight" | sed -n 's/^[[:space:]]*Machine:[[:space:]]*//p')
case "$ELF_MACHINE" in
  "Advanced Micro Devices X86-64") NFPM_ARCH=amd64 ;;
  AArch64) NFPM_ARCH=arm64 ;;
  *) fail "Unsupported AppDir architecture: ${ELF_MACHINE:-unknown}" ;;
esac

echo Staging packages from $APPDIR
mkdir -p "$STAGE/opt" "$STAGE/usr/bin" "$STAGE/usr/share/applications" \
         "$STAGE/usr/share/icons/hicolor/scalable/apps" "$STAGE/usr/share/metainfo" "$STAGE/licenses"
cp -a "$APPDIR" "$STAGE/opt/pyrolight"
# AppImage directories are private (0700) because each user mounts their own;
# the system-wide copy must be readable by everyone and writable by no one else.
chmod -R u+rwX,go+rX,go-w "$STAGE/opt/pyrolight"
install -m 0755 "$SOURCE_ROOT/app/deploy/linux/pyrolight-launcher.sh" "$STAGE/usr/bin/pyrolight"
# The AppImage's copy carries AppImage-only keys.
grep -v '^X-AppImage-' "$APPDIR/com.moonlight_stream.Moonlight.desktop" \
  > "$STAGE/usr/share/applications/com.moonlight_stream.Moonlight.desktop"
cp "$APPDIR/usr/share/icons/hicolor/scalable/apps/pyrolight.svg" "$STAGE/usr/share/icons/hicolor/scalable/apps/"
cp "$APPDIR/usr/share/metainfo/com.moonlight_stream.Moonlight.appdata.xml" "$STAGE/usr/share/metainfo/"
cp "$APPDIR"/usr/share/licenses/pyrolight/*-LICENSE "$STAGE/licenses/"
[ -s "$STAGE/licenses/Pyrolight-LICENSE" ] && [ -s "$STAGE/licenses/PyroWave-LICENSE" ] || \
  fail "The AppDir is missing the Pyrolight or PyroWave license"

"$SOURCE_ROOT/scripts/check-linux-icons.sh" "$STAGE" || fail "Icon check failed!"

cd "$STAGE"
for packager in deb rpm archlinux; do
  VERSION=$VERSION NFPM_ARCH=$NFPM_ARCH nfpm package --config "$SOURCE_ROOT/app/deploy/linux/nfpm.yaml" \
    --packager "$packager" --target "$OUTPUT/" || fail "nfpm $packager failed!"
done

echo Packages built in $OUTPUT
