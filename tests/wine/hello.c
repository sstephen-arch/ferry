/* Protected Ferry test: prints the architecture the COMPILER targeted. */
#include <stdio.h>
int main(void)
{
#if defined(_WIN64)
    puts("ferry-hello x86_64");
#elif defined(_WIN32) && defined(_M_IX86) || defined(__i386__)
    puts("ferry-hello i386");
#else
    puts("ferry-hello unknown");
#endif
    return 0;
}
