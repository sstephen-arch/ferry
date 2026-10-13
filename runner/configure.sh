#!/bin/sh
# shellcheck disable=SC1091
# configure.sh — configure CrossOver's Wine for x86_64 macOS host with i386+x86_64 PE.
#
# Usage: configure.sh
# Exits non-zero on failure.
# Idempotent: skips re-copying source when patches have not changed.
#
# Two-stage build:
#   1. Native tools build (winebuild, widl, etc.) for the host.
#   2. Cross-configure the main Wine tree using those tools.

set -e

. "$(dirname "$0")/lib.sh"

# ---- paths ---------------------------------------------------------------
WINE_SRC="$SRC/crossover-26.3.0/sources/wine"
PATCHED_SRC="$SRC/wine-patched"
BUILD_DIR="$SCRATCH/build/wine-x86_64"
TOOLS_BUILD_DIR="$SCRATCH/build/wine-tools"
PATCHES_DIR="$(cd "$(dirname "$0")/.." && pwd)/patches/wine"
PATCH_HASH_FILE="$PATCHED_SRC/.patch-hash"

# ---- prerequisites -------------------------------------------------------
if [ ! -d "$WINE_SRC" ]; then
  die "Wine source not found at $WINE_SRC (run runner/fetch.sh first)"
fi
if [ ! -x "$WINE_SRC/configure" ]; then
  die "Wine configure not found at $WINE_SRC/configure"
fi
for tool in make bison flex; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    die "required tool not found: $tool"
  fi
done
for tool in x86_64-w64-mingw32-gcc i686-w64-mingw32-gcc; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    die "required cross-compiler not found: $tool"
  fi
done
if [ ! -f "$SCRATCH/deps-x86_64/lib/libfreetype.6.dylib" ]; then
  die "freetype not found at $SCRATCH/deps-x86_64/lib/libfreetype.6.dylib (run runner/deps.sh first)"
fi

# ---- apply patches (idempotent) ------------------------------------------
compute_patch_hash() {
  hash_files="$PATCHES_DIR/series"
  if [ -f "$hash_files" ]; then
    while IFS= read -r patch; do
      [ -z "$patch" ] && continue
      [ -f "$PATCHES_DIR/$patch" ] && hash_files="$hash_files $PATCHES_DIR/$patch"
    done < "$hash_files"
  fi
  # shellcheck disable=SC2086
  sha256sum $hash_files 2>/dev/null | sha256sum | awk '{ print $1 }'
}

need_copy=false
if [ ! -d "$PATCHED_SRC" ]; then
  need_copy=true
elif [ -f "$PATCH_HASH_FILE" ]; then
  stored=$(cat "$PATCH_HASH_FILE")
  current=$(compute_patch_hash)
  if [ "$stored" != "$current" ]; then
    need_copy=true
  fi
else
  need_copy=true
fi

if [ "$need_copy" = true ]; then
  printf 'copying Wine source for patching ...\n'
  rm -rf "$PATCHED_SRC"
  cp -Rp "$WINE_SRC" "$PATCHED_SRC"

  if [ -f "$PATCHES_DIR/series" ]; then
    while IFS= read -r patch; do
      [ -z "$patch" ] && continue
      patch_file="$PATCHES_DIR/$patch"
      if [ -f "$patch_file" ]; then
        printf 'applying patch: %s\n' "$patch"
        if ! ( cd "$PATCHED_SRC" && git apply --directory=. "$patch_file" ); then
          die "failed to apply patch: $patch"
        fi
      else
        die "patch file not found: $patch_file"
      fi
    done < "$PATCHES_DIR/series"
  fi

  mkdir -p "$PATCHED_SRC"
  compute_patch_hash > "$PATCH_HASH_FILE"
fi

# ---- stage 1: build native Wine tools ------------------------------------
printf 'configuring Wine tools (native) ...\n'
mkdir -p "$TOOLS_BUILD_DIR"
cd "$TOOLS_BUILD_DIR"
rm -f config.status config.log

PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH"
export PATH
export PKG_CONFIG_PATH="$SCRATCH/deps-x86_64/lib/pkgconfig"

"$PATCHED_SRC/configure" \
  --prefix=/usr \
  --enable-archs=x86_64 \
  --without-freetype \
  --without-x \
  --disable-tests \
  CC="clang -arch x86_64" \
  CXX="clang++ -arch x86_64"

printf 'building Wine tools ...\n'
make tools -j"$JOBS"

if [ ! -x "$TOOLS_BUILD_DIR/tools/winebuild/winebuild" ]; then
  die "Wine tools not built: $TOOLS_BUILD_DIR/tools/winebuild/winebuild missing"
fi
if [ ! -f "$TOOLS_BUILD_DIR/tools/makedep" ]; then
  die "Wine tools not built: $TOOLS_BUILD_DIR/tools/makedep missing"
fi
# wrc looks for nls/locale.nls two levels above itself, i.e. in this out-of-tree tools build,
# which `make tools` does not populate; without it every .rc compile in a CLEAN Wine build fails
# with "unable to load locale.nls" (incremental builds hid this).
mkdir -p "$TOOLS_BUILD_DIR/nls"
cp -f "$PATCHED_SRC/nls/locale.nls" "$TOOLS_BUILD_DIR/nls/locale.nls"
printf 'Wine tools built ok\n'

# ---- stage 2: cross-configure Wine ---------------------------------------
printf 'configuring Wine x86_64 cross ...\n'
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
rm -f config.status config.log

PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH"
export PATH
export PKG_CONFIG_PATH="$SCRATCH/deps-x86_64/lib/pkgconfig"

"$PATCHED_SRC/configure" \
  --host=x86_64-apple-darwin \
  --prefix=/ferry \
  --enable-archs=i386,x86_64 \
  --with-freetype \
  --without-x \
  --disable-tests \
  --with-wine-tools="$TOOLS_BUILD_DIR" \
  ac_cv_lib_soname_freetype="@rpath/libfreetype.6.dylib" \
  ac_cv_lib_soname_vulkan="@rpath/libMoltenVK.dylib" \
  ac_cv_lib_soname_SDL2="@rpath/libSDL2-2.0.0.dylib" \
  ac_cv_lib_soname_gnutls="@rpath/libgnutls.30.dylib" \
  CC="clang -arch x86_64" \
  CXX="clang++ -arch x86_64"

# ---- verify configure ----------------------------------------------------
if ! grep -q '^host_cpu = x86_64' "$BUILD_DIR/config.status"; then
  die "host_cpu is not x86_64 in config.status (cross-configure may have fallen back)"
fi
if ! grep -q 'SONAME_LIBFREETYPE' "$BUILD_DIR/include/config.h"; then
  die "freetype was not found by configure (SONAME_LIBFREETYPE missing from config.h)"
fi
if ! grep -q 'SONAME_LIBSDL2' "$BUILD_DIR/include/config.h"; then
  die "SDL2 was not found by configure (controllers would not work; run runner/deps.sh)"
fi
# GnuTLS: secur32 (schannel, HTTPS), bcrypt and crypt32 dlopen it; without it games can't go online
if ! grep -q '#define SONAME_LIBGNUTLS' "$BUILD_DIR/include/config.h"; then
  die "configure did not find GnuTLS (SONAME_LIBGNUTLS missing; run runner/deps.sh)"
fi
if ! grep -qE '^PE_ARCHS.*i386' "$BUILD_DIR/Makefile"; then
  die "i386 PE arch not enabled (PE_ARCHS missing from Makefile)"
fi
if ! grep -qE '^PE_ARCHS.*x86_64' "$BUILD_DIR/Makefile"; then
  die "x86_64 PE arch not enabled (PE_ARCHS missing from Makefile)"
fi

# ---- print summary -------------------------------------------------------
printf '\n=== Configure summary ===\n'
printf 'host_cpu   = '
grep '^host_cpu' "$BUILD_DIR/config.status"
printf 'build_cpu  = '
grep '^build_cpu' "$BUILD_DIR/config.status"
printf 'PE_ARCHS   = '
grep '^PE_ARCHS' "$BUILD_DIR/Makefile"
printf 'freetype   = '
grep 'SONAME_LIBFREETYPE' "$BUILD_DIR/include/config.h" | head -1
printf 'prefix     = /ferry\n'
printf '=======================\n\n'
