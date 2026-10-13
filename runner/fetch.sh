#!/bin/sh
# shellcheck disable=SC1091
# fetch.sh — verify and extract the CrossOver 26.3.0 source tarball.
#
# Usage: fetch.sh
# Exits non-zero on sha256 mismatch (even if the tree was already extracted).
# Extracts idempotently: skips if the marker file is present.

set -e

. "$(dirname "$0")/lib.sh"

TARBALL="$FERRY_CACHE/crossover-sources-26.3.0.tar.gz"
EXTRACT_DIR="$SRC/crossover-26.3.0"
MARKER="$EXTRACT_DIR/.extracted"

# ---- verify tarball --------------------------------------------------------
if [ ! -f "$TARBALL" ]; then
  die "tarball not found: $TARBALL"
fi

# Read the expected sha256 from cache.lock (skip comment and directory lines).
EXPECTED_HASH=$(awk '/^#|^$/ { next } $1 == "crossover-sources-26.3.0.tar.gz" { print $3; exit }' \
  "$FERRY_CACHE/cache.lock")
if [ -z "$EXPECTED_HASH" ]; then
  die "crossover-sources-26.3.0.tar.gz not listed in cache.lock"
fi

ACTUAL_HASH=$(sha256sum "$TARBALL" | awk '{ print $1 }')
if [ "$ACTUAL_HASH" != "$EXPECTED_HASH" ]; then
  die "sha256 mismatch for $TARBALL: expected $EXPECTED_HASH, got $ACTUAL_HASH"
fi

# ---- extract (idempotent) --------------------------------------------------
mkdir -p "$EXTRACT_DIR"

if [ -f "$MARKER" ] && [ -f "$EXTRACT_DIR/sources/wine/configure" ]; then
  printf 'already extracted: %s\n' "$EXTRACT_DIR"
  exit 0
fi

printf 'extracting crossover-sources-26.3.0.tar.gz -> %s\n' "$EXTRACT_DIR"
if ! tar xzf "$TARBALL" -C "$EXTRACT_DIR"; then
  die "failed to extract $TARBALL"
fi

# The tarball's top-level directory is "sources/"; Wine ends up at
# $EXTRACT_DIR/sources/wine.  Touch the marker so future runs skip.
touch "$MARKER"
printf 'extracted ok\n'
