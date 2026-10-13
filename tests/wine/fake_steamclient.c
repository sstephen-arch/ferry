/* Protected Ferry test: stands in for Valve's steamclient64.dll / steamclient.dll.
   Built twice: -o steamclient64.dll (x86_64) and -o steamclient.dll (i386). */
#include <windows.h>
/* each export 16-byte aligned: Ferry's loader writes a 12-byte jump over the shared ones */
#define EXPORT __declspec(dllexport) __attribute__((aligned(16)))
static volatile LONG real_dllmain_ran = 0;
BOOL WINAPI DllMain(HINSTANCE h, DWORD reason, LPVOID r)
{
    if (reason == DLL_PROCESS_ATTACH) InterlockedExchange(&real_dllmain_ran, 1);
    return TRUE;
}
EXPORT int Steam_A(void) { return 1; }
EXPORT int Steam_B(void) { return 11; }
EXPORT int OnlyInReal(void) { return 99; }
/* Not exported by lsteamclient, so a redirect never replaces it: reports the real flag. */
EXPORT int FerryProbeRealDllMainRan(void) { return (int)real_dllmain_ran; }
