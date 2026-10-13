/* Ferry test: Wine's TLS stack is present (GnuTLS, loaded by secur32 and bcrypt).
   Prints SCHANNEL=0x........ RSA=0x........ ; both 0 when TLS works. No network needed.
   Link: -lsecur32 -lbcrypt */
#define SECURITY_WIN32
#include <windows.h>
#include <security.h>
#include <schannel.h>
#include <bcrypt.h>
#include <stdio.h>
int main(void)
{
    SCHANNEL_CRED cred = { SCHANNEL_CRED_VERSION };
    CredHandle handle;
    TimeStamp expiry;
    BCRYPT_ALG_HANDLE rsa = NULL;
    SECURITY_STATUS s = AcquireCredentialsHandleA(NULL, (char *)UNISP_NAME_A, SECPKG_CRED_OUTBOUND,
                                                  NULL, &cred, NULL, NULL, &handle, &expiry);
    NTSTATUS n = BCryptOpenAlgorithmProvider(&rsa, BCRYPT_RSA_ALGORITHM, NULL, 0);
    printf("SCHANNEL=0x%08lx RSA=0x%08lx\n", (unsigned long)s, (unsigned long)n);
    if (s == SEC_E_OK) FreeCredentialsHandle(&handle);
    if (rsa) BCryptCloseAlgorithmProvider(rsa, 0);
    return 0;
}
