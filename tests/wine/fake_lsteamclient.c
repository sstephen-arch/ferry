/* Protected Ferry test: stands in for lsteamclient.dll. */
#include <windows.h>
#define EXPORT __declspec(dllexport) __attribute__((aligned(16)))
EXPORT int Steam_A(void) { return 2; }
EXPORT int Steam_B(void) { return 22; }
EXPORT int OnlyInL(void) { return 77; }
