// macOS AudioUnit.framework -> iOS AudioToolbox (re-exported). FMOD asks for the HAL output
// unit, which iOS lacks; hand it RemoteIO instead and swallow HAL-only properties.
#include <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>
#include "../common/shimlog.h"

#define kHALOutputSubType 'ahal'
#define kAudioOutputUnitProperty_CurrentDevice 2000
#define kAudioOutputUnitProperty_IsRunning_ 2001

AudioComponent AudioComponentFindNext(AudioComponent inComponent, const AudioComponentDescription *inDesc)
{
    AudioComponentDescription d = *inDesc;
    if (d.componentType == kAudioUnitType_Output && d.componentSubType == kHALOutputSubType) {
        SHIM_LOG_ONCE("AudioUnitMac: HALOutput -> RemoteIO");
        d.componentSubType = kAudioUnitSubType_RemoteIO;
    }
    AudioComponent (*real)(AudioComponent, const AudioComponentDescription *) = dlsym(RTLD_NEXT, "AudioComponentFindNext");
    return real(inComponent, &d);
}

OSStatus AudioUnitSetProperty(AudioUnit unit, AudioUnitPropertyID prop, AudioUnitScope scope,
                              AudioUnitElement elem, const void *data, UInt32 size)
{
    if (prop == kAudioOutputUnitProperty_CurrentDevice) {
        SHIM_LOG_ONCE("AudioUnitMac: ignoring CurrentDevice");
        return noErr;
    }
    OSStatus (*real)(AudioUnit, AudioUnitPropertyID, AudioUnitScope, AudioUnitElement, const void *, UInt32) =
        dlsym(RTLD_NEXT, "AudioUnitSetProperty");
    OSStatus r = real(unit, prop, scope, elem, data, size);
    SHIM_VLOG("AU set prop %u scope %u el %u -> %d", (unsigned)prop, (unsigned)scope, (unsigned)elem, (int)r);
    return r;
}

// Diagnostics: trace the rest of the output-unit lifecycle FMOD drives.
#define TRACE_FWD(ret, name, params, args, fmt, ...) \
    ret name params { \
        static ret (*real) params; if (!real) real = dlsym(RTLD_NEXT, #name); \
        SHIM_VLOG("AU " #name " " fmt " ...", ##__VA_ARGS__); \
        ret r = real args; SHIM_VLOG("   -> %d", (int)r); return r; }

TRACE_FWD(OSStatus, AudioUnitInitialize, (AudioUnit u), (u), "")
TRACE_FWD(OSStatus, AudioOutputUnitStart, (AudioUnit u), (u), "")
TRACE_FWD(OSStatus, AudioOutputUnitStop, (AudioUnit u), (u), "")
TRACE_FWD(OSStatus, AudioUnitUninitialize, (AudioUnit u), (u), "")
TRACE_FWD(OSStatus, AudioComponentInstanceNew, (AudioComponent c, AudioComponentInstance *o), (c, o), "")
TRACE_FWD(OSStatus, AudioUnitGetProperty,
          (AudioUnit u, AudioUnitPropertyID p, AudioUnitScope s, AudioUnitElement e, void *d, UInt32 *sz),
          (u, p, s, e, d, sz), "get prop %u scope %u el %u", (unsigned)p, (unsigned)s, (unsigned)e)
