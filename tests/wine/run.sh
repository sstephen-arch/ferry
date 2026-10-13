#!/bin/sh
# tests/wine/run.sh: run the Wine-level tests against a Ferry runner root.
#
#   sh tests/wine/run.sh                     the staged runner (scratch/stage/CrossOver)
#   sh tests/wine/run.sh dist/ferry-runner-<ver>-rosetta/CrossOver
#
# Covers what no Swift test can: Wine boots (64- and 32-bit), fonts load, the steamclient ->
# lsteamclient redirect (ntdll patch 0001) behaves like NotProton's detour, and the graphics
# backends selected through backend.sh (ntdll patch 0002) create a D3D11 device. Run it after
# any change to patches/wine/ or a new CrossOver source drop.
# Needs mingw-w64 (x86_64/i686-w64-mingw32-gcc). Exits non-zero if any check fails.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
ROOT=$(cd "${1:-$repo/scratch/stage/CrossOver}" 2>/dev/null && pwd) || { echo "no runner root at ${1:-scratch/stage/CrossOver}"; exit 2; }
LOADER=$ROOT/lib/wine/x86_64-unix/wine
[ -x "$LOADER" ] && [ -x "$ROOT/bin/wineserver" ] || { echo "$ROOT is not a runner root"; exit 2; }

# Environment every Ferry launch needs (see docs/install-layout.md)
export WINEVERTEMP=/tmp WINEDEBUG=-all WINESERVER="$ROOT/bin/wineserver"
[ -d "/tmp/.wine-$(id -u)" ] && chmod 700 "/tmp/.wine-$(id -u)"
BASE_OVERRIDES="mscoree=d;mshtml=d"

tmp=$(mktemp -d /tmp/ferry-tests.XXXXXX)
pfx="$tmp/pfx"
trap 'WINEPREFIX="$pfx" "$ROOT/bin/wineserver" -k 2>/dev/null; rm -rf "$tmp"' EXIT
pass=0
fail=0

ok() { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL  %s\n      want %s\n      got  %s\n' "$1" "$2" "$3"; }

# build <32|64> <out> <sources...> [-lfoo]: compile and check the PE machine type
build() {
  bits=$1 out=$2
  shift 2
  if [ "$bits" = 32 ]; then cc=i686-w64-mingw32-gcc od=i686-w64-mingw32-objdump want=pei-i386
  else cc=x86_64-w64-mingw32-gcc od=x86_64-w64-mingw32-objdump want=pei-x86-64; fi
  case "$out" in *.dll) shared=-shared ;; *) shared= ;; esac
  mkdir -p "$(dirname "$out")"
  # shellcheck disable=SC2086 # $shared is empty or one flag
  "$cc" -O1 $shared -o "$out" "$@" || { echo "compile failed: $out"; exit 2; }
  "$od" -f "$out" | grep -q "file format $want" || { echo "$out is not $want"; exit 2; }
}

# out <dir> <overrides> <extra env or -> <exe> [args]: trimmed stdout of the program, 3 min cap
out() {
  dir=$1 overrides=$2 extra=$3
  shift 3
  [ "$extra" = - ] && extra=
  # shellcheck disable=SC2086 # $extra is a list of NAME=value words
  (cd "$dir" && env $extra WINEPREFIX="$pfx" WINEDLLOVERRIDES="$overrides" \
    perl -e 'alarm 180; exec @ARGV or die q(exec failed)' "$LOADER" "$@" 2>/dev/null) \
    | tr -d '\r' | sed -e 's/[[:space:]]*$//'
}

# expect <name> <want> <dir> <overrides> <extra env or -> <exe> [args]
expect() {
  name=$1 want=$2
  shift 2
  got=$(out "$@")
  if [ "$got" = "$want" ]; then ok "$name"; else bad "$name" "$want" "$got"; fi
}

# expect_re <name> <extended regex> <dir> <overrides> <extra env or -> <exe> [args]
expect_re() {
  name=$1 re=$2
  shift 2
  got=$(out "$@")
  if printf '%s\n' "$got" | grep -Eq -- "$re"; then ok "$name"; else bad "$name" "/$re/" "$got"; fi
}

# ---- fixtures -------------------------------------------------------------------------------
B="$tmp/bin"
build 64 "$B/hello64.exe" "$here/hello.c"
build 32 "$B/hello32.exe" "$here/hello.c"
x86_64-w64-mingw32-gcc -o "$B/fontcount.exe" "$here/fontcount.c" -lgdi32
x86_64-w64-mingw32-gcc -o "$B/d3d11_probe.exe" "$here/d3d11_probe.c" -ld3d11 -ldxgi -luuid
x86_64-w64-mingw32-gcc -o "$B/tls_probe.exe" "$here/tls_probe.c" -lsecur32 -lbcrypt

D64="$tmp/sc64" D32="$tmp/sc32" N64="$tmp/nolsteam64" X64="$tmp/scx64" O32="$tmp/overlay32" REAL="$tmp/real64"
build 64 "$D64/probe.exe" "$here/probe.c"
build 64 "$D64/steamclient64.dll" "$here/fake_steamclient.c"
build 64 "$D64/lsteamclient.dll" "$here/fake_lsteamclient.c"
build 32 "$D32/probe.exe" "$here/probe.c"
build 32 "$D32/steamclient.dll" "$here/fake_steamclient.c"
build 32 "$D32/lsteamclient.dll" "$here/fake_lsteamclient.c"
mkdir -p "$N64" "$X64" "$REAL"
cp "$D64/probe.exe" "$D64/steamclient64.dll" "$N64/"
cp "$D64/probe.exe" "$D64/lsteamclient.dll" "$X64/"
cp "$D64/steamclient64.dll" "$X64/steamclientx.dll"
build 32 "$O32/gameoverlayrenderer.dll" "$here/fake_overlay.c"
cp "$D32/probe.exe" "$D32/lsteamclient.dll" "$O32/"
cp "$D64/probe.exe" "$D64/steamclient64.dll" "$REAL/"

FAKE="lsteamclient=n;$BASE_OVERRIDES"     # use the fake lsteamclient.dll next to the probe
NONE="lsteamclient=;$BASE_OVERRIDES"      # no lsteamclient at all, not even the runner's own

# ---- boot -----------------------------------------------------------------------------------
echo "runner: $ROOT"
if WINEPREFIX="$pfx" WINEDLLOVERRIDES="$BASE_OVERRIDES" perl -e 'alarm 300; exec @ARGV or die q(exec failed)' \
     "$LOADER" wineboot --init >/dev/null 2>&1; then ok "wineboot --init"; else bad "wineboot --init" "exit 0" "failed"; fi
expect "hello 64-bit" "ferry-hello x86_64" "$B" "$BASE_OVERRIDES" - hello64.exe
expect "hello 32-bit (WoW64)" "ferry-hello i386" "$B" "$BASE_OVERRIDES" - hello32.exe
expect_re "fonts are visible" "^FONTS=[1-9]" "$B" "$BASE_OVERRIDES" - fontcount.exe
# GnuTLS: without it schannel is missing and games can't reach their servers over HTTPS
expect "TLS: schannel and RSA work (GnuTLS)" "SCHANNEL=0x00000000 RSA=0x00000000" "$B" "$BASE_OVERRIDES" - tls_probe.exe

# ---- steamclient redirect (patch 0001) -------------------------------------------------------
expect "64-bit: shared exports go to lsteamclient, real DllMain skipped" "A=2 B=22 R=99 E=0 L=1 M=1" "$D64" "$FAKE" - probe.exe steamclient64.dll
expect "32-bit: shared exports go to lsteamclient, real DllMain skipped" "A=2 B=22 R=99 E=0 L=1 M=1" "$D32" "$FAKE" - probe.exe steamclient.dll
expect "no lsteamclient: real steamclient loads normally" "A=1 B=11 R=99 E=1 L=0 M=1" "$N64" "$NONE" - probe.exe steamclient64.dll
expect "FERRY_STEAMCLIENT_REDIRECT=0 turns it off" "A=1 B=11 R=99 E=1 L=0 M=1" "$D64" "$FAKE" FERRY_STEAMCLIENT_REDIRECT=0 probe.exe steamclient64.dll
expect "a DLL named steamclientx.dll is left alone" "A=1 B=11 R=99 E=1 L=0 M=1" "$X64" "$FAKE" - probe.exe steamclientx.dll
expect "32-bit overlay: DllMain skipped with lsteamclient" "O=0" "$O32" "$FAKE" - probe.exe --overlay
expect "32-bit overlay: DllMain runs without lsteamclient" "O=1" "$O32" "$NONE" - probe.exe --overlay
expect "32-bit overlay: DllMain runs with the redirect off" "O=1" "$O32" "$FAKE" FERRY_STEAMCLIENT_REDIRECT=0 probe.exe --overlay
if [ -f "$ROOT/lib/wine/x86_64-windows/lsteamclient.dll" ]; then
  expect_re "the runner's real lsteamclient is picked up" "E=0 L=1 M=1$" "$REAL" "$BASE_OVERRIDES" - probe.exe steamclient64.dll
else
  echo "SKIP  real lsteamclient (not installed in this runner)"
fi

# ---- graphics backends (patch 0002 + share/ferry/backend.sh) --------------------------------
backend_env() {  # the variables backend.sh exports for one backend, as NAME=value words
  env -i PATH=/usr/bin:/bin CX_ROOT="$ROOT" CX_GRAPHICS_BACKEND="$1" \
    sh -c ". \"$ROOT/share/ferry/backend.sh\" >/dev/null 2>&1; env" | grep -E '^(FERRY_|CX_APPLE)' | tr '\n' ' '
}
expect_re "wined3d: D3D11 device" "^hr=0x00000000 .* wined3d=1 winemetal=0$" "$B" "$BASE_OVERRIDES" - d3d11_probe.exe
if [ -f "$ROOT/share/ferry/backend.sh" ] && [ -d "$ROOT/lib/dxmt" ]; then
  expect_re "DXMT: D3D11 device on the Apple GPU" "^hr=0x00000000 adapter=Apple.* wined3d=0 winemetal=1$" "$B" "$BASE_OVERRIDES" "$(backend_env dxmt)" d3d11_probe.exe
else
  echo "SKIP  DXMT (not installed in this runner)"
fi
if [ -f "$ROOT/share/ferry/backend.sh" ] && [ -f "$ROOT/lib64/apple_gptk/external/libd3dshared.dylib" ]; then
  # GPTK reports its device as "AMD Compatibility Mode"
  expect_re "D3DMetal: D3D11 device" "^hr=0x00000000 adapter=(AMD Compatibility Mode|Apple).* wined3d=0 winemetal=0$" "$B" "$BASE_OVERRIDES" "$(backend_env d3dmetal)" d3d11_probe.exe
else
  echo "SKIP  D3DMetal (no GPTK in this runner)"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
