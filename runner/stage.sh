#!/bin/sh
# shellcheck disable=SC1091
# stage.sh: install the built Wine into scratch/stage-raw, then lay it out as a runner root at
# scratch/stage/CrossOver/ (see docs/runner-layout.md and docs/install-layout.md).
#
# Usage: stage.sh
# Exits non-zero on any failure. There is no "manual install" fallback: a partial install
# leaves files like share/wine/winmd/*.winmd missing, and the first wineboot then loops forever
# in setupapi asking for "media" (found in Phase 6).
set -e
. "$(dirname "$0")/lib.sh"

BUILD_DIR="$SCRATCH/build/wine-x86_64"
TOOLS_BUILD_DIR="$SCRATCH/build/wine-tools"
STAGE_RAW="$SCRATCH/stage-raw"
STAGE="$SCRATCH/stage/CrossOver"
LOG="$SCRATCH/logs/install.log"
FT_DYLIB="$SCRATCH/deps-x86_64/lib/libfreetype.6.dylib"
SDL_DYLIB="$SCRATCH/deps-x86_64/lib/libSDL2-2.0.0.dylib"
MVK_DYLIB="$SCRATCH/deps-x86_64/lib/libMoltenVK.dylib"
TLS_DYLIBS="libgmp.10.dylib libnettle.8.dylib libhogweed.6.dylib libgnutls.30.dylib"

[ -f "$BUILD_DIR/Makefile" ] || die "build directory not configured: $BUILD_DIR"
[ -x "$BUILD_DIR/loader/wine" ] || die "build not complete: $BUILD_DIR/loader/wine missing (run runner/build.sh)"
[ -x "$TOOLS_BUILD_DIR/tools/install" ] || die "Wine's install tool missing: $TOOLS_BUILD_DIR/tools/install"
[ -f "$FT_DYLIB" ] || die "freetype missing: $FT_DYLIB (run runner/deps.sh)"
[ -f "$SDL_DYLIB" ] || die "SDL2 missing: $SDL_DYLIB (run runner/deps.sh)"
[ -f "$MVK_DYLIB" ] || die "MoltenVK missing: $MVK_DYLIB (run runner/deps.sh)"
for lib in $TLS_DYLIBS; do [ -f "$SCRATCH/deps-x86_64/lib/$lib" ] || die "$lib missing (run runner/deps.sh)"; done

# 1. make install. The generated Makefile calls $(INSTALL) but does not define it when the
#    tools come from --with-wine-tools, so pass Wine's own tools/install explicitly.
rm -rf "$STAGE_RAW"
mkdir -p "$STAGE_RAW" "$(dirname "$LOG")"
printf 'make install -> %s\n' "$STAGE_RAW"
if ! make -C "$BUILD_DIR" install DESTDIR="$STAGE_RAW" INSTALL="$TOOLS_BUILD_DIR/tools/install" >"$LOG" 2>&1; then
  tail -20 "$LOG"
  die "make install failed, see $LOG"
fi
RAW="$STAGE_RAW/ferry"

# 2. runner root: a real copy (no symlinks into stage-raw, so the stage survives a reinstall
#    and can be packaged as is).
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$RAW/bin" "$RAW/lib" "$RAW/share" "$STAGE/"

# 3. freetype: win32u.so dlopens "@rpath/libfreetype.6.dylib" (configure.sh pins that soname)
#    and carries LC_RPATH @loader_path/, so the dylib lives next to it.
cp "$FT_DYLIB" "$STAGE/lib/wine/x86_64-unix/libfreetype.6.dylib"
otool -D "$STAGE/lib/wine/x86_64-unix/libfreetype.6.dylib" | tail -1 | grep -q '@rpath/libfreetype.6.dylib' \
  || die "staged freetype does not have the @rpath install name"
# SDL2: winebus.so dlopens "@rpath/libSDL2-2.0.0.dylib" (configure.sh) for game controllers
cp "$SDL_DYLIB" "$STAGE/lib/wine/x86_64-unix/libSDL2-2.0.0.dylib"
# MoltenVK: win32u.so dlopens "@rpath/libMoltenVK.dylib" (configure.sh) for Vulkan, which Wine
# also uses to describe the GPU to D3D games; without it some D3D11 games quit at startup
cp "$MVK_DYLIB" "$STAGE/lib/wine/x86_64-unix/libMoltenVK.dylib"
# TLS: secur32/bcrypt/crypt32 dlopen "@rpath/libgnutls.30.dylib"; it finds its siblings next to it
for lib in $TLS_DYLIBS; do cp "$SCRATCH/deps-x86_64/lib/$lib" "$STAGE/lib/wine/x86_64-unix/$lib"; done

# 4. sanity: the paths the run script and the app need
for p in bin/wineserver lib/wine/x86_64-unix/wine lib/wine/x86_64-unix/win32u.so \
         lib/wine/x86_64-windows/ntdll.dll lib/wine/i386-windows/ntdll.dll \
         lib/wine/x86_64-windows/kernel32.dll share/wine/wine.inf share/wine/winmd \
         lib/wine/x86_64-unix/libSDL2-2.0.0.dylib lib/wine/x86_64-unix/winebus.so \
         lib/wine/x86_64-unix/libMoltenVK.dylib lib/wine/x86_64-unix/libgnutls.30.dylib; do
  [ -e "$STAGE/$p" ] || die "stage is missing $p"
done
printf 'staged runner at %s\n' "$STAGE"
