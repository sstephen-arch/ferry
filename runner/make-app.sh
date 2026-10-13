#!/bin/sh
# shellcheck disable=SC1091
# make-app.sh: build the forked app (app/) with its payload, offline.
#
# Upstream's `make app` expects a NotProton bridge built in its own scratch tree and fetches
# Dobby and Sparkle from the network. Here: Dobby comes from ferry-cache, Sparkle is resolved from
# the SwiftPM cache before make runs, and the four bridge files come from dist/ferry-bridge-*.
# The newest dist/ferry-runner-* ships inside the app (Contents/Resources/ferry-runner.tar.gz), so a
# fresh install needs nothing else: the app unpacks, verifies and sets it up (BundledFerryRunner).
# FERRY_BUNDLE_RUNNER=0 leaves it out.
# Output: app/out/NotProton.app (bundle id local.ferry.app, display name Ferry).
set -e
. "$(dirname "$0")/lib.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO_ROOT/app"
bridge=$(find "$REPO_ROOT/dist" -maxdepth 1 -type d -name 'ferry-bridge-*' | sort -V | tail -1)
[ -n "$bridge" ] || die "no dist/ferry-bridge-* (run runner/package.sh)"
runner_archive=
if [ "${FERRY_BUNDLE_RUNNER:-1}" != 0 ]; then
  runner=$(find "$REPO_ROOT/dist" -maxdepth 1 -type d -name 'ferry-runner-*-rosetta' | sort -V | tail -1)
  [ -n "$runner" ] || die "no dist/ferry-runner-* to bundle (run runner/package.sh, or FERRY_BUNDLE_RUNNER=0)"
  runner_archive="$SCRATCH/$(basename "$runner").tar.gz"
  # packed once per runner build: a dist runner is never changed after package.sh writes it
  if [ ! -f "$runner_archive" ]; then
    printf 'packing %s into the app ...\n' "$(basename "$runner")"
    COPYFILE_DISABLE=1 tar -czf "$runner_archive.part" -C "$REPO_ROOT/dist" "$(basename "$runner")"
    mv "$runner_archive.part" "$runner_archive"
  fi
fi

# Dobby: upstream ignores vendor/dobby and pins a commit; ours is the cached tarball of that pin
if [ ! -f "$APP/vendor/dobby/CMakeLists.txt" ]; then
  [ -f "$FERRY_CACHE"/dobby-5dfc8546.tar.gz ] || die "missing $FERRY_CACHE/dobby-5dfc8546.tar.gz (ferry-cache)"
  mkdir -p "$APP/vendor/dobby"
  tar xzf "$FERRY_CACHE"/dobby-5dfc8546.tar.gz -C "$APP/vendor/dobby"
fi

# Sparkle: resolve into the package's own .build from the offline cache, so make's plain
# `swift build -c release` finds everything in place
( cd "$APP/app" && swift build -c release --disable-sandbox --skip-update \
    --cache-path "$FERRY_CACHE/swiftpm" >/dev/null )

PATH="$FERRY_CACHE/fontvenv/bin:$PATH"
export PATH
make -C "$APP" dobby
make -C "$APP" fonts
# Sign with a stable identity when one exists: macOS ties the App Management permission (needed
# to patch Steam.app) to the signature, and an ad-hoc signature changes on every build, so the
# permission would have to be granted again after each rebuild.
if [ -z "${FERRY_SIGN_ID:-}" ]; then
  FERRY_SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
fi
printf 'signing with: %s\n' "${FERRY_SIGN_ID:--}"
make -C "$APP" app APP_SIGN_ID="${FERRY_SIGN_ID:--}" FERRY_RUNNER_ARCHIVE="$runner_archive" BRIDGE_FILES="\
$bridge/steam.exe:steam.exe \
$bridge/x86_64-windows-lsteamclient.dll:x86_64-windows-lsteamclient.dll \
$bridge/x86_64-unix-lsteamclient.so:x86_64-unix-lsteamclient.so \
$bridge/i386-windows-lsteamclient.dll:i386-windows-lsteamclient.dll"
printf 'built %s\n' "$APP/out/NotProton.app"
