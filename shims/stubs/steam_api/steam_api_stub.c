// Replacement for libsteam_api.dylib that behaves like the real library when no Steam client is
// running: SteamAPI_Init reports k_ESteamAPIInitResult_NoSteamClient and every interface lookup
// returns NULL. Nothing is faked or bypassed; the game simply runs with Steam features unavailable
// (it does not require Steam on macOS: it never calls SteamAPI_RestartAppIfNecessary).
#include <stdint.h>
#include <stddef.h>
#include "../../common/shimlog.h"

typedef int32_t HSteamUser;
typedef int32_t HSteamPipe;

enum { k_ESteamAPIInitResult_NoSteamClient = 2 };

int SteamInternal_SteamAPI_Init(const char *versions, char *outErrMsg)
{
    SHIM_LOG("steam_api: no Steam client on iOS - SteamAPI_Init -> NoSteamClient");
    if (outErrMsg) {
        static const char msg[] = "Steam is not running";
        for (size_t i = 0; i < sizeof msg; i++) outErrMsg[i] = msg[i];
    }
    return k_ESteamAPIInitResult_NoSteamClient;
}

void SteamAPI_Shutdown(void) {}
void SteamAPI_RunCallbacks(void) {}
void SteamAPI_RegisterCallback(void *cb, int id) {}
void SteamAPI_UnregisterCallback(void *cb) {}
HSteamUser SteamAPI_GetHSteamUser(void) { return 0; }
HSteamPipe SteamAPI_GetHSteamPipe(void) { return 0; }
int SteamAPI_RestartAppIfNecessary(uint32_t appid) { return 0; }

void *SteamInternal_FindOrCreateUserInterface(HSteamUser user, const char *version)
{
    SHIM_LOG("steam_api: interface %s requested without Steam -> NULL", version ? version : "?");
    return NULL;
}

void *SteamInternal_FindOrCreateGameServerInterface(HSteamUser user, const char *version) { return NULL; }

// Mirrors steam_api_internal.h: struct { void (*init)(void *ctx); uintptr_t counter; ctx storage... }.
// Without Steam the real library runs the init callback once; the interface pointers it fills are NULL.
void *SteamInternal_ContextInit(void *pContextInitData)
{
    struct Ctx { void (*init)(void *); uintptr_t counter; char ctx[]; } *c = pContextInitData;
    if (c->counter != 1) {
        c->init(c->ctx);
        c->counter = 1;
    }
    return c->ctx;
}
