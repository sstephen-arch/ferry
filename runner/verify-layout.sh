#!/bin/sh
# verify-layout.sh — check that a runner root satisfies the layout contract.
#
# Usage:
#   verify-layout.sh <root>              # exits 0 on success, 1 on failure
#   verify-layout.sh --json <root>       # prints JSON summary to stdout; same exit status
#
# REQUIRED paths (every runner must have these):
#   bin/wineserver
#   lib/wine/x86_64-unix/wine            (the Rosetta loader, must be executable)
#   lib/wine/x86_64-windows/ntdll.dll
#   lib/wine/i386-windows/ntdll.dll
#   lib/wine/x86_64-windows              (directory)
#   lib/wine/i386-windows                (directory)
#   share/wine/wine.inf
#   share/wine/fonts                     (directory)
#
# OPTIONAL paths (checked for information only; absence is not a failure):
#   lib64/apple_gptk/external/libd3dshared.dylib   (D3DMetal, user-supplied)
#   bin/wineserver-arm64                 (FEX/arm64 build)
#   lib/wine/aarch64-unix                (FEX/arm64 Wine loader dir)

set -e

json_mode=0
case "$1" in
  --json) json_mode=1; shift ;;
esac
root="$1"

if [ -z "$root" ]; then
  printf 'usage: verify-layout.sh [--json] <root>\n' >&2
  exit 2
fi

missing=0
json_first=1

check_required() {
  path="$1"
  must_exec="$2"
  full="$root/$path"
  if [ ! -e "$full" ]; then
    printf 'MISSING %s\n' "$path" >&2
    missing=$((missing + 1))
    if [ "$json_mode" -eq 1 ]; then
      [ "$json_first" -eq 0 ] && json_paths="${json_paths},"
      json_paths="${json_paths}{\"path\":\"$path\",\"required\":true,\"present\":false}"
      json_first=0
    fi
    return
  fi
  if [ "$must_exec" = "yes" ] && [ ! -x "$full" ]; then
    printf 'NOT-EXECUTABLE %s\n' "$path" >&2
    missing=$((missing + 1))
    if [ "$json_mode" -eq 1 ]; then
      [ "$json_first" -eq 0 ] && json_paths="${json_paths},"
      json_paths="${json_paths}{\"path\":\"$path\",\"required\":true,\"present\":true,\"executable\":false}"
      json_first=0
    fi
    return
  fi
  if [ "$json_mode" -eq 1 ]; then
    [ "$json_first" -eq 0 ] && json_paths="${json_paths},"
    json_paths="${json_paths}{\"path\":\"$path\",\"required\":true,\"present\":true}"
    json_first=0
  fi
}

check_optional() {
  path="$1"
  full="$root/$path"
  if [ -e "$full" ]; then
    if [ "$json_mode" -eq 1 ]; then
      [ "$json_first" -eq 0 ] && json_paths="${json_paths},"
      json_paths="${json_paths}{\"path\":\"$path\",\"required\":false,\"present\":true}"
      json_first=0
    fi
  else
    if [ "$json_mode" -eq 1 ]; then
      [ "$json_first" -eq 0 ] && json_paths="${json_paths},"
      json_paths="${json_paths}{\"path\":\"$path\",\"required\":false,\"present\":false}"
      json_first=0
    fi
  fi
}

# REQUIRED
check_required "bin/wineserver"            "yes"
check_required "lib/wine/x86_64-unix/wine"  "yes"
check_required "lib/wine/x86_64-windows/ntdll.dll" "no"
check_required "lib/wine/i386-windows/ntdll.dll"   "no"
check_required "lib/wine/x86_64-windows"    "no"
check_required "lib/wine/i386-windows"      "no"
check_required "share/wine/wine.inf"        "no"
check_required "share/wine/fonts"           "no"

# OPTIONAL
check_optional "lib64/apple_gptk/external/libd3dshared.dylib" ""
check_optional "bin/wineserver-arm64"   ""
check_optional "lib/wine/aarch64-unix"  ""

if [ "$json_mode" -eq 1 ]; then
  root_json=$(printf '%s' "$root" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '{"root":"%s","missing":%d,"checks":[%s]}\n' \
    "$root_json" "$missing" "$json_paths"
  [ "$missing" -eq 0 ] || exit 1
else
  if [ "$missing" -gt 0 ]; then
    exit 1
  fi
  printf 'ok: %s\n' "$root"
  exit 0
fi