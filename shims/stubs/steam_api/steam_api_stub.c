// Offline replacement for libsteam_api.dylib. SteamAPI init "succeeds" and every interface the
// game asks for is a fake C++ object whose vtable slots all return 0 (not logged in, no
// achievements, no cloud), so the game runs as if Steam were present but offline.
#include <stdint.h>
#include <string.h>
#include "../../common/shimlog.h"

typedef int32_t HSteamUser;
typedef int32_t HSteamPipe;

static uint64_t ReturnZero(void) { return 0; }

#define VTABLE_SLOTS 512
static void *g_vtable[VTABLE_SLOTS];
static struct { void **vtbl; } g_iface = { g_vtable };
static uintptr_t g_init_counter = 1;

__attribute__((constructor)) static void InitVtable(void)
{
    for (int i = 0; i < VTABLE_SLOTS; i++) g_vtable[i] = (void *)ReturnZero;
}

// ESteamAPIInitResult: 0 = OK
int SteamInternal_SteamAPI_Init(const char *versions, char *outErrMsg)
{
    SHIM_LOG("steam_api stub: SteamAPI_Init -> OK (offline)");
    if (outErrMsg) outErrMsg[0] = 0;
    return 0;
}

void SteamAPI_Shutdown(void) {}
void SteamAPI_RunCallbacks(void) {}
void SteamAPI_RegisterCallback(void *cb, int id) {}
void SteamAPI_UnregisterCallback(void *cb) {}
HSteamUser SteamAPI_GetHSteamUser(void) { return 1; }
HSteamPipe SteamAPI_GetHSteamPipe(void) { return 1; }
int SteamAPI_RestartAppIfNecessary(uint32_t appid) { return 0; }

void *SteamInternal_FindOrCreateUserInterface(HSteamUser user, const char *version)
{
    SHIM_LOG("steam_api stub: interface %s", version ? version : "?");
    return &g_iface;
}

void *SteamInternal_FindOrCreateGameServerInterface(HSteamUser user, const char *version) { return &g_iface; }

// Mirrors steam_api_internal.h: struct { void (*init)(void *ctx); uintptr_t counter; ctx storage... }
void *SteamInternal_ContextInit(void *pContextInitData)
{
    struct Ctx { void (*init)(void *); uintptr_t counter; char ctx[]; } *c = pContextInitData;
    if (c->counter != g_init_counter) {
        c->init(c->ctx);
        c->counter = g_init_counter;
    }
    return c->ctx;
}
