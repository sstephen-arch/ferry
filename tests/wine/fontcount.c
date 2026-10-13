/* Protected Ferry test: counts font families GDI can see. Prints FONTS=<n>. */
#include <windows.h>
#include <stdio.h>
static int n;
static int CALLBACK cb(const LOGFONTW *lf, const TEXTMETRICW *tm, DWORD type, LPARAM p) { n++; return 1; }
int main(void)
{
    HDC dc = CreateCompatibleDC(NULL);
    LOGFONTW lf = {0}; lf.lfCharSet = DEFAULT_CHARSET;
    EnumFontFamiliesExW(dc, &lf, cb, 0, 0);
    printf("FONTS=%d\n", n);
    return n > 0 ? 0 : 1;
}
