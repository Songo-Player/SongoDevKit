#!/usr/bin/env bash
# Packages Songo #5 for 64-bit Windows as an installer. Run by songo.sh
# (songo_build_release windows) inside the devkit's windows Docker image,
# which has ImageMagick, Wine (for rcedit), NSIS and MinGW's objdump. songo.sh
# exports the game's .pck first, on the host, and passes in:
#
#   TEMPLATE      Songodot's Windows export template (.exe)
#   PCK           the exported game (Songo5.pck)
#   ENGINE_DLL    SongoBGPlayer's libsongo_engine.windows.x86_64.dll
#   ICON_SRC      the image to make the icon from (Songo-5's project icon)
#   VERSION       Songo's version, eg: "v1.0.0 RC8"
#   LICENSE_FILE  Songo's license, shown by the installer
#   STAGE         a scratch directory for the installer's files
#   SETUP         the installer to write
#   WINEPREFIX    a Wine prefix to keep between runs
#
# The installer (installer.nsi) installs, per user with no admin rights:
#   Songo5.exe          the template, with Songo's icon and version info
#   Songo5.pck          loaded from next to the .exe
#   the engine DLL, LICENSE.txt, songo.ico and an uninstaller
# The .pck isn't embedded in the .exe: Godot embeds it after setting the
# icon, which only works inside its own exporter.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${TEMPLATE:?}" "${PCK:?}" "${ENGINE_DLL:?}" "${ICON_SRC:?}" "${VERSION:?}" "${LICENSE_FILE:?}" "${STAGE:?}" "${SETUP:?}" "${WINEPREFIX:?}"
RCEDIT="$SCRIPT_DIR/tools/rcedit-x64.exe"
OBJDUMP="${CROSS_PREFIX:-x86_64-w64-mingw32-}objdump"

for f in "$TEMPLATE" "$PCK" "$ENGINE_DLL" "$ICON_SRC" "$LICENSE_FILE" "$RCEDIT"; do
    [ -f "$f" ] || { echo "!! Missing $f" >&2; exit 1; }
done
# Captured first: grep -q stopping early would fail the pipe under pipefail
TEMPLATE_STRINGS="$(strings "$TEMPLATE")"
for class in TagLibLibrary SongoPlayerHarness; do
    grep -q "$class" <<< "$TEMPLATE_STRINGS" \
        || { echo "!! $TEMPLATE has no $class, is it a current Songodot Windows template?" >&2; exit 1; }
done

# Windows wants a numeric file version too, eg: 1.0.0.0
NUMERIC_VERSION="$(grep -oE '[0-9]+(\.[0-9]+){0,3}' <<< "$VERSION" | head -n1)"
NUMERIC_VERSION="${NUMERIC_VERSION:-0}"
while [ "$(tr -cd . <<< "$NUMERIC_VERSION" | wc -c)" -lt 3 ]; do NUMERIC_VERSION="$NUMERIC_VERSION.0"; done

rm -rf "$STAGE"
mkdir -p "$STAGE" "$WINEPREFIX"
cp -f "$PCK" "$STAGE/Songo5.pck"
cp -f "$ENGINE_DLL" "$STAGE/"
cp -f "$LICENSE_FILE" "$STAGE/LICENSE.txt"

echo ">> Making Songo5.exe from the template, with Songo's icon and version info ($VERSION)"
# The sizes Godot's own export puts in the .ico
convert "$ICON_SRC" -background none -define icon:auto-resize=256,128,64,48,32,16 "$STAGE/songo.ico"
cp -f "$TEMPLATE" "$STAGE/Songo5.exe"
wine "$RCEDIT" "$STAGE/Songo5.exe" \
    --set-icon "$STAGE/songo.ico" \
    --set-file-version "$NUMERIC_VERSION" \
    --set-product-version "$NUMERIC_VERSION" \
    --set-version-string ProductName "Songo #5" \
    --set-version-string FileDescription "Songo #5" \
    --set-version-string ProductVersion "$VERSION" \
    --set-version-string OriginalFilename "Songo5.exe" \
    --set-version-string InternalName "Songo5" \
    2> >(grep -v "syswow64\|has been updated" >&2)

# Only Windows' own DLLs, so the installed files are all a user needs
echo ">> Checking nothing needs DLLs Windows doesn't have"
for f in "$STAGE/Songo5.exe" "$STAGE/$(basename "$ENGINE_DLL")"; do
    EXTRA="$("$OBJDUMP" -p "$f" | sed -n 's/^\s*DLL Name: //p' | grep -viE '^(kernel32|user32|gdi32|advapi32|shell32|ole32|oleaut32|ws2_32|wsock32|dwrite|bcrypt|secur32|msvcrt|winmm|dwmapi|imm32|shlwapi|uuid|version|dinput8|dxgi|wbemuuid|dsound|avrt|iphlpapi|setupapi|hid|ntdll|crypt32|opengl32|uxtheme|comctl32|comdlg32|propsys|mfplat|mfreadwrite|mfuuid|userenv|winhttp|xinput1_4|api-ms-win-.*)\.dll$' || true)"
    if [ -n "$EXTRA" ]; then
        echo "!! $(basename "$f") needs DLLs that won't be on the user's machine: $EXTRA" >&2
        exit 1
    fi
done

echo ">> Building the installer -> $SETUP"
mkdir -p "$(dirname "$SETUP")"
rm -f "$SETUP"
makensis -V2 \
    -DSRC="$STAGE" \
    -DICON="$STAGE/songo.ico" \
    -DOUT_FILE="$SETUP" \
    -DVERSION="$VERSION" \
    -DNUMERIC_VERSION="$NUMERIC_VERSION" \
    "$SCRIPT_DIR/installer.nsi"
[ -f "$SETUP" ] || { echo "!! makensis didn't produce $SETUP" >&2; exit 1; }
echo ">> Done: $SETUP ($(du -h "$SETUP" | cut -f1))"
