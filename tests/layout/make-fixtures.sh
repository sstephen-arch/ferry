#!/bin/sh
# make-fixtures.sh — build runner-layout test trees under $1.
#
# Each fixture is a minimal runner root.  The "good" fixture satisfies every
# REQUIRED path in runner/verify-layout.sh.  The "bad-*" fixtures each omit or
# corrupt exactly one required item so that verify-layout.sh can be exercised
# on every failure mode.
#
# Usage: sh tests/layout/make-fixtures.sh <out-dir>
#
# Outputs (all under <out-dir>):
#   good               — all required paths present, executables set +x
#   no-wineserver      — same, but bin/wineserver is deleted
#   loader-not-exec    — same, but lib/wine/x86_64-unix/wine is chmod -x
#   no-i386-ntdll      — same, but lib/wine/i386-windows/ntdll.dll is deleted
#   no-wine-inf        — same, but share/wine/wine.inf is deleted

set -eu
out="${1:?usage: make-fixtures.sh <out-dir>}"
rm -rf "$out"
mkdir -p "$out"

mk_good() {
  r="$1"
  mkdir -p "$r/bin" "$r/lib/wine/x86_64-unix" "$r/lib/wine/x86_64-windows" "$r/lib/wine/i386-windows" "$r/share/wine/fonts"
  : > "$r/bin/wineserver"
  chmod +x "$r/bin/wineserver"
  : > "$r/lib/wine/x86_64-unix/wine"
  chmod +x "$r/lib/wine/x86_64-unix/wine"
  : > "$r/lib/wine/x86_64-windows/ntdll.dll"
  : > "$r/lib/wine/i386-windows/ntdll.dll"
  : > "$r/share/wine/wine.inf"
  : > "$r/share/wine/fonts/tahoma.ttf"
}

mk_good "$out/good"

mk_good "$out/no-wineserver"
rm     "$out/no-wineserver/bin/wineserver"

mk_good "$out/loader-not-exec"
chmod -x "$out/loader-not-exec/lib/wine/x86_64-unix/wine"

mk_good "$out/no-i386-ntdll"
rm     "$out/no-i386-ntdll/lib/wine/i386-windows/ntdll.dll"

mk_good "$out/no-wine-inf"
rm     "$out/no-wine-inf/share/wine/wine.inf"
