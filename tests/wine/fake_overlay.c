/* Protected Ferry test: stands in for gameoverlayrenderer.dll (32-bit case in detour32.c). */
#include <windows.h>
static volatile LONG overlay_dllmain_ran = 0;
BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID r)
{
    if (reason == DLL_PROCESS_ATTACH) InterlockedExchange(&overlay_dllmain_ran, 1);
    return TRUE;
}
__declspec(dllexport) int FerryProbeOverlayDllMainRan(void) { return (int)overlay_dllmain_ran; }
