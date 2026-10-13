#!/bin/sh
# build-all.sh: the whole runner from the cached sources, in order. Each step is idempotent
# (skips what is current); a log per step goes to scratch/logs/all-<step>.log.
#
#   build-all.sh     fetch, deps, configure, build, stage, components, graphics, package
# shellcheck disable=SC1091
set -e
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
mkdir -p "$SCRATCH/logs"

run() {
  name=$1; shift
  printf '==> %s\n' "$name"
  if ! "$@" > "$SCRATCH/logs/all-$name.log" 2>&1; then
    tail -20 "$SCRATCH/logs/all-$name.log"
    die "step $name failed, see $SCRATCH/logs/all-$name.log"
  fi
}

run fetch sh "$here/fetch.sh"
run deps sh "$here/deps.sh"
run configure sh "$here/configure.sh"
run build sh "$here/build.sh"
run stage sh "$here/stage.sh"
run components-sync sh "$here/components.sh" --sync
run components-build sh "$here/components.sh" --build
run dxmt sh "$here/graphics.sh" --dxmt
if [ -f "$FERRY_CACHE/gptk/redist/lib/external/libd3dshared.dylib" ]; then
  run d3dmetal sh "$here/graphics.sh" --d3dmetal
else
  printf '==> d3dmetal skipped (no GPTK in %s/gptk/redist)\n' "$FERRY_CACHE"
fi
run package sh "$here/package.sh"
printf 'done: see %s/dist\n' "$(dirname "$SCRATCH")"
