// macOS CGDisplay* APIs the Forge window code uses to enumerate monitors and modes.
// iOS has one display: the UIScreen, at its native pixel size and max refresh rate.
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#include "../common/shimlog.h"

typedef uint32_t CGDirectDisplayID;
typedef struct CGDisplayMode { size_t w, h; double hz; } *CGDisplayModeRef;
const CFStringRef kCGDisplayShowDuplicateLowResolutionModes = CFSTR("kCGDisplayShowDuplicateLowResolutionModes");

static CGSize NativeSize(void)
{
    // The AppKit shim caches the safe-area game size in pixels; report that as the display mode.
    NSString *cached = [NSUserDefaults.standardUserDefaults stringForKey:@"HadesGameAreaPx"];
    if (cached) return CGSizeFromString(cached);
    __block CGSize s;
    void (^get)(void) = ^{
        CGRect b = UIScreen.mainScreen.nativeBounds;   // portrait pixels
        s = CGSizeMake(MAX(b.size.width, b.size.height), MIN(b.size.width, b.size.height));
    };
    if (NSThread.isMainThread) get(); else dispatch_sync(dispatch_get_main_queue(), get);
    return s;
}

static CGDisplayModeRef NewMode(void)
{
    CGDisplayModeRef m = calloc(1, sizeof *m);
    CGSize s = NativeSize();
    m->w = (size_t)s.width; m->h = (size_t)s.height;
    m->hz = UIScreen.mainScreen.maximumFramesPerSecond;
    return m;
}

CGDirectDisplayID CGMainDisplayID(void) { return 1; }

CGError CGGetOnlineDisplayList(uint32_t max, CGDirectDisplayID *displays, uint32_t *count)
{
    if (displays && max) displays[0] = 1;
    if (count) *count = 1;
    return 0;
}

CGDisplayModeRef CGDisplayCopyDisplayMode(CGDirectDisplayID d) { return NewMode(); }

CFArrayRef CGDisplayCopyAllDisplayModes(CGDirectDisplayID d, CFDictionaryRef opts)
{
    // Ownership semantics of the array values don't matter to callers; leak-free enough for a one-off query.
    CGDisplayModeRef m = NewMode();
    const void *vals[] = { m };
    return CFArrayCreate(NULL, vals, 1, NULL);
}

size_t CGDisplayModeGetPixelWidth(CGDisplayModeRef m) { return m ? m->w : 0; }
size_t CGDisplayModeGetPixelHeight(CGDisplayModeRef m) { return m ? m->h : 0; }
double CGDisplayModeGetRefreshRate(CGDisplayModeRef m) { return m ? m->hz : 60; }
void CGDisplayModeRelease(CGDisplayModeRef m) { free(m); }

CGSize CGDisplayScreenSize(CGDirectDisplayID d)
{
    return CGSizeMake(163, 75);   // physical mm, approximate for a 6.9" phone; only used for DPI hints
}

CGError CGWarpMouseCursorPosition(CGPoint p) { SHIM_STUB(); return 0; }

id<MTLDevice> CGDirectDisplayCopyCurrentMetalDevice(CGDirectDisplayID d)
{
    return MTLCreateSystemDefaultDevice();
}
