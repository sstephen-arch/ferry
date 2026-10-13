# Graphics backends in Ferry (Phase 9a spike, by Claude after the takeover)

## How CrossOver 26.3.0's Wine selects graphics

There is **no backend switch inside CrossOver's open-source Wine.** `CX_GRAPHICS_BACKEND`, the
variable NotProton's Steam panel sets, appears nowhere in `sources/`. What the source does have:

- `wine/dlls/ntdll/unix/loader.c:1323`: reads `CX_APPLEGPTK_LIBD3DSHARED_PATH` and dlopens
  GPTK's `libd3dshared.dylib` early (Rosetta thread-state support for D3DMetal).
- `wine/dlls/ntdll/unix/loader.c:367`: `prepend_dll_path()` ("CW Hack 24067"), exported but
  called by nothing in the source tree: CrossOver's closed launcher uses it to put a backend's
  DLL directory ahead of Wine's own.
- `wine/dlls/ntdll/unix/loader.c:389`: `set_dll_path()` puts Wine's own dll dir FIRST and
  `WINEDLLPATH` after it, so `WINEDLLPATH` alone can never replace builtin d3d11/dxgi.
- `wine/dlls/win32u/d3dkmt.c:719` and `wine/dlls/win32u/vulkan.c:3007`: read
  `CX_ACTIVE_GRAPHICS_BACKEND` for adapter/Vulkan quirks only.
- `wine/dlls/setupapi/devinst.c:5251`: "CW HACK 23560", matches GPU LUIDs with D3DMetal's dxgi.

So in CrossOver the choice is made by which `d3d11.dll`/`dxgi.dll` the loader finds first, and
the closed launcher arranges that. Ferry has no launcher, so **Ferry patch 0002** adds
`FERRY_DLLPATH_FIRST` to `set_dll_path()`: directories searched before Wine's own dll dir.
`CrossOver/share/ferry/backend.sh` (installed by runner/graphics.sh, sourced by the run script)
maps `CX_GRAPHICS_BACKEND` to that variable.

## Layout in the runner

| Backend | Files | Selected by |
|---|---|---|
| DXMT v0.80 | `lib/dxmt/{x86_64,i386}-windows/{d3d11,dxgi,d3d10core}.dll` (+ nvapi64, nvngx x86_64); `winemetal.dll` in Wine's own pe dirs and `winemetal.so` in `lib/wine/x86_64-unix/` (its rpath is `@loader_path`, it needs Wine's winemac.so/ntdll.so beside it) | `FERRY_DLLPATH_FIRST=$CX_ROOT/lib/dxmt` |
| D3DMetal (GPTK 4.0 beta 2) | `lib64/apple_gptk/external/{D3DMetal.framework,libd3dshared.dylib}`; `lib64/apple_gptk/wine/x86_64-{windows,unix}/{d3d10,d3d11,d3d12,dxgi,nvapi64,nvngx-on-metalfx}` | `FERRY_DLLPATH_FIRST=$CX_ROOT/lib64/apple_gptk/wine` + `CX_APPLEGPTK_LIBD3DSHARED_PATH` |
| wined3d | Wine's own builtins | default |

GPTK ships x86_64 only: 32-bit games use DXMT or wined3d. GPTK files are the owner's own
download and are never committed (Apple's licence forbids redistribution).

## Verdicts

D3DMETAL: SUPPORTED (hooks are in the open source; selection needs Ferry patch 0002 + backend.sh; requires the owner's GPTK files)
DXMT: SUPPORTED (builtin release tarball drops into the runner; same selection mechanism)
