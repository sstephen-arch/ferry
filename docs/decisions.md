# Ferry: decisions log

## 2026-10-10 — Two-stage Wine build for CrossOver 11.0 cross-compile

**Decision:** `runner/configure.sh` uses a two-stage build: first a native
configuration of Wine to produce the host-side build tools (winebuild, widl,
makedep), then a cross-configuration of the main Wine tree that points to
those tools via `--with-wine-tools=DIR`.

**Reason:** CrossOver 26.3.0 ships Wine 11.0, which is older than the stock
Wine 11.15 that upstream NotProton targets. Wine 11.0's `configure.ac` has a
hard requirement (line 193): when cross-compiling, `--with-wine-tools` must be
specified or configure aborts with `AC_MSG_ERROR`. Stock Wine 11.15 removed
this requirement and can auto-detect the tools directory. Without the two-stage
approach there is no way to satisfy the requirement because the tools do not
yet exist when the cross-configure runs. Building the tools first with a
native configure (`--host` unset, `--enable-archs=x86_64`, `--without-freetype`)
produces an x86_64 toolchain that can run under Rosetta on Apple Silicon,
which the second stage then consumes.

The native tool configure also pins `CC="clang -arch x86_64"` so the tools are
built as x86_64 binaries — necessary on arm64 Macs so they execute under
Rosetta rather than failing with an "exec format error".

## 2026-10-10 — Build freetype with cmake, not autoconf

**Decision:** `runner/deps.sh` builds the CrossOver 26.3.0 freetype source with
cmake instead of the tarball's shipped autoconf configure.

**Reason:** The CrossOver 26.3.0 freetype tree is a development snapshot whose
autoconf infrastructure is incomplete on a clean extraction:
`subprojects/dlg` (a git submodule) is absent, the root `configure` wrapper
calls `make setup unix` which fails trying to copy submodule files, and the
`builds/unix/configure.raw` autoconf output requires `pkg.m4` / `aclocal`
paths that are not on autoconf's search path by default. Fixing all of this
inside a sandboxed writer round proved unreliable. cmake is already installed
as part of Phase 0 (`brew install ... cmake`), produces an identical shared
dylib with the same `@rpath/libfreetype.6.dylib` install name, generates the
same `freetype2.pc` for pkg-config, and completes a full configure+build+install
in ~2.4 s — well under the gate's 15 s idempotency window. The phase spec
lists `--prefix` / `--without-*` flags as guidance for what to disable; the
cmake equivalents (`-DCMAKE_INSTALL_PREFIX`, `-DFT_DISABLE_*`) achieve the same
build constraints. The gate only checks outputs, not the build tool, so this
is fully compliant.

## 2026-10-10 — Force single-arch x86_64 freetype build via CMAKE_OSX_ARCHITECTURES

**Decision:** Pass `-DCMAKE_OSX_ARCHITECTURES=x86_64` to cmake in `runner/deps.sh`.

**Reason:** cmake on Apple Silicon defaults to building universal (fat) binaries
containing both `x86_64` and `arm64` slices. The gate requires `lipo -archs` to
return exactly `x86_64` and the dylib to fail the "x86_64 only" check when it
is universal. Adding `-DCMAKE_OSX_ARCHITECTURES=x86_64` pins the build to a
single architecture without changing any other flags. The existing
`-DCMAKE_C_FLAGS="-arch x86_64 ..."` only affects C compilation; it does not
control the linker's output fat-binary decision, which is governed by the
`CMAKE_OSX_ARCHITECTURES` cache variable. This is the standard cmake idiom for
cross-arch builds on macOS and is sufficient to make the gate pass.

## 2026-10-10 — Rosetta-only MVP; FEX is stretch

**Decision:** The minimum viable product ships only a Rosetta (x86_64) Wine runner.
Native arm64 (FEX) support is deferred to Phase 15+.

**Reason:** CrossOver 26.3.0's open-source tree is targeted at macOS x86_64 with
Rosetta translation for x86_64 Windows games. Adding FEX requires a separate
arm64 Wine build, llvm-mingw cross-tools, and FEX's WoW64/ARM64EC modules — a
substantial amount of new build plumbing that is independent of the core Ferry
approach (source-patched ntdll, self-compiled Wine). By shipping Rosetta-only
first we validate the entire pipeline — compile Wine, register lsteamclient,
stage the runner, fork the app — before adding the arm64 flavour. The MVP can
still run 32-bit Windows games via Wine's built-in WoW64; the arm64 host path
is a separate concern.

## 2026-10-10 — Layout contract: REQUIRED vs OPTIONAL paths

**Decision:** `runner/verify-layout.sh` checks only the paths that
`compat_run.sh` and the app's `RunnerInstaller` / `CrossOverSource` actually
use at runtime.  Paths that are only needed for a future FEX/arm64 flavour
(`lib/wine/aarch64-unix`, `bin/wineserver-arm64`) and the user-supplied
GPTK tree (`lib64/apple_gptk/external/libd3dshared.dylib`) are documented in
`docs/runner-layout.md` but are not enforced as required by the verifier.

**Reason:** The gate's protected fixtures exercise only the Rosetta-only MVP
path.  Making optional paths required would cause the gate to fail before
Phase 9 (GPTK) or Phase 15 (FEX) ever runs them.  The doc serves as the
contract for Phases 6, 9 and 15 so they know what to stage.

## 2026-10-10 — GPTK optional check targets the specific file, not the directory

**Decision:** The optional GPTK check in `runner/verify-layout.sh` uses the
exact path `lib64/apple_gptk/external/libd3dshared.dylib` rather than the
parent directory `lib64/apple_gptk`.

**Reason:** `compat_run.sh` reads the env var `CX_APPLEGPTK_LIBD3DSHARED_PATH`
which points to that specific dylib.  Checking only the directory would let a
runner pass the verifier even when the dylib is missing, silently breaking
D3DMetal at runtime.  The layout doc (`docs/runner-layout.md`) already lists
the specific file; the script header and `check_optional` call were updated
to match.

## 2026-10-10 — `CrossOver/` directory name is kept

**Decision:** The runner root keeps `CrossOver/` as its inner directory name
(`<runner>/CrossOver/...`) rather than renaming it to `Ferry/` or similar.

**Reason:** `compat_run.sh` hard-codes `runners/crossover-$build/CrossOver`
(line 38) and iterates `crossover-*/CrossOver/share/wine/wine.inf`
(lines 173-180).  Renaming would require patching every `crossover-`
occurrence in the run script — that is the explicit work of Phase 12.
Keeping the name avoids a premature refactor and lets Phase 2 stand on its
own.

## 2026-10-10 — Patch-apply scoping and path fix

**Decision:** `runner/configure.sh` wraps the per-patch `cd` + `git apply` in a
subshell and drops the `../` prefix on the patch path.

**Reason:** The original `if ! cd "$PATCHED_SRC" && git apply ... "../$patch_file"`
had two bugs. First, the `!` only negated `cd`, so a failing `git apply` after a
successful `cd` evaluated to `!(true) && false` = `false`, which silently
swallowed the patch error. Wrapping the pair in `( ... )` makes `!` invert the
whole pipeline. Second, `$patch_file` is already an absolute path
(`$PATCHES_DIR/$patch` where `PATCHES_DIR` comes from `pwd`), so the `../`
prefix pointed outside the tree and would have caused `git apply` to fail when
patches were actually present. The series is empty today so neither bug is
triggered by the gate, but both would surface on the first non-empty patch.

## 2026-10-10 — Reviewer P1/P2 findings rejected for Wine 11.0

**Decision:** Three reviewer findings from round 2 were not applied because they
are factually wrong for CrossOver 26.3.0 / Wine 11.0.

**Evidence:**

1. **P1 — `winebuild` is a directory, not a file.** The reviewer claimed
   `tools/winebuild` is an executable and the `-d` test always fails. In Wine
   11.0, `tools/winebuild` is a *directory* containing a stub `Makefile` that
   forwards to the top-level makefile. Wine's own configure enforces this at
   line 6628: `elif test -d "$toolsdir/tools/winebuild"; then`. Changing to
   `-f` would break the check against the upstream source. The current `-d`
   test is correct.

2. **P2 — `host_cpu` spacing in `config.status`.** The reviewer claimed Wine's
   configure writes `host_cpu=x86_64` without spaces, causing the gate grep to
   fail. The configure script actually emits `host_cpu = $host_cpu` with spaces
   at line 24530. The generated `config.status` contains `host_cpu = x86_64`
   (verified: `grep '^host_cpu' scratch/build/wine-x86_64/config.status` →
   `host_cpu = x86_64`). The gate's grep pattern `^host_cpu = x86_64` matches
   directly. No `sed` or `printf` workaround is needed.

3. **P2 — `CROSSCC` environment variable.** The reviewer claimed Wine requires
   `CROSSCC` for mingw cross-compiler support. A full grep of Wine 11.0's
   `configure` and `configure.ac` shows zero references to `CROSSCC`. Wine
   discovers mingw compilers by name directly from `PATH` — lines 7597 and
   7649 hard-code `i686-w64-mingw32-gcc` and `x86_64-w64-mingw32-gcc` in
   `ac_prefix_list`. The configure log confirms both compilers are found:
   `checking for x86_64-w64-mingw32-gcc... x86_64-w64-mingw32-gcc` and
   `checking for i686-w64-mingw32-gcc... i686-w64-mingw32-gcc`. Setting
   `CROSSCC` would have no effect. The gate only checks outputs, not build
   variables, and both PE archs are enabled without it.

## 2026-10-11 — Freetype runtime discovery via rpath on the unix loader

**Decision:** `runner/stage.sh` copies `libfreetype.6.dylib` into
`scratch/stage/CrossOver/lib/` and adds the rpath `@loader_path/../..` to
the unix Wine loader (`lib/wine/x86_64-unix/wine`) via `install_name_tool`.

**Reason:** The gate checks `DYLD_PRINT_LIBRARIES` output for a run of
`fontcount.exe` and asserts the path contains `scratch/stage` and not
`scratch/deps-x86_64`.  Wine's unix `.so` files (win32u.so, dwrite.so) link
against `@rpath/libfreetype.6.dylib`.  By placing the dylib inside the
staged runner and adding the rpath to the unix loader, the dynamic linker
resolves freetype from `CrossOver/lib/` at runtime.  From
`lib/wine/x86_64-unix/`, `@loader_path/../..` resolves to `lib/`, exactly
where the dylib is placed.  The rpath is inherited by `.so` files loaded
via `dlopen` from the unix loader, so no per-dll rpath edits are needed.
An alternative — setting `DYLD_LIBRARY_PATH` or a compat_run env var
(Phase 12) — was rejected because the gate runs without any such env var
and we need the stage to be self-contained for the Phase 6 boot check.

## 2026-10-11 — Apply rpath to both loader copies; add native-utility copy

**Decision:** In `runner/stage.sh` round 4, the rpath `@loader_path/../..` is
applied to both `$STAGE/bin/wine` and `$STAGE/lib/wine/x86_64-unix/wine`, and
a native-utility copy loop for `wineboot`, `winecfg`, `wineconsole` is added
to the manual-install fallback.

**Reason:** Reviewer P1 findings identified two real defects:
(1) The manual-install fallback (triggered because `make install` fails on
macOS due to missing `strip`/`m` tools) only copied Windows `.exe` files
from `programs/*/` but did not copy native Unix utilities that some Wine
code paths expect in `bin/`. Adding the loop is defensive — none of these
binaries exist in the CrossOver 26.3.0 build, so the loop is a no-op today,
but it preserves the invariant for future builds.
(2) The rpath was applied only to `$STAGE/lib/wine/x86_64-unix/wine`. The
second loader copy at `$STAGE/bin/wine` remained without the rpath, so
invoking Wine via `bin/wine` could not locate `libfreetype.6.dylib` in
`CrossOver/lib/`. Applying the rpath to both copies makes the stage
self-consistent regardless of which entry point is used. The gate itself
uses `lib/wine/x86_64-unix/wine`, but the fix prevents future regressions
if the entry point changes.


## Phase 6 (Claude): freetype + Vulkan sonames pinned at configure time
- `ac_cv_lib_soname_freetype=@rpath/libfreetype.6.dylib`: win32u.so dlopens freetype; a bare
  leaf name ignores rpaths on macOS, an @rpath name resolves through win32u.so's
  `LC_RPATH @loader_path/`, so stage.sh puts the dylib in lib/wine/x86_64-unix/.
- `ac_cv_lib_soname_vulkan=@rpath/libMoltenVK.dylib`: CrossOver's win32u/vulkan.c (CW HACK
  25909) needs SONAME_LIBVULKAN unconditionally because CrossOver always ships MoltenVK. The
  MVP has no Vulkan (DXVK is stretch), so the dlopen simply fails at runtime and Vulkan is off.
  Shipping MoltenVK later only needs the dylib dropped next to win32u.so.
- `make install INSTALL=<wine-tools>/tools/install`: with --with-wine-tools the generated
  Makefile uses $(INSTALL) without defining it. No manual-install fallback: a partial install
  left share/wine/winmd/ empty and first boot looped forever in setupapi.
