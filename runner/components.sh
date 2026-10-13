#!/bin/sh
# shellcheck disable=SC1091
# components.sh: lsteamclient + the steam.exe shim (the Steam "bridge").
#
#   components.sh --sync    prepare the components tree (copy, register, place sources)
#   components.sh --build   configure + build it, then copy the results into the stage and the
#                           repo bridge scratch/bridge/
#
# Like upstream NotProton (Makefile `bridge` target, bridge/setup-wine-tree.sh), the components
# are built in their OWN stock Wine 11.15 tree, not in the runner's CrossOver 11.0 tree:
# CrossOver's Wine 11.0 build system has no C++ support (no CXX_PE_LIBS, makedep ignores .cpp),
# which steam.exe needs. The PE halves are self-contained and the unix half resolves ntdll
# symbols at load time (-undefined dynamic_lookup), which is how NotProton ships these same
# files against CrossOver's runtime.
#
# Inputs (all from ~/Developer/ferry-cache, hash-checked in Phase 0; no network):
#   wine-11.15/ (commit 2df1ee28, upstream's pin), lsteamclient-tree/, proton-lsc/,
#   steam-shim-headers-out/. Upstream sources are read from upstream/notproton, never written.
set -e
. "$(dirname "$0")/lib.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UP="$REPO_ROOT/upstream/notproton"
WINE_PIN=2df1ee28039cf84776eb1421ed90bd154cebb65f
CWINE_CACHE="$FERRY_CACHE/wine-11.15"
CWINE_SRC="$SRC/wine-11.15-components"
CWINE_BUILD="$SCRATCH/build/wine-11.15-components"
STAGE="$SCRATCH/stage/CrossOver"
BRIDGE="$SCRATCH/bridge"
LSC_TREE="$FERRY_CACHE/lsteamclient-tree"
SHIM_HEADERS="$FERRY_CACHE/steam-shim-headers-out"

for d in "$CWINE_CACHE" "$LSC_TREE" "$SHIM_HEADERS"; do
  [ -d "$d" ] || die "missing $d (Phase 0 pre-fetch)"
done

sync_tree() {
  head=$(git -C "$CWINE_CACHE" rev-parse HEAD)
  [ "$head" = "$WINE_PIN" ] || die "ferry-cache/wine-11.15 is at $head, expected $WINE_PIN"
  if [ ! -f "$CWINE_SRC/.ferry-registered" ]; then
    rm -rf "$CWINE_SRC"
    mkdir -p "$(dirname "$CWINE_SRC")"
    cp -Rc "$CWINE_CACHE" "$CWINE_SRC" 2>/dev/null || cp -R "$CWINE_CACHE" "$CWINE_SRC"
    ( cd "$CWINE_SRC" && git apply "$UP/bridge/register-components.diff" ) \
      || die "upstream register-components.diff did not apply to wine-11.15"
    : > "$CWINE_SRC/.ferry-registered"
  fi
  # whole trees: makedep reads every SOURCES file a Makefile.in lists
  mkdir -p "$CWINE_SRC/dlls/lsteamclient" "$CWINE_SRC/programs/steam.exe/proton-headers"
  rsync -a --delete "$LSC_TREE/" "$CWINE_SRC/dlls/lsteamclient/"
  rsync -a --exclude build.sh --exclude gen-implib.sh --exclude fetch-headers.sh \
    --exclude proton-headers "$UP/steam-shim/" "$CWINE_SRC/programs/steam.exe/"
  rsync -a --delete "$SHIM_HEADERS/" "$CWINE_SRC/programs/steam.exe/proton-headers/"
  printf 'components tree ready at %s\n' "$CWINE_SRC"
}

build_components() {
  sync_tree
  [ -d "$STAGE" ] || die "stage the runner first (runner/stage.sh)"

  # configure exactly as upstream bridge/setup-wine-tree.sh does (rosetta / x86_64 host)
  if [ ! -f "$CWINE_BUILD/Makefile" ]; then
    mkdir -p "$CWINE_BUILD"
    ( cd "$CWINE_BUILD" && "$CWINE_SRC/configure" --enable-archs=i386,x86_64 \
        --without-freetype --without-x --host=x86_64-apple-darwin \
        CC="clang -arch x86_64" CXX="clang++ -arch x86_64" ) > "$SCRATCH/logs/components-configure.log" 2>&1 \
      || { tail -20 "$SCRATCH/logs/components-configure.log"; die "components configure failed"; }
  fi
  grep -q '^host_cpu = x86_64' "$CWINE_BUILD/config.status" \
    || die "components configure did not take the x86_64 host"

  # lsteamclient's unix half links against this tree's ntdll.so
  if [ ! -f "$CWINE_BUILD/dlls/ntdll/ntdll.so" ]; then
    make -C "$CWINE_BUILD" -j"$JOBS" dlls/ntdll/ntdll.so > "$SCRATCH/logs/components-ntdll.log" 2>&1 \
      || { tail -20 "$SCRATCH/logs/components-ntdll.log"; die "building ntdll.so for the components failed"; }
  fi

  wine_src_rel=$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$CWINE_SRC" "$CWINE_BUILD")

  # lsteamclient: upstream's script (PE halves via make, unix half by hand, size/sign checks).
  # TREE/WORK point at the cached Proton tree so its fetch.sh only verifies; CX_ROOT points
  # nowhere so it can never touch a real NotProton runner.
  WINE_BUILD="$CWINE_BUILD" WINE_SRC_REL="$wine_src_rel" UNIX_ARCH=x86_64 \
  TREE="$LSC_TREE" WORK="$FERRY_CACHE/proton-lsc" CX_ROOT=/nonexistent/ferry \
    bash "$UP/lsteamclient/build.sh"

  # steam.exe: upstream's build.sh would write generated headers into upstream/, so its make
  # step is run here (sources were placed by sync_tree). x86_64 only, as upstream ships.
  make -C "$CWINE_BUILD" -j"$JOBS" programs/steam.exe/x86_64-windows/steam.exe > "$SCRATCH/logs/components-steam.log" 2>&1 \
    || { tail -20 "$SCRATCH/logs/components-steam.log"; die "building steam.exe failed"; }
  shim="$CWINE_BUILD/programs/steam.exe/x86_64-windows/steam.exe"
  size=$(stat -f %z "$shim")
  [ "$size" -gt 1000000 ] || die "steam.exe is only $size bytes, the link dropped objects"

  lsc="$CWINE_BUILD/dlls/lsteamclient"
  # into the runner as builtins; the x86_64 unix half must stay unsigned (Wine refuses signed builtins)
  cp -f "$lsc/x86_64-windows/lsteamclient.dll" "$STAGE/lib/wine/x86_64-windows/lsteamclient.dll"
  cp -f "$lsc/i386-windows/lsteamclient.dll" "$STAGE/lib/wine/i386-windows/lsteamclient.dll"
  cp -f "$lsc/lsteamclient.so" "$STAGE/lib/wine/x86_64-unix/lsteamclient.so"
  codesign --remove-signature "$STAGE/lib/wine/x86_64-unix/lsteamclient.so" 2>/dev/null || true

  # repo bridge: the four files we build, named as upstream's Makefile BRIDGE_FILES names them
  rm -rf "$BRIDGE"
  mkdir -p "$BRIDGE"
  cp -f "$shim" "$BRIDGE/steam.exe"
  cp -f "$lsc/x86_64-windows/lsteamclient.dll" "$BRIDGE/x86_64-windows-lsteamclient.dll"
  cp -f "$lsc/i386-windows/lsteamclient.dll" "$BRIDGE/i386-windows-lsteamclient.dll"
  cp -f "$lsc/lsteamclient.so" "$BRIDGE/x86_64-unix-lsteamclient.so"
  codesign --remove-signature "$BRIDGE/x86_64-unix-lsteamclient.so" 2>/dev/null || true
  printf 'built components; bridge at %s\n' "$BRIDGE"
}

case "${1:-}" in
  --sync) sync_tree ;;
  --build) build_components ;;
  *) die "usage: components.sh --sync | --build" ;;
esac
