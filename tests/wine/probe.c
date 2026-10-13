/* Protected Ferry test probe.
   probe.exe <dll name>            -> A=<n> B=<n> R=<n> E=<0|1> L=<0|1> M=<0|1>
   M: Steam_A's address lies inside <dll name> itself (SteamStub DRM checks this)
   probe.exe --overlay             -> O=<0|1|missing>   (gameoverlayrenderer.dll DllMain ran?)
   Values: -1 = export missing, -2 = LoadLibrary failed. */
#include <windows.h>
#include <stdio.h>
#include <string.h>
typedef int (*fn)(void);
static int call(HMODULE m, const char *name)
{
    fn f = (fn)GetProcAddress(m, name);
    return f ? f() : -1;
}
int main(int argc, char **argv)
{
    if (argc > 1 && !strcmp(argv[1], "--overlay"))
    {
        HMODULE o = LoadLibraryA("gameoverlayrenderer.dll");
        if (!o) { puts("O=missing"); return 2; }
        printf("O=%d\n", call(o, "FerryProbeOverlayDllMainRan"));
        return 0;
    }
    const char *name = argc > 1 ? argv[1] : "steamclient64.dll";
    HMODULE m = LoadLibraryA(name);
    if (!m) { printf("A=-2 B=-2 R=-2 E=-2 L=%d\n", GetModuleHandleA("lsteamclient.dll") != NULL); return 2; }
    HMODULE owner = NULL;
    GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                       (LPCSTR)GetProcAddress(m, "Steam_A"), &owner);
    printf("A=%d B=%d R=%d E=%d L=%d M=%d\n", call(m, "Steam_A"), call(m, "Steam_B"), call(m, "OnlyInReal"),
           call(m, "FerryProbeRealDllMainRan"), GetModuleHandleA("lsteamclient.dll") != NULL, owner == m);
    fflush(stdout);
    return 0;
}
