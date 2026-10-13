#!/bin/sh
# shellcheck disable=SC1091
# package.sh: copy the staged runner and the repo bridge into dist/ with a manifest.
#
#   dist/ferry-runner-<ver>-rosetta/CrossOver/   the runner root (what the app installs)
#   dist/ferry-runner-<ver>-rosetta/manifest.json
#   dist/ferry-bridge-<ver>/                     the four bridge files the app payload takes
#
# <ver> = 26.3.0-ferry.<n>, n = number of commits touching runner/ or patches/.
# The dist copy is local only: with D3DMetal installed it contains Apple's GPTK files, which
# must never be shared.
set -e
. "$(dirname "$0")/lib.sh"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$SCRATCH/stage/CrossOver"
BRIDGE="$SCRATCH/bridge"
DIST="$REPO_ROOT/dist"

[ -x "$STAGE/lib/wine/x86_64-unix/wine" ] || die "no staged runner (runner/stage.sh)"
for f in steam.exe x86_64-windows-lsteamclient.dll i386-windows-lsteamclient.dll x86_64-unix-lsteamclient.so; do
  [ -f "$BRIDGE/$f" ] || die "bridge is missing $f (runner/components.sh --build)"
done
sh "$REPO_ROOT/runner/verify-layout.sh" "$STAGE" >/dev/null || die "staged runner fails verify-layout"

n=$(git -C "$REPO_ROOT" rev-list --count HEAD -- runner patches)
ver="26.3.0-ferry.$n"
out="$DIST/ferry-runner-$ver-rosetta"
bout="$DIST/ferry-bridge-$ver"
rm -rf "$out" "$bout"
mkdir -p "$out" "$bout"
cp -R "$STAGE" "$out/CrossOver"
cp -R "$BRIDGE/." "$bout/"
xattr -r -d com.apple.quarantine "$out" "$bout" 2>/dev/null || true
xattr -r -d com.apple.provenance "$out" "$bout" 2>/dev/null || true

python3 - "$out" "$bout" "$ver" "$REPO_ROOT" <<'PY'
import datetime, hashlib, json, os, subprocess, sys
out, bout, ver, repo = sys.argv[1:5]
root = os.path.join(out, "CrossOver")
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
key_files = ["lib/wine/x86_64-windows/ntdll.dll", "lib/wine/i386-windows/ntdll.dll",
             "lib/wine/x86_64-unix/ntdll.so", "lib/wine/x86_64-unix/wine", "bin/wineserver",
             "lib/wine/x86_64-windows/lsteamclient.dll", "lib/wine/i386-windows/lsteamclient.dll",
             "lib/wine/x86_64-unix/lsteamclient.so", "lib/wine/x86_64-unix/win32u.so"]
# scripts the run script executes from the runner must be covered too
key_files += [p for p in ["share/ferry/backend.sh"] if os.path.isfile(os.path.join(root, p))]
series = open(os.path.join(repo, "patches/wine/series")).read().split()
version_file = os.path.join(os.environ["SRC"], "crossover-26.3.0/sources/wine/VERSION")
manifest = {
    "name": "Ferry",
    "version": ver,
    "flavor": "rosetta",
    "wine_version": open(version_file).read().strip().replace("Wine version ", ""),
    "built_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "git_commit": subprocess.run(["git", "-C", repo, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip(),
    "patches": [{"name": p, "sha256": sha(os.path.join(repo, "patches/wine", p))} for p in series],
    "files": {k: sha(os.path.join(root, k)) for k in key_files},
    "graphics": {"dxmt": os.path.isdir(os.path.join(root, "lib/dxmt")),
                 "d3dmetal": os.path.isfile(os.path.join(root, "lib64/apple_gptk/external/libd3dshared.dylib"))},
    "bridge": {f: sha(os.path.join(bout, f)) for f in sorted(os.listdir(bout))},
}
json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=1)
print("manifest:", ver, "graphics", manifest["graphics"])
PY
printf 'packaged %s and %s\n' "$out" "$bout"
