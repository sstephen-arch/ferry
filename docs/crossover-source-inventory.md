# CrossOver 26.3.0 source inventory

Pinned tarball: `crossover-sources-26.3.0.tar.gz`
Source: `media.codeweavers.com/pub/crossover/source/`
Bytes: 149,054,023  Sha256: `ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872`

Extracted to: `$SCRATCH/src/crossover-26.3.0/` (top-level dir is `sources/`).

## Top-level directories under `sources/`

| Directory | Size (approx.) | Notes |
|---|---|---|
| android | 112 K | Android target support |
| busybox | 15 M | BusyBox for Wine's user-mode Linux |
| cabextract | 1.6 M | CAB extraction utility |
| dxvk | 8.1 M | DXVK (Vulkan-based DX9/10/11) — meson build |
| freetype | 12 M | FreeType font renderer — autotools |
| ghostscript | 72 M | Ghostscript for PDF rendering |
| glib | 52 M | GLib dependency |
| gnutls | 104 M | GnuTLS for TLS |
| gstreamer | 192 M | GStreamer multimedia framework |
| htmltextview | 28 K | HTML text view for Wine |
| makedep | 84 K | Makefile dependency generator |
| moltenvk | 29 M | MoltenVK (Vulkan-for-Metal) — Xcode/Make |
| po4a | 4.1 M | i18n localization tooling |
| pyxdg | 44 K | Python XDG helper |
| vkd3d | 11 M | VKD3D (Vulkan-based DX12) — autotools |
| wine | 332 M | **Wine itself** |

Total: ~816 M (source only; not counting build output).

## Wine

- **Path:** `sources/wine/`
- **VERSION:** `Wine version 11.0`
- **Git describe:** not available — the tarball is a release archive, not a git working tree.
- **configure:** present (`sources/wine/configure`, autoconf-generated).
- **Key configure.ac observations:**
  - `*-darwin*` and `darwin*` branches exist — macOS is a first-class target.
  - macOS min version: `10.7` (`-mmacosx-version-min=10.7`).
  - Cross-compile requires `--with-wine-tools=DIR` (errors out otherwise).
  - PC/SC support links `-framework PCSC` on darwin.
  - D3DMetal hooks are wired in: `dlls/ntdll/unix/loader.c` reads env var
    `CX_APPLEGPTK_LIBD3DSHARED_PATH` and dlopen's the dylib on Sonoma+.
  - `cxcompatdb.so` is loaded from the ntdll directory at runtime if present
    (the directory itself is **not** shipped in the tarball).

## Components present (yes / no)

| Component | Present? | Notes |
|---|---|---|
| wine | yes | VERSION 11.0 |
| dxvk | yes | meson build, has `setup_dxvk.sh` |
| moltenvk | yes | Xcode project + `Makefile` |
| vkd3d | yes | autotools, has `autogen.sh` |
| freetype | yes | autotools, has `configure` |
| gnutls | yes | has `gmp` submodule |
| gstreamer | yes | meson build |
| sdl / SDL | **no** | No SDL directory in the tarball; Wine links against system SDL2 on macOS. |
| cxcompatdb | **no** | No `cxcompatdb/` directory in the tarball (expected absent). Source code in
  `dlls/ntdll/unix/loader.c` loads `cxcompatdb.so` at runtime if found alongside ntdll. |

## CodeWeavers build assumptions

- The Wine `configure.ac` assumes a **POSIX host** (Linux or macOS). No Cygwin/MSYS
  detection for the host toolchain; `darwin*` is explicitly handled.
- Cross-compiling (x86_64 macOS host targeting Windows PE) requires a separate
  Wine tools directory built for the host (`--with-wine-tools`). This is standard
  Wine cross-build practice.
- No CodeWeavers-specific build scripts (e.g. `setup-wine-tree.sh`, `cx-build.sh`)
  are present in the tarball. The Closed-source build glue (CX-specific config,
  compatibility DB management) lives outside this open-source tree.
- Sub-component builds (dxvk, moltenvk, vkd3d, freetype) use their own upstream
  build systems (meson, autotools, Xcode). None are orchestrated by a CW master
  script in this tarball.

## Why this matters for Ferry

- Wine 11.0 is the base runtime we compile ourselves (Phase 5+).
- D3DMetal integration points are already in the open source (`loader.c`), so
  Phase 9 only needs to place the user-supplied dylib where the env var points.
- dxvk / moltenvk / vkd3d are present and can be staged as builtins (Phase 9)
  if the gate probes require them.
- No SDL in the tarball means Phase 15 (FEX stretch) will need to fetch it
  separately if controller support is added.
- `cxcompatdb` absence is expected; Ferry drops the closed compatibility DB
  entirely (see Phase 0 "What Ferry is NOT").
