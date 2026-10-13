#!/bin/sh
# shellcheck disable=SC1091
# build.sh — compile CrossOver's Wine x86_64 from the configured source tree.
#
# Usage: build.sh
# Exits non-zero on failure.
# Idempotent: make is re-run even if targets are up-to-date (fast).
#
# The parallelism variable $JOBS comes from runner/lib.sh.
# Build output is logged to scratch/logs/build.log.

set -e

. "$(dirname "$0")/lib.sh"

BUILD_DIR="$SCRATCH/build/wine-x86_64"
LOG_DIR="$SCRATCH/logs"

if [ ! -f "$BUILD_DIR/Makefile" ]; then
  die "build directory not configured: $BUILD_DIR (run runner/configure.sh first)"
fi

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/build.log"
printf 'building Wine x86_64 in %s (JOBS=%s) ...\n' "$BUILD_DIR" "$JOBS"
cd "$BUILD_DIR"
if make -j"$JOBS" >"$LOG" 2>&1; then
  printf 'build completed successfully\n'
else
  rc=$?
  printf 'build failed (exit %d); see %s\n' "$rc" "$LOG"
  exit "$rc"
fi