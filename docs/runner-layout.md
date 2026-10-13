# Ferry runner directory layout

The runner root is the directory passed to `runner/verify-layout.sh`.  Its
immediate children are laid out so that NotProton's `compat_run.sh` and the
forked app's `RunnerInstaller` / `CrossOverSource` can find them without any
knowledge of the Ferry build system.  The root convention is:

```
<runner>/CrossOver/          ← the layout contract applies under this path
  bin/
    wineserver               REQUIRED — Wine process server
    wineserver-arm64         OPTIONAL — FEX/arm64 wineserver (phase 15+)
  lib/
    wine/
      x86_64-unix/
        wine                 REQUIRED — Rosetta loader (must be executable)
      x86_64-windows/
        ntdll.dll            REQUIRED — 64-bit Windows ntdll
        ...                  (other 64-bit PE DLLs)
      i386-windows/
        ntdll.dll            REQUIRED — 32-bit Windows ntdll
        ...                  (other 32-bit PE DLLs)
      aarch64-unix/          OPTIONAL — FEX/arm64 Wine loader dir (phase 15+)
    apple_gptk/              OPTIONAL — D3DMetal runtime (phase 9, user-supplied)
  share/
    wine/
      wine.inf               REQUIRED — Wine version / install metadata
      fonts/                 REQUIRED — TrueType font directory
```

## REQUIRED paths

| Path                                         | Used by                                       | File:line in upstream compat_run.sh |
|----------------------------------------------|-----------------------------------------------|--------------------------------------|
| `bin/wineserver`                             | `$WINESERVER` for `-k`/`-w` and template build | line 51, 479, 480, 523, 524, 579, 817, 818, 1425, 1426 |
| `lib/wine/x86_64-unix/wine`                  | `$WINELOADER` for Rosetta; entry point for games | line 49-50, 469, 472, 576, 1133, 1138, 1304, 1327 |
| `lib/wine/x86_64-windows/ntdll.dll`          | Bridge verify (`verify_runner`, line 953); PE export checks | line 953 |
| `lib/wine/i386-windows/ntdll.dll`            | Bridge verify (`verify_runner`, line 953)       | line 953 |
| `lib/wine/x86_64-windows/` (directory)       | `WINEDLLPATH` prefix                           | line 62, 513 |
| `lib/wine/i386-windows/` (directory)         | Bridge verify (`verify_runner`, line 961)       | line 961 |
| `share/wine/wine.inf`                        | `last_wine_build` mtime comparison; template identity | line 170, 173, 713 |
| `share/wine/fonts/` (directory)              | `link_fonts` symlinks into prefix               | line 887 |

**App-side checks** (from `upstream/notproton/app/Sources/NotProtonApp/Model/`):

| Path                                            | Used by                          | File:line   |
|-------------------------------------------------|----------------------------------|-------------|
| `lib/wine/x86_64-unix/wine`                     | `CrossOverSource.unixLoader()`   | line 151    |
| `lib/wine/<arch>/ntdll.dll` for each WineArch    | `NtdllPatcher.cleanSource()`     | line 569-570|
| `lib/wine/` (directory existence)               | `RunnerInstaller.hasClone()`     | line 238    |

## OPTIONAL paths

| Path                                         | Used by                                       | Condition                        |
|----------------------------------------------|-----------------------------------------------|----------------------------------|
| `lib64/apple_gptk/external/libd3dshared.dylib` | `compat_run.sh` sets `CX_APPLEGPTK_LIBD3DSHARED_PATH` | Present when owner supplies GPTK (Phase 9) |
| `bin/wineserver-arm64`                       | `$WINESERVER` when `np_flavor != rosetta` and loader exists | FEX/arm64 runner (Phase 15+)     |
| `lib/wine/aarch64-unix/`                     | `$WINELOADER` when `np_flavor != rosetta`      | FEX/arm64 runner (Phase 15+)     |

## Design notes

- **`CrossOver/` is kept as the directory name.**  `compat_run.sh` hard-codes
  `runners/crossover-$build/CrossOver` (line 38).  Renaming would require
  patching every `crossover-` occurrence in the run script — that is the work
  of Phase 12.
- **`ntdll.dll` is required for both PE architectures** because the bridge
  verifier (`verify_runner`, lines 951-959) compares the staged bridge copies
  against the live files in the runner.  Even though Ferry patches ntdll in
  source (Phase 7), both `x86_64-windows` and `i386-windows` copies must be
  present.
- **Optional paths must not be checked by `verify-layout.sh` as failures.**
  They are documented here and tracked by the script for informational output
  (`--json` mode) only.
