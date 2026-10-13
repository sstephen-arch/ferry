#!/bin/sh
# shellcheck disable=SC1091
# deps.sh — build the x86_64 libraries Wine loads at runtime: freetype (from the CrossOver
# source tarball) and SDL2 (from the pinned release in ferry-cache; Wine's winebus uses it
# for game controllers, as CrossOver does), and take MoltenVK (Vulkan on Metal; win32u needs
# it for Vulkan and D3D adapter queries) from Khronos's pinned prebuilt release, and the TLS stack
# (GMP + Nettle + GnuTLS; Wine's secur32/bcrypt/crypt32 use it for HTTPS and crypto). Without it
# games that go online fail with "no schannel support" (Lost Judgment: "server not reachable").
#
# Usage: deps.sh
# Exits non-zero on failure.
# Idempotent: each library is skipped when its dylib is already installed (x86_64, @rpath name).
#
# Decision: we use cmake instead of the shipped autoconf configure.
# The CrossOver 26.3.0 freetype tarball is a development snapshot whose
# autoconf tree is incomplete (missing subprojects/dlg submodule, no
# pre-generated configure, and pkg.m4/aclocal issues that make autoconf
# fail on a clean tree). cmake is available in the Phase 0 brew install
# and produces the same outputs (shared dylib, pkg-config, @rpath install
# name) with far fewer moving parts.

set -e

. "$(dirname "$0")/lib.sh"

SRC_FT="$SRC/crossover-26.3.0/sources/freetype"
BUILD_DIR="$SCRATCH/build/freetype-x86_64"
PREFIX="$SCRATCH/deps-x86_64"
DYLIB="$PREFIX/lib/libfreetype.6.dylib"

build_freetype() {

# ---- cmake configure -----------------------------------------------------
# CC/CFLAGS pin the host to x86_64 macOS 13+.
# FT_DISABLE_* mirror the intended --without-* configure flags.
# zlib is kept (system SDK zlib) as the plan allows "zlib from SDK ok".
printf 'configuring freetype x86_64 ...\n'
cmake \
  -S "$SRC_FT" \
  -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=ON \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_C_FLAGS="-arch x86_64 -mmacosx-version-min=13.0" \
  -DFT_DISABLE_HARFBUZZ=ON \
  -DFT_DISABLE_BROTLI=ON \
  -DFT_DISABLE_BZIP2=ON \
  -DFT_DISABLE_PNG=ON

# ---- build ---------------------------------------------------------------
printf 'building freetype x86_64 ...\n'
cmake --build "$BUILD_DIR" --parallel "$JOBS"

# ---- install -------------------------------------------------------------
printf 'installing freetype x86_64 -> %s\n' "$PREFIX"
cmake --install "$BUILD_DIR"

# ---- verify install name -------------------------------------------------
INSTALL_NAME=$(otool -D "$DYLIB" | tail -1)
if [ "$INSTALL_NAME" != "@rpath/libfreetype.6.dylib" ]; then
  die "unexpected install_name for $DYLIB: $INSTALL_NAME (expected @rpath/libfreetype.6.dylib)"
fi
}

# ---- SDL2 ------------------------------------------------------------------
SDL_VER=2.32.10
SDL_TAR="$FERRY_CACHE/SDL2-$SDL_VER.tar.gz"
SDL_SRC="$SRC/SDL2-$SDL_VER"
SDL_BUILD="$SCRATCH/build/sdl2-x86_64"
SDL_DYLIB="$PREFIX/lib/libSDL2-2.0.0.dylib"

build_sdl2() {
  [ -f "$SDL_TAR" ] || die "missing $SDL_TAR (ferry-cache)"
  want=$(awk -v n="SDL2-$SDL_VER.tar.gz" '$1 == n { print $3; exit }' "$FERRY_CACHE/cache.lock")
  got=$(shasum -a 256 "$SDL_TAR" | awk '{ print $1 }')
  [ -n "$want" ] && [ "$want" = "$got" ] || die "sha256 mismatch for $SDL_TAR"
  if [ ! -f "$SDL_SRC/CMakeLists.txt" ]; then
    mkdir -p "$SRC"
    tar xzf "$SDL_TAR" -C "$SRC"
  fi
  printf 'configuring SDL2 %s x86_64 ...\n' "$SDL_VER"
  # @rpath install name: winebus.so dlopens SONAME_LIBSDL2 (pinned by configure.sh) and finds
  # it through its LC_RPATH @loader_path/, next to it in lib/wine/x86_64-unix/
  cmake -S "$SDL_SRC" -B "$SDL_BUILD" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_INSTALL_NAME_DIR=@rpath \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST=OFF
  cmake --build "$SDL_BUILD" --parallel "$JOBS"
  cmake --install "$SDL_BUILD"
  name=$(otool -D "$SDL_DYLIB" | tail -1)
  [ "$name" = "@rpath/libSDL2-2.0.0.dylib" ] || die "unexpected install_name for $SDL_DYLIB: $name"
  [ "$(lipo -archs "$SDL_DYLIB")" = x86_64 ] || die "$SDL_DYLIB is not x86_64"
}

# ---- MoltenVK ----------------------------------------------------------------
# Khronos's prebuilt release (KhronosGroup/MoltenVK, CI-built, digest checked against GitHub's);
# CrossOver 26.3.0 ships stock MoltenVK 1.2.10 with no CrossOver changes. Universal, so only the
# x86_64 half is kept: the runner is Rosetta-only.
MVK_VER=1.4.2
MVK_TAR="$FERRY_CACHE/MoltenVK-$MVK_VER-macos.tar"
MVK_DYLIB="$PREFIX/lib/libMoltenVK.dylib"

take_moltenvk() {
  [ -f "$MVK_TAR" ] || die "missing $MVK_TAR (ferry-cache)"
  want=$(awk -v n="MoltenVK-$MVK_VER-macos.tar" '$1 == n { print $3; exit }' "$FERRY_CACHE/cache.lock")
  got=$(shasum -a 256 "$MVK_TAR" | awk '{ print $1 }')
  [ -n "$want" ] && [ "$want" = "$got" ] || die "sha256 mismatch for $MVK_TAR"
  out="$SCRATCH/build/moltenvk-$MVK_VER"
  rm -rf "$out" && mkdir -p "$out" "$PREFIX/lib"
  tar xf "$MVK_TAR" -C "$out" MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib
  lipo -thin x86_64 "$out/MoltenVK/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib" -output "$MVK_DYLIB"
  name=$(otool -D "$MVK_DYLIB" | tail -1)
  [ "$name" = "@rpath/libMoltenVK.dylib" ] || die "unexpected install_name for $MVK_DYLIB: $name"
}

# ---- TLS: GMP, Nettle, GnuTLS ------------------------------------------------
# GMP and GnuTLS come from the CrossOver tarball. Its Nettle lacks the top-level Makefile.in, so
# Nettle is the official 3.10 release (pinned; GNU signature by the Nettle maintainer checked).
TLS_SRC="$SRC/crossover-26.3.0/sources/gnutls"
NETTLE_VER=3.10
NETTLE_TAR="$FERRY_CACHE/nettle-$NETTLE_VER.tar.gz"
TLS_DYLIBS="libgmp.10.dylib libnettle.8.dylib libhogweed.6.dylib libgnutls.30.dylib"
TLS_CROSS="--host=x86_64-apple-darwin --build=aarch64-apple-darwin --prefix=$PREFIX --enable-shared --disable-static"

# autotools build <name> <srcdir> <configure args...>: out of tree, x86_64, macOS 13+
tls_build() {
  name=$1 src=$2
  shift 2
  dir="$SCRATCH/build/$name-x86_64"
  rm -rf "$dir" && mkdir -p "$dir"
  printf 'building %s x86_64 ...\n' "$name"
  # shellcheck disable=SC2086 # TLS_CROSS is a list of flags
  ( cd "$dir" && PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" "$src/configure" $TLS_CROSS "$@" \
      CC="clang -arch x86_64" CFLAGS="-O2 -mmacosx-version-min=13.0" CPPFLAGS="-I$PREFIX/include" \
      LDFLAGS="-L$PREFIX/lib -Wl,-headerpad_max_install_names" > configure.log 2>&1 \
    && make -j"$JOBS" > make.log 2>&1 && make install > install.log 2>&1 ) \
    || { tail -20 "$dir/make.log" "$dir/configure.log" 2>/dev/null; die "$name build failed, see $dir"; }
}

build_tls() {
  [ -f "$NETTLE_TAR" ] || die "missing $NETTLE_TAR (ferry-cache)"
  want=$(awk -v n="nettle-$NETTLE_VER.tar.gz" '$1 == n { print $3; exit }' "$FERRY_CACHE/cache.lock")
  got=$(shasum -a 256 "$NETTLE_TAR" | awk '{ print $1 }')
  [ -n "$want" ] && [ "$want" = "$got" ] || die "sha256 mismatch for $NETTLE_TAR"
  [ -f "$SRC/nettle-$NETTLE_VER/configure" ] || tar xzf "$NETTLE_TAR" -C "$SRC"

  tls_build gmp "$TLS_SRC/gmp" --disable-cxx --disable-assembly
  tls_build nettle "$SRC/nettle-$NETTLE_VER" --disable-documentation --disable-openssl --disable-assembler
  # NETTLE_LIBS & co must be single words: gnutls's configure tests them unquoted, and a value
  # with a space silently turns its nettle crypto backend off (then the link fails).
  # GOST off: gnutls 3.8.3's own GOST code clashes with nettle 3.10's.
  tls_build gnutls "$TLS_SRC/gnutls" --with-included-libtasn1 --with-included-unistring \
    --without-p11-kit --without-idn --without-brotli --without-zstd --without-tpm --without-tpm2 \
    --disable-gost --disable-tools --disable-doc --disable-tests --disable-cxx --disable-nls \
    --disable-guile --disable-libdane --disable-hardware-acceleration \
    NETTLE_LIBS=-lnettle HOGWEED_LIBS=-lhogweed GMP_LIBS=-lgmp

  # @rpath names, siblings found next to each other (they all end up in lib/wine/x86_64-unix)
  for lib in $TLS_DYLIBS; do
    f="$PREFIX/lib/$lib"
    install_name_tool -id "@rpath/$lib" "$f"
    for dep in $TLS_DYLIBS; do install_name_tool -change "$PREFIX/lib/$dep" "@rpath/$dep" "$f"; done
    install_name_tool -add_rpath @loader_path/ "$f" 2>/dev/null || true
    otool -L "$f" | tail -n +2 | grep -q "$PREFIX" && die "$lib still links an absolute $PREFIX path"
  done
}

# usable <dylib> <install name>: already built for this runner (x86_64, @rpath name), so skip it
usable() {
  [ -f "$1" ] && [ "$(otool -D "$1" | tail -1)" = "$2" ] && [ "$(lipo -archs "$1")" = x86_64 ]
}
if usable "$DYLIB" @rpath/libfreetype.6.dylib; then printf 'freetype already installed: %s\n' "$DYLIB"; else build_freetype; fi
if usable "$SDL_DYLIB" @rpath/libSDL2-2.0.0.dylib; then printf 'SDL2 already installed: %s\n' "$SDL_DYLIB"; else build_sdl2; fi
if usable "$MVK_DYLIB" @rpath/libMoltenVK.dylib; then printf 'MoltenVK already installed: %s\n' "$MVK_DYLIB"; else take_moltenvk; fi
if usable "$PREFIX/lib/libgnutls.30.dylib" @rpath/libgnutls.30.dylib; then printf 'GnuTLS already installed\n'; else build_tls; fi
printf '%s\n%s\n%s\n' "$DYLIB" "$SDL_DYLIB" "$MVK_DYLIB"
