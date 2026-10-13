#!/bin/sh
# shellcheck disable=SC1091
# graphics.sh: install the graphics backends into the staged runner (see docs/graphics-layout.md).
#
#   graphics.sh --dxmt       DXMT v0.80 builtins (D3D10/11 on Metal), from ferry-cache
#   graphics.sh --d3dmetal   Apple's D3DMetal from the owner's GPTK redist in ferry-cache/gptk
#                            (never committed; Apple's licence forbids redistribution)
#
# Both also install CrossOver/share/ferry/backend.sh, which the run script sources to pick the
# backend from CX_GRAPHICS_BACKEND. Layout:
#   lib/dxmt/{x86_64,i386}-windows/   DXMT's d3d11, dxgi, d3d10core (+ nvapi64, nvngx on x86_64)
#   lib/wine/{x86_64,i386}-windows/winemetal.dll, lib/wine/x86_64-unix/winemetal.so
#       (no name clash with Wine; winemetal.so finds winemac.so/ntdll.so via @loader_path)
#   lib64/apple_gptk/external/        D3DMetal.framework, libd3dshared.dylib
#   lib64/apple_gptk/wine/x86_64-{windows,unix}/   GPTK's d3d10/11/12, dxgi, nvapi64, nvngx
set -e
. "$(dirname "$0")/lib.sh"

STAGE="$SCRATCH/stage/CrossOver"
DXMT_TAR="$FERRY_CACHE/dxmt-v0.80-builtin.tar.gz"
GPTK="$FERRY_CACHE/gptk/redist/lib"

[ -d "$STAGE/lib/wine" ] || die "stage the runner first (runner/stage.sh)"

install_backend_sh() {
  mkdir -p "$STAGE/share/ferry"
  cat > "$STAGE/share/ferry/backend.sh" <<'EOF'
# Ferry graphics backend selection. POSIX sh, sourced by the run script with CX_ROOT and
# CX_GRAPHICS_BACKEND set. Only exports variables; never runs programs.
#   dxmt      DXMT (D3D10/11 -> Metal)
#   d3dmetal  Apple D3DMetal (D3D11/12 -> Metal), 64-bit only, needs the GPTK files
#   empty or wined3d   Wine's own wined3d
# FERRY_DLLPATH_FIRST (Ferry ntdll patch 0002) puts the backend's directory ahead of Wine's
# own dll dir, so its d3d11/dxgi replace Wine's builtins.
ferry_prepend() { FERRY_DLLPATH_FIRST="$1${FERRY_DLLPATH_FIRST:+:$FERRY_DLLPATH_FIRST}"; export FERRY_DLLPATH_FIRST; }
case "${CX_GRAPHICS_BACKEND:-}" in
  dxmt)
    if [ -d "$CX_ROOT/lib/dxmt/x86_64-windows" ]; then
      ferry_prepend "$CX_ROOT/lib/dxmt"
    else
      echo "ferry backend.sh: DXMT is not installed in $CX_ROOT, using wined3d" >&2
    fi
    ;;
  d3dmetal)
    if [ -f "$CX_ROOT/lib64/apple_gptk/external/libd3dshared.dylib" ]; then
      ferry_prepend "$CX_ROOT/lib64/apple_gptk/wine"
      CX_APPLEGPTK_LIBD3DSHARED_PATH="$CX_ROOT/lib64/apple_gptk/external/libd3dshared.dylib"
      export CX_APPLEGPTK_LIBD3DSHARED_PATH
    else
      echo "ferry backend.sh: D3DMetal (GPTK) is not installed in $CX_ROOT, using wined3d" >&2
    fi
    ;;
  ''|wined3d) ;;
  *) echo "ferry backend.sh: unknown CX_GRAPHICS_BACKEND=$CX_GRAPHICS_BACKEND, using wined3d" >&2 ;;
esac
EOF
}

install_dxmt() {
  [ -f "$DXMT_TAR" ] || die "missing $DXMT_TAR"
  t=$(mktemp -d)
  tar xzf "$DXMT_TAR" -C "$t"
  d="$t/v0.80"
  [ -f "$d/x86_64-unix/winemetal.so" ] || die "unexpected DXMT tarball layout"
  rm -rf "$STAGE/lib/dxmt"
  mkdir -p "$STAGE/lib/dxmt/x86_64-windows" "$STAGE/lib/dxmt/i386-windows"
  for f in d3d11 dxgi d3d10core nvapi64 nvngx; do
    cp -f "$d/x86_64-windows/$f.dll" "$STAGE/lib/dxmt/x86_64-windows/"
  done
  for f in d3d11 dxgi d3d10core; do
    cp -f "$d/i386-windows/$f.dll" "$STAGE/lib/dxmt/i386-windows/"
  done
  cp -f "$d/x86_64-windows/winemetal.dll" "$STAGE/lib/wine/x86_64-windows/winemetal.dll"
  cp -f "$d/i386-windows/winemetal.dll" "$STAGE/lib/wine/i386-windows/winemetal.dll"
  cp -f "$d/x86_64-unix/winemetal.so" "$STAGE/lib/wine/x86_64-unix/winemetal.so"
  rm -rf "$t"
  install_backend_sh
  printf 'installed DXMT v0.80\n'
}

install_d3dmetal() {
  [ -f "$GPTK/external/libd3dshared.dylib" ] || die "no GPTK in $FERRY_CACHE/gptk/redist (owner downloads it from developer.apple.com)"
  g="$STAGE/lib64/apple_gptk"
  rm -rf "$g"
  mkdir -p "$g/external" "$g/wine"
  cp -R "$GPTK/external/D3DMetal.framework" "$GPTK/external/libd3dshared.dylib" "$g/external/"
  cp -R "$GPTK/wine/x86_64-windows" "$GPTK/wine/x86_64-unix" "$g/wine/"
  install_backend_sh
  printf 'installed D3DMetal from GPTK\n'
}

case "${1:-}" in
  --dxmt) install_dxmt ;;
  --d3dmetal) install_d3dmetal ;;
  *) die "usage: graphics.sh --dxmt | --d3dmetal" ;;
esac
