// Offline replacement for libEOSSDK (Epic Online Services). EOS_Platform_Create returns NULL,
// so the game sees EOS as unavailable; everything else is a logged no-op.
#include <stdint.h>
#include <stddef.h>
#include "../../common/shimlog.h"

typedef int32_t EOS_EResult;
#define EOS_Success 0
#define EOS_NotConfigured 14
typedef int32_t EOS_Bool;

EOS_EResult EOS_Initialize(const void *opts) { SHIM_LOG("EOS stub: EOS_Initialize -> NotConfigured"); return EOS_NotConfigured; }
EOS_EResult EOS_Shutdown(void) { return EOS_Success; }
void *EOS_Platform_Create(const void *opts) { SHIM_LOG("EOS stub: EOS_Platform_Create -> NULL"); return NULL; }
void EOS_Platform_Release(void *h) {}
void EOS_Platform_Tick(void *h) {}
EOS_EResult EOS_Platform_SetOverrideLocaleCode(void *h, const char *c) { return EOS_Success; }
void *EOS_Platform_GetAchievementsInterface(void *h) { return NULL; }
void *EOS_Platform_GetAuthInterface(void *h) { return NULL; }
void *EOS_Platform_GetConnectInterface(void *h) { return NULL; }
void *EOS_Platform_GetPlayerDataStorageInterface(void *h) { return NULL; }
EOS_EResult EOS_Logging_SetCallback(void *cb) { return EOS_Success; }
EOS_EResult EOS_Logging_SetLogLevel(int cat, int lvl) { return EOS_Success; }
EOS_Bool EOS_EResult_IsOperationComplete(EOS_EResult r) { return 1; }
const char *EOS_EResult_ToString(EOS_EResult r) { return r == EOS_Success ? "EOS_Success" : "EOS_NotConfigured"; }
EOS_Bool EOS_EpicAccountId_IsValid(void *id) { return 0; }
EOS_Bool EOS_ProductUserId_IsValid(void *id) { return 0; }
EOS_EResult EOS_ProductUserId_ToString(void *id, char *buf, int32_t *len) { if (buf && len && *len) buf[0] = 0; return EOS_NotConfigured; }
EOS_EResult EOS_IntegratedPlatform_CreateIntegratedPlatformOptionsContainer(const void *o, void **out) { if (out) *out = NULL; return EOS_NotConfigured; }
void EOS_IntegratedPlatformOptionsContainer_Release(void *c) {}

// Interface calls: unreachable while the platform handle is NULL, but keep them safe.
#define NOOP(name) void name(void) { SHIM_STUB(); }
#define ZERO(name) int64_t name(void) { SHIM_STUB(); return 0; }
#define FAIL(name) EOS_EResult name(void) { SHIM_STUB(); return EOS_NotConfigured; }
FAIL(EOS_Achievements_CopyPlayerAchievementByIndex)
ZERO(EOS_Achievements_GetPlayerAchievementCount)
NOOP(EOS_Achievements_PlayerAchievement_Release)
NOOP(EOS_Achievements_QueryDefinitions)
NOOP(EOS_Achievements_UnlockAchievements)
FAIL(EOS_Auth_CopyUserAuthToken)
NOOP(EOS_Auth_DeletePersistentAuth)
ZERO(EOS_Auth_GetLoggedInAccountByIndex)
ZERO(EOS_Auth_GetLoggedInAccountsCount)
ZERO(EOS_Auth_GetLoginStatus)
NOOP(EOS_Auth_Login)
NOOP(EOS_Auth_Logout)
NOOP(EOS_Auth_Token_Release)
ZERO(EOS_Connect_AddNotifyAuthExpiration)
NOOP(EOS_Connect_CreateUser)
ZERO(EOS_Connect_GetLoggedInUserByIndex)
ZERO(EOS_Connect_GetLoggedInUsersCount)
ZERO(EOS_Connect_GetLoginStatus)
NOOP(EOS_Connect_Login)
NOOP(EOS_Connect_RemoveNotifyAuthExpiration)
FAIL(EOS_PlayerDataStorageFileTransferRequest_CancelRequest)
NOOP(EOS_PlayerDataStorageFileTransferRequest_Release)
FAIL(EOS_PlayerDataStorage_CopyFileMetadataAtIndex)
FAIL(EOS_PlayerDataStorage_DeleteCache)
NOOP(EOS_PlayerDataStorage_DeleteFile)
NOOP(EOS_PlayerDataStorage_FileMetadata_Release)
NOOP(EOS_PlayerDataStorage_QueryFileList)
ZERO(EOS_PlayerDataStorage_ReadFile)
ZERO(EOS_PlayerDataStorage_WriteFile)
