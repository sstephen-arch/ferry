# Phase 14: hands-on test with real Steam (owner)

Everything up to here was tested without touching your real Steam or `~/Library`. This is the
first step that does: installing changes Steam the way NotProton does. Undo is step 6.

## Before you start

1. **Update Steam.** Your Steam is build `1785799196`. NotProton (pinned commit e054db0) only
   hooks builds `1788652215` and `1790121765`. Open Steam, let it update, quit it. If it updates
   past those builds, the hooks will not apply. Then `upstream/` needs a newer NotProton commit
   first (a separate, reviewed change).
2. Suspend the Parallels VM and quit anything heavy. The first game launch builds a Wine prefix.

## Install

```bash
cp -R ~/Developer/ferry/app/out/NotProton.app /Applications/Ferry.app
```

3. Open **Ferry**, then **Add Ferry runner…** and pick
   `~/Developer/ferry/dist/ferry-runner-26.3.0-ferry.13-rosetta` (the folder holding `manifest.json`).
   It should show as "Ferry 26.3.0-ferry.13" with no licence warning.
4. Run the app's install/set-up for that runner (it copies the runner to
   `~/Library/Application Support/notproton/runners/crossover-ferry-26.3.0-ferry.13`, installs the
   bridge and the Steam hook).
5. Start Steam, go to **Settings > Compatibility** and choose **Ferry 26.3.0-ferry.13 (Rosetta)**.

## Test ladder (stop at the first failure and note it below)

| # | Test | Graphics | Result |
|---|---|---|---|
| a | A free 2D / light DX9 game | default (wined3d) | **PASS 11 Oct**: Celeste 1.4.0.0 (Windows build) reaches the title screen; Steam API via lsteamclient; overlay injected |
| b | A free DX11 3D game | launch option `CX_GRAPHICS_BACKEND=dxmt %command%` | |
| c | Same game | `CX_GRAPHICS_BACKEND=d3dmetal %command%` | |
| d | A 32-bit game | dxmt or default (D3DMetal is 64-bit only) | |
| e | A game with Steam achievements (proves lsteamclient) | any | |
| f | Steam overlay (shift-tab) in game | any | |

Logs: `<library>/steamapps/compatdata/<appid>/notproton-run.log` per game, and
`~/Library/Application Support/notproton/launchers/<appid>/notproton-wine.log`.

Known on a first launch: Wine may offer to install **Wine Mono / Gecko**. Cancel is fine for
most games. (Upstream's run script forbids passing overrides into the prefix template, so
Ferry leaves that prompt alone.)

## 6. Remove (undo)

Ferry > **Remove everything** restores Steam to stock. Then delete `/Applications/Ferry.app`.
Check that Steam starts normally.

## Not in this build

- DXVK (Vulkan): choose D3DMetal or DXMT instead.
- FEX / arm64 runner: Rosetta only.
- Online/TLS inside games (GnuTLS not built). Steam itself is unaffected.

## Results

**11 Oct 2026, first live run (Claude driving, owner watching):** Steam 1788652215.
Celeste (app 504230), Windows depot 504231, forced to Ferry 26.3.0-ferry.13 via Steam's
CompatToolMapping: prefix built, `Celeste.exe` running under Ferry's wineserver, title screen
shown (owner confirmed). Fixes the live install needed (all committed, 501 Swift tests pass):
App Management permission; strip Finder metadata before re-signing Steam; stable signing
identity so the permission survives rebuilds; a missed licence-check call site; Rosetta-only
bridge manifest; no entitlement grant for an unsigned (non-hardened) loader; tool name must
start with `notproton` for the Steam hook to accept it.
Open: tests b-f (DX11 with DXMT/D3DMetal, 32-bit, achievements, overlay) not run yet; the run
log's "no patched ntdll for build ferry-..." line is expected for Ferry but misleading.

**11 Oct 2026, Ni no Kuni II (app 589360), D3D11 + SteamStub DRM:** title screen on
Ferry 26.3.0-ferry.18 with `CX_GRAPHICS_BACKEND=d3dmetal` (owner confirmed). It took two runner
fixes, each with a Wine-level test that fails on the old runner:
- **MoltenVK was never shipped.** win32u logged `Failed to load @rpath/libMoltenVK.dylib` and
  the game quit at startup. deps.sh now takes Khronos's prebuilt MoltenVK 1.4.2 (x86_64 half).
- **SteamStub DRM: "Application load error 3:0000065432".** The wrapper looks up an export of
  steamclient64.dll and refuses unless that address lies in steamclient64.dll. Patch 0001
  answered with lsteamclient's addresses; it now writes jumps into the real module's shared
  exports, as Proton's loader does (`probe.exe` reports this as `M=1`).
Switching a game to a new Ferry build needs Ferry > Prefixes > Rebuild Prefix (the run script
refuses a prefix built by another build). Celeste was rebuilt for ferry.18 too, not re-tested.

**12 Oct 2026, Lost Judgment (app 2058190), DX11 + AVX + online check:** plays on ferry.20 with
launch option `CX_GRAPHICS_BACKEND=d3dmetal ROSETTA_ADVERTISE_AVX=1 %command%` (owner confirmed).
- "The CPU in use does not support AVX": Rosetta runs AVX/AVX2 but only reports it with
  `ROSETTA_ADVERTISE_AVX=1`; the run script already forwards `ROSETTA_*`.
- "The server is not reachable": Wine logged "no schannel support". ferry.20 builds GMP, Nettle
  and GnuTLS (deps.sh); tests/wine/tls_probe.exe checks schannel, and a live WinHTTP request to
  https://www.apple.com returned 200.
- Heavy flicker and black blotches on wined3d (the default when no backend is set); D3DMetal fixed it.
- An unmapped game runs on the *first* Ferry tool Steam lists, so keep only one Ferry build
  installed (older ones were removed).
- Fresh-install path checked: with no runner set up, one Install hooked Steam, unpacked the
  bundled runner and created the Steam tool.
Ni no Kuni II on D3DMetal: no menu text; on DXMT not yet reported.
