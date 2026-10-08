// AppKit-on-UIKit shim: just enough of AppKit for Supergiant's Forge-based macOS build.
// NSView/NSWindow are plain NSObjects that own UIKit views; UIKit never sees them,
// so UIView's own -window/-layer semantics stay intact.
#pragma once
#import <UIKit/UIKit.h>
#include "../common/shimlog.h"

typedef CGRect NSRect;
typedef CGSize NSSize;
typedef CGPoint NSPoint;
typedef NSUInteger NSWindowStyleMask;
#define NSWindowStyleMaskFullScreen (1 << 14)

// Any selector a shim class doesn't implement resolves to a logged IMP that returns 0
// in x0/x1 and d0-d3 (covers id, integers, BOOL, and NSRect/NSSize/NSPoint returns).
void HadesShimInstallCatchAll(Class cls);
#define HADES_CATCH_ALL \
    + (BOOL)resolveInstanceMethod:(SEL)sel { HadesShimInstallCatchAllFor(self, sel, NO); return YES; } \
    + (BOOL)resolveClassMethod:(SEL)sel { HadesShimInstallCatchAllFor(self, sel, YES); return YES; }
void HadesShimInstallCatchAllFor(Class cls, SEL sel, BOOL isClassMethod);

@class NSWindow, NSScreen;

@interface NSView : NSObject
@property (nonatomic, readonly) UIView *hostView;          // backing UIKit view
@property (nonatomic, weak) NSWindow *window;
@property (nonatomic, strong) CALayer *layer;                // hosted layer (game's CAMetalLayer)
@property (nonatomic) BOOL wantsLayer;
- (instancetype)initWithFrame:(NSRect)frame;
@end

@interface NSWindow : NSObject
@property (nonatomic, strong) NSView *contentView;
@property (nonatomic, weak) id delegate;
@property (nonatomic) NSWindowStyleMask styleMask;
- (void)hades_attach;
- (void)hades_postResize;
@end

@interface NSScreen : NSObject
+ (NSScreen *)mainScreen;
- (CGFloat)backingScaleFactor;
- (NSRect)frame;
@end

@interface NSApplication : NSObject
@property (nonatomic, strong) id delegate;
+ (instancetype)sharedApplication;
@end

// Shared state between the UIKit lifecycle and the AppKit facade.
extern UIViewController *HadesRootViewController;
extern BOOL HadesAppInBackground;
extern NSMutableArray<NSWindow *> *HadesWindows;
CGRect HadesScreenBoundsLandscape(void);   // game area size in points, origin 0
CGRect HadesGameAreaInRoot(void);          // game area within the root view (safe-area aware)
CGFloat HadesBackingScale(void);           // render scale (defaults to UIScreen.scale)
