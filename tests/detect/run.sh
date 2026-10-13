#!/bin/sh
# tests/detect/run.sh: the graphics auto-detection in app/helpers/appinfo.swift (`appinfo --graphics`)
# against real 32- and 64-bit PE files that import each graphics API. Needs swiftc and mingw-w64.
set -u
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d /tmp/ferry-detect.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
swiftc -O -o "$tmp/appinfo" "$repo/app/helpers/appinfo.swift" || { echo "appinfo did not build"; exit 2; }
pass=0 fail=0
check() {  # check <name> <expected prefix> <file>
  got=$("$tmp/appinfo" --graphics "$3")
  case "$got" in "$2"*) pass=$((pass + 1)); printf 'PASS  %s (%s)\n' "$1" "$got" ;;
    *) fail=$((fail + 1)); printf 'FAIL  %s\n      want %s...\n      got  %s\n' "$1" "$2" "$got" ;; esac
}
# exe <bits> <name> <lib...>: a program that imports one function from each lib
exe() {
  bits=$1 name=$2; shift 2
  cc=x86_64-w64-mingw32-gcc; [ "$bits" = 32 ] && cc=i686-w64-mingw32-gcc
  printf '#include <windows.h>\nint main(void){ return (int)(INT_PTR)GetProcAddress(0, "x"); }\n' > "$tmp/m.c"
  for lib in "$@"; do
    case $lib in
      d3d11) printf '#include <d3d11.h>\nvoid u11(void){ D3D11CreateDevice(0,0,0,0,0,0,0,0,0,0); }\n' ;;
      d3d10) printf '#include <d3d10.h>\nvoid u10(void){ D3D10CreateDevice(0,0,0,0,0,0); }\n' ;;
      d3d9)  printf '#include <d3d9.h>\nvoid u9(void){ Direct3DCreate9(0); }\n' ;;
      opengl32) printf '#include <GL/gl.h>\nvoid ugl(void){ glFlush(); }\n' ;;
    esac >> "$tmp/m.c"
  done
  # shellcheck disable=SC2046 # one -l flag per lib
  $cc -o "$tmp/$name.exe" "$tmp/m.c" $(for lib in "$@"; do printf -- '-l%s ' "$lib"; done) || { echo "could not build $name"; exit 2; }
}
exe 64 d3d11 d3d11;          check "64-bit D3D11 -> D3DMetal" "d3dmetal imports d3d11.dll" "$tmp/d3d11.exe"
exe 32 d3d11-32 d3d11;       check "32-bit D3D11 -> D3DMetal" "d3dmetal imports d3d11.dll" "$tmp/d3d11-32.exe"
exe 64 d3d10 d3d10;          check "D3D10 only -> DXMT" "dxmt imports d3d10.dll" "$tmp/d3d10.exe"
exe 32 d3d9 d3d9;            check "D3D9 -> wined3d" "wined3d imports d3d9.dll" "$tmp/d3d9.exe"
exe 64 gl opengl32;          check "OpenGL -> wined3d" "wined3d imports opengl32.dll" "$tmp/gl.exe"
exe 64 both d3d9 d3d11;      check "D3D11 wins over D3D9" "d3dmetal imports d3d11.dll" "$tmp/both.exe"
exe 64 none;                 check "no graphics import -> default" "d3dmetal default" "$tmp/none.exe"
printf 'not a PE' > "$tmp/junk.exe"; check "not a PE -> default" "d3dmetal default" "$tmp/junk.exe"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
