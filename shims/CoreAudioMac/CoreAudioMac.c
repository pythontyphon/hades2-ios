// macOS CoreAudio HAL calls made by the retagged FMOD. iOS CoreAudio exports AudioObject*, but
// calling them boots an in-process macOS-style audio server that loads BTAudioHALPlugin and
// traps on XPC misuse. So never forward: describe one fixed stereo 48 kHz output device. The
// audio itself flows through RemoteIO (see AudioUnitMac), which needs no HAL at all.
#include <CoreAudio/CoreAudioTypes.h>
#include <CoreFoundation/CoreFoundation.h>
#include <string.h>
#include "../common/shimlog.h"

typedef UInt32 AudioObjectID;
typedef struct { UInt32 mSelector, mScope, mElement; } AudioObjectPropertyAddress;
typedef OSStatus (*AudioObjectPropertyListenerProc)(AudioObjectID, UInt32, const AudioObjectPropertyAddress *, void *);

#define kDevice 2
#define kUnknownProperty 'who?'
#define kBadSize '!siz'
#define FOURCC(x) (char)((x) >> 24), (char)((x) >> 16), (char)((x) >> 8), (char)(x)

// Fills *out with the property value (size bytes); returns 0 or a HAL error.
static OSStatus Property(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 *size, void *out)
{
    union { AudioObjectID id; Float64 rate; CFStringRef str; char layout[52]; } v;
    UInt32 n;
    switch (a->mSelector) {
    case 'dOut':   // kAudioHardwarePropertyDefaultOutputDevice
    case 'dev#':   // kAudioHardwarePropertyDevices
        v.id = kDevice; n = sizeof v.id; break;
    case 'nsrt':   // kAudioDevicePropertyNominalSampleRate
        v.rate = 48000.0; n = sizeof v.rate; break;
    case 'uid ':   // kAudioDevicePropertyDeviceUID (caller releases)
        v.str = CFSTR("HadesRemoteIO"); n = sizeof v.str; break;
    case 'lnam':   // kAudioDevicePropertyDeviceNameCFString
        v.str = CFSTR("iPhone"); n = sizeof v.str; break;
    case 'srnd': { // kAudioDevicePropertyPreferredChannelLayout: stereo L/R by description
        AudioChannelLayout *l = (AudioChannelLayout *)v.layout;
        memset(v.layout, 0, sizeof v.layout);
        l->mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions;
        l->mNumberChannelDescriptions = 2;
        l->mChannelDescriptions[0].mChannelLabel = kAudioChannelLabel_Left;
        l->mChannelDescriptions[1].mChannelLabel = kAudioChannelLabel_Right;
        n = sizeof v.layout;
        break;
    }
    default:
        SHIM_LOG("CoreAudioMac: unknown HAL property obj=%u '%c%c%c%c' scope '%c%c%c%c'",
                 obj, FOURCC(a->mSelector), FOURCC(a->mScope));
        return kUnknownProperty;
    }
    if (out) {
        if (*size < n) return kBadSize;
        if (n == sizeof(CFStringRef) && (a->mSelector == 'uid ' || a->mSelector == 'lnam')) CFRetain(v.str);
        memcpy(out, &v, n);
    }
    *size = n;
    return 0;
}

OSStatus AudioObjectGetPropertyDataSize(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qs,
                                        const void *q, UInt32 *size)
{
    return Property(obj, a, size, NULL);
}

OSStatus AudioObjectGetPropertyData(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qs,
                                    const void *q, UInt32 *size, void *data)
{
    return Property(obj, a, size, data);
}

OSStatus AudioObjectSetPropertyData(AudioObjectID obj, const AudioObjectPropertyAddress *a, UInt32 qs,
                                    const void *q, UInt32 size, const void *data)
{
    SHIM_LOG("CoreAudioMac: ignoring HAL set '%c%c%c%c'", FOURCC(a->mSelector));
    return 0;
}

Boolean AudioObjectHasProperty(AudioObjectID obj, const AudioObjectPropertyAddress *a)
{
    UInt32 size = 0;
    return Property(obj, a, &size, NULL) == 0;
}

// Device topology never changes on our fake HAL, so listeners never fire.
OSStatus AudioObjectAddPropertyListener(AudioObjectID obj, const AudioObjectPropertyAddress *a,
                                        AudioObjectPropertyListenerProc proc, void *ctx) { return 0; }
OSStatus AudioObjectRemovePropertyListener(AudioObjectID obj, const AudioObjectPropertyAddress *a,
                                           AudioObjectPropertyListenerProc proc, void *ctx) { return 0; }
