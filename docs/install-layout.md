# What `make install` produces (Phase 6)

`runner/stage.sh` runs `make install DESTDIR=scratch/stage-raw INSTALL=<wine-tools>/tools/install`
with `--prefix=/ferry`, so everything lands under `scratch/stage-raw/ferry/`:

| Installed path (under `/ferry`) | Contents |
|---|---|
| `bin/wineserver` | the server (Mach-O x86_64). There is no `bin/wine`: Wine 11 installs the loader under lib/ |
| `lib/wine/x86_64-unix/wine` | the unix loader the run script starts for Rosetta (`$CX_ROOT/lib/wine/x86_64-unix/wine`) |
| `lib/wine/x86_64-unix/*.so` | unix halves (ntdll.so, win32u.so, winemac.so, ...); win32u.so carries `LC_RPATH @loader_path/` |
| `lib/wine/x86_64-windows/` | ~1000 x86_64 PE builtins (ntdll.dll, kernel32.dll, ...) |
| `lib/wine/i386-windows/` | i386 PE builtins for 32-bit games under the new WoW64 |
| `share/wine/wine.inf` | prefix setup script used by `wineboot --init` |
| `share/wine/fonts/`, `share/wine/nls/` | Wine's own fonts and locale data |
| `share/wine/winmd/` | Windows metadata copied into new prefixes. **If missing, the first `wineboot` loops forever** in setupapi waiting for "media" (seen in Phase 6) |

No preloader exists on macOS (`wine-preloader` is Linux only).

`stage.sh` then copies `bin/ lib/ share/` (real copies, no symlinks into stage-raw) to
`scratch/stage/CrossOver/` and adds `lib/wine/x86_64-unix/libfreetype.6.dylib` (x86_64, install
name `@rpath/libfreetype.6.dylib`, the soname configure.sh pins for win32u.so).

Runtime notes for whoever launches this runner:
- `WINEVERTEMP=/tmp`: CrossOver's wineserver picks its socket directory from `$WINEVERTEMP`,
  else `$TMPDIR`, but ntdll's client always uses `/tmp`; with Steam's per-user `TMPDIR` they
  would never meet. `/tmp/.wine-<uid>` must be mode 0700.
- `WINEDLLOVERRIDES=mscoree=d;mshtml=d` for headless first boots (no Mono/Gecko prompt).
