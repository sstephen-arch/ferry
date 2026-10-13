/* Protected Ferry test: create a hardware D3D11 device without a window and print the adapter.
   Prints hr=0x........ adapter=<description> feature=0x.... wined3d=0|1 winemetal=0|1; exit 0 only
   on success. wined3d/winemetal say which D3D11 really loaded: Wine's own d3d11 pulls in
   wined3d.dll, DXMT's pulls in winemetal.dll, so an Apple adapter alone proves nothing.
   Link: -ld3d11 -ldxgi -luuid */
#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <stdio.h>
int main(void)
{
    ID3D11Device *dev = NULL; ID3D11DeviceContext *ctx = NULL; D3D_FEATURE_LEVEL got;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, 0, NULL, 0,
                                   D3D11_SDK_VERSION, &dev, &got, &ctx);
    if (FAILED(hr)) { printf("hr=0x%08lx adapter=none\n", (unsigned long)hr); return 1; }
    IDXGIDevice *xd = NULL; IDXGIAdapter *ad = NULL; DXGI_ADAPTER_DESC desc;
    char name[256] = "unknown";
    if (SUCCEEDED(ID3D11Device_QueryInterface(dev, &IID_IDXGIDevice, (void **)&xd)) &&
        SUCCEEDED(IDXGIDevice_GetAdapter(xd, &ad)) && SUCCEEDED(IDXGIAdapter_GetDesc(ad, &desc)))
        WideCharToMultiByte(CP_UTF8, 0, desc.Description, -1, name, sizeof(name), NULL, NULL);
    printf("hr=0x%08lx adapter=%s feature=0x%x wined3d=%d winemetal=%d\n", (unsigned long)hr, name,
           (unsigned)got, GetModuleHandleA("wined3d.dll") != NULL, GetModuleHandleA("winemetal.dll") != NULL);
    return 0;
}
