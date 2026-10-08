// Logging for shims: every stub logs its first call so missing behaviour shows up
// in `devicectl device process launch --console` output.
#pragma once
#include <stdio.h>
#include <stdatomic.h>

#define SHIM_LOG(fmt, ...) fprintf(stderr, "[shim] " fmt "\n", ##__VA_ARGS__)
#define SHIM_LOG_ONCE(fmt, ...) do { static atomic_flag _f = ATOMIC_FLAG_INIT; \
    if (!atomic_flag_test_and_set(&_f)) SHIM_LOG(fmt, ##__VA_ARGS__); } while (0)
#define SHIM_STUB() SHIM_LOG_ONCE("stub: %s", __func__)

// Verbose diagnostics (per-heap/audio/HAL tracing) only when the HadesVerbose default is set.
#include <CoreFoundation/CoreFoundation.h>
static inline int HadesVerbose(void)
{
    static int v = -1;
    if (v < 0) {
        Boolean ok = false;
        v = CFPreferencesGetAppBooleanValue(CFSTR("HadesVerbose"), kCFPreferencesCurrentApplication, &ok) && ok;
    }
    return v;
}
#define SHIM_VLOG(fmt, ...) do { if (HadesVerbose()) SHIM_LOG(fmt, ##__VA_ARGS__); } while (0)
