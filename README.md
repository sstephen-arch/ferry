# Ferry

Ferry is a self-built Steam Play runner for macOS. It is a fork of
[NotProton](https://github.com/NotProtonNot/NotProton) that replaces CrossOver's
closed-source Wine runtime with a Wine runtime compiled from CodeWeavers' published
open-source CrossOver 26.3.0 sources.

> [!IMPORTANT]
> **This repo is source code only. You have to download several things yourself before you can build
> or use Ferry. Nothing here is a ready-to-run app.**
>
> 1. **Apple's Game Porting Toolkit (for D3DMetal).** Free, but you must download it yourself with an
>    Apple ID from [developer.apple.com/download](https://developer.apple.com/download/all/?q=game%20porting%20toolkit)
>    (tested with 4.0 beta 2). Apple's licence forbids redistributing it, so it is **not in this repo and never
>    will be**. Copy its `redist` folder to `$FERRY_CACHE/gptk/redist/`. Without it Ferry still builds, but
>    DirectX 12 games and the D3DMetal backend will not work (many modern DX11 games need it too, for example
>    Lost Judgment and Ni no Kuni II); you are left with DXMT and Wine's own wined3d.
> 2. **The build inputs:** CrossOver's open-source release, Proton, DXMT, NotProton and others. They are listed,
>    with download sources and sha256 sums, in [`docs/inputs.md`](docs/inputs.md). Put them in your
>    `$FERRY_CACHE` folder (default `~/Developer/ferry-cache`); the build never downloads anything itself.
> 3. **Tools and apps:** Steam for Mac, Rosetta 2, Xcode, and the Homebrew packages under
>    [Requirements](#requirements).
>
> There are no prebuilt releases: you build the Wine runner and the app on your own Mac.

## What it is

Ferry enables Steam Play on macOS by launching Windows games through a Wine runtime
that we compile ourselves, with the `lsteamclient` Steam redirect applied directly
in Wine's source (no binary patching of `ntdll.dll`). It ships DXMT for DX10/DX11
graphics and optionally D3DMetal (from Apple's Game Porting Toolkit) for DX11/DX12.

## What Ferry is NOT

- A product or a binary download. This repo is source only, shared as-is under GPLv3 for anyone
  who wants to build it themselves. No builds, Wine binaries or Apple files are distributed here.
- Ferry is **not affiliated with** Valve, CodeWeavers, or Apple. All trademarks
  belong to their respective owners.
- Ferry does not require a paid CrossOver licence. It never touches CrossOver.app.
- Apple's D3DMetal licence forbids redistribution, so GPTK files are imported from
  the user's own download and are gitignored.

## MVP scope

The minimum viable product supports **Rosetta (x86_64) runners only**, covering
both 64-bit and 32-bit games via Wine's WoW64 subsystem. Graphics are provided
via D3DMetal (DX11/DX12) and DXMT (DX10/DX11).

FEX / native arm64 support is planned as stretch work after the MVP is proven.

## How it was built

Ferry started as a test of local AI models doing real work: phases 1-5 were written by local
models (KAT-Coder writer, gpt-oss reviewer) in an automated loop with deterministic gates.
Phase 6 (first Wine boot) blocked on Wine environment problems, and Claude finished the
remaining phases. `docs/decisions.md` records the decisions made along the way.

## Status

Tested on an Apple Silicon Mac (Rosetta runner) with real Steam:

| Game | Result |
|---|---|
| Celeste (Windows build) | Reaches the title screen |
| Ni no Kuni II | Reaches the title screen (D3DMetal: menu text missing) |
| Lost Judgment | Plays (D3DMetal, AVX advertised, online check over GnuTLS) |

Details and known issues: `docs/integration.md`.

## Build it

```sh
sh runner/build-all.sh     # Wine runner + bridge + graphics -> dist/
sh runner/make-app.sh      # the app -> app/out/NotProton.app (bundle id local.ferry.app)
sh tests/wine/run.sh       # Wine-level tests on the staged runner (or pass dist/.../CrossOver)
```

Run `tests/wine/run.sh` after any change to `patches/wine/` or a new CrossOver source drop: it
checks Wine boots (64/32-bit), the steamclient redirect behaves like NotProton's detour, and
each graphics backend creates a D3D11 device. The app's own tests: `swift test` in `app/app`.

Inputs come from a local cache folder, `$FERRY_CACHE` (default `~/Developer/ferry-cache`); the files
and their sha256 sums are listed in `docs/inputs.md`. Nothing downloads
during a build. Then follow `docs/integration.md` to install and test with real Steam.

## What is in the runner

| Piece | Source |
|---|---|
| Wine 11.0 | CrossOver 26.3.0 open source + `patches/wine/` (0001 steamclient redirect, 0002 `FERRY_DLLPATH_FIRST`) |
| lsteamclient + steam.exe (bridge) | Valve Proton sources via NotProton's scripts, built in a stock Wine 11.15 tree |
| DXMT v0.80 | release builtins (LGPL-2.1+) |
| D3DMetal | your own GPTK download, never committed |
| freetype | CrossOver's source tarball, x86_64 |

Docs: `docs/runner-layout.md`, `docs/install-layout.md`, `docs/graphics-layout.md`,
`docs/decisions.md`, `docs/integration.md`.

## Requirements

- macOS with Rosetta (x86_64 games).
- **Your own Game Porting Toolkit download** for D3DMetal (into `$FERRY_CACHE/gptk/redist/`), from
  developer.apple.com with an Apple ID. Apple's licence forbids redistribution, so it is never in this repo.
- **The build inputs in [`docs/inputs.md`](docs/inputs.md)**, placed in `$FERRY_CACHE`.
- Steam for Mac and Xcode.
- brew: `mingw-w64 autoconf automake libtool bison flex shellcheck meson ninja cmake fontforge gpatch`;
  a Python venv with `afdko<5` and `fonttools` (`$FERRY_CACHE/fontvenv`) for the font build.

## Licensing

The repo is GPLv3 (copied from NotProton). Wine sources and DXMT are LGPL-2.1+. See
`LICENSE` and `NOTICE` for full details.
