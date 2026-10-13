#!/bin/sh
# lib.sh — shared variables for runner build scripts.
#
# Each variable can be overridden from the environment.
# Source this file before using any of the helpers below.

set -e

# ---- paths ----------------------------------------------------------------
# Repo root: assumes this file lives at runner/lib.sh inside the Ferry repo.
REPO="$(cd "$(dirname "$0")/.." && pwd)"

: "${FERRY_CACHE:=$HOME/Developer/ferry-cache}"
: "${FERRY_SCRATCH:=$REPO/scratch}"
export SCRATCH="$FERRY_SCRATCH"
export SRC="$SCRATCH/src"

# ---- parallelism -----------------------------------------------------------
# hw.perflevel0.logicalcpu gives the performance-core count on Apple Silicon;
# fall back to hw.logicalcpu, then nproc.
# All cores (performance + efficiency); FERRY_JOBS overrides.
export JOBS="${FERRY_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)}"

# ---- PATH ------------------------------------------------------------------
# Brew-installed bison and flex may be needed by Wine autoreconf; put them
# first so the configure script picks them up over any macOS-shipped ones.
PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:$PATH"
export PATH

# ---- helpers ---------------------------------------------------------------
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}