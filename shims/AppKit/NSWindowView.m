// NSWindow / NSView / NSScreen on top of the single full-screen UIKit root view.
#import <objc/message.h>
#import <objc/runtime.h>
#import <QuartzCore/CAMetalLayer.h>
#import "AppKitShim.h"

NSNotificationName const NSWindowDidBecomeKeyNotification = @"NSWindowDidBecomeKeyNotification";
NSNotificationName const NSWindowDidBecomeMainNotification = @"NSWindowDidBecomeMainNotification";
NSNotificationName const NSWindowDidResignMainNotification = @"NSWindowDidResignMainNotification";
NSNotificationName const NSWindowDidChangeScreenNotification = @"NSWindowDidChangeScreenNotification";
NSNotificationName const NSWindowDidResizeNotification_ = @"NSWindowDidResizeNotification";

static CGRect FullScreenLandscape(void)
{
    CGRect b = UIScreen.mainScreen.bounds;
    return CGRectMake(0, 0, MAX(b.size.width, b.size.height), MIN(b.size.width, b.size.height));
}

// Where the game draws, in root-view points. With HadesSafeArea (default on) the left/right safe-area
// insets are excluded so the rounded corners and Dynamic Island don't clip the HUD; full height is kept.
CGRect HadesGameAreaInRoot(void)
{
    UIView *root = HadesRootViewController.view;
    if (!root.window) return FullScreenLandscape();
    CGRect r = root.bounds;
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    BOOL safe = [d objectForKey:@"HadesSafeArea"] ? [d boolForKey:@"HadesSafeArea"] : YES;
    if (safe) {
        UIEdgeInsets in = root.safeAreaInsets;
        r = CGRectMake(in.left, 0, r.size.width - in.left - in.right, r.size.height);
    }
    return CGRectIntegral(r);
}

// The game's view of the "screen": the game area at origin 0. Before UIKit is up (the game queries this
// from main()), use the size cached by the previous run so it starts at the right resolution.
CGRect HadesScreenBoundsLandscape(void)
{
    NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
    if (HadesRootViewController.view.window) {
        CGSize s = HadesGameAreaInRoot().size;
        CGFloat scale = UIScreen.mainScreen.scale;
        [d setObject:NSStringFromCGSize(s) forKey:@"HadesGameAreaPt"];
        [d setObject:NSStringFromCGSize(CGSizeMake(s.width * scale, s.height * scale)) forKey:@"HadesGameAreaPx"];
        return CGRectMake(0, 0, s.width, s.height);
    }
    NSString *cached = [d stringForKey:@"HadesGameAreaPt"];
    if (cached) { CGSize s = CGSizeFromString(cached); return CGRectMake(0, 0, s.width, s.height); }
    return FullScreenLandscape();
}

CGFloat HadesBackingScale(void)
{
    // Performance lever: `HadesRenderScale` default (e.g. 2.0) renders below native 3x.
    double s = [NSUserDefaults.standardUserDefaults doubleForKey:@"HadesRenderScale"];
    return s > 0 ? s : UIScreen.mainScreen.scale;
}

static void NotifyDelegate(id window, SEL sel, NSString *name)
{
    NSNotification *n = [NSNotification notificationWithName:name object:window];
    id d = [window delegate];
    if (d && class_getInstanceMethod(object_getClass(d), sel))   // real implementations only
        ((void (*)(id, SEL, id))objc_msgSend)(d, sel, n);
    [NSNotificationCenter.defaultCenter postNotification:n];
}

#pragma mark - NSView

@interface HadesHostView : UIView
@property (nonatomic, weak) NSView *owner;
@end

@implementation HadesHostView
- (void)layoutSubviews
{
    [super layoutSubviews];
    CALayer *hosted = self.owner.layer;
    if (hosted && hosted.superlayer == self.layer) {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        hosted.frame = self.layer.bounds;
        [CATransaction commit];
        if ([hosted isKindOfClass:CAMetalLayer.class]) {
            CAMetalLayer *m = (CAMetalLayer *)hosted;
            SHIM_LOG("layer: frame %.0fx%.0f pt, contentsScale %.1f, drawable %.0fx%.0f px",
                     m.frame.size.width, m.frame.size.height, m.contentsScale, m.drawableSize.width, m.drawableSize.height);
        }
    }
}
@end

@implementation NSView {
    HadesHostView *_host;
    NSMutableArray *_trackingAreas;
}
@synthesize layer = _layer;
HADES_CATCH_ALL

- (instancetype)init { return [self initWithFrame:CGRectZero]; }

- (instancetype)initWithFrame:(NSRect)frame
{
    // The Forge's macOS code sizes its window from display-mode *pixels* but passes that as a frame
    // in points, then sets drawableSize = frame * backingScale (3x too big: the image only filled
    // the top-left third). Views are always full screen here, so clamp to the screen in points.
    CGRect screen = HadesScreenBoundsLandscape();
    if (frame.size.width > screen.size.width || frame.size.height > screen.size.height) frame = screen;
    if ((self = [super init])) {
        _host = [[HadesHostView alloc] initWithFrame:frame];
        _host.owner = self;
        _host.backgroundColor = UIColor.blackColor;
        _host.multipleTouchEnabled = YES;
        _trackingAreas = [NSMutableArray new];
    }
    return self;
}

- (UIView *)hostView { return _host; }

- (void)setLayer:(CALayer *)layer
{
    [_layer removeFromSuperlayer];
    _layer = layer;
    if (layer) {
        layer.frame = _host.layer.bounds;
        [_host.layer addSublayer:layer];
    }
}

- (CALayer *)layer { return _layer ?: _host.layer; }

- (NSRect)frame { return _host.frame; }
- (void)setFrame:(NSRect)f { _host.frame = f; }
- (NSRect)bounds { return _host.bounds; }
- (void)setFrameOrigin:(NSPoint)p { CGRect f = _host.frame; f.origin = p; _host.frame = f; }
- (void)setFrameSize:(NSSize)s { CGRect f = _host.frame; f.size = s; _host.frame = f; }
- (void)setAutoresizingMask:(NSUInteger)m { _host.autoresizingMask = m; }   // NS/UI bit layouts match
- (void)setAutoresizesSubviews:(BOOL)b { _host.autoresizesSubviews = b; }
- (void)setHidden:(BOOL)h { _host.hidden = h; }
- (BOOL)isHidden { return _host.hidden; }
- (BOOL)isFlipped { return NO; }
- (BOOL)isOpaque { return YES; }
- (void)setNeedsDisplay:(BOOL)b {}
- (void)addSubview:(NSView *)v { v.window = self.window; [_host addSubview:v.hostView]; }
- (void)removeFromSuperview { [_host removeFromSuperview]; }
- (void)addTrackingArea:(id)a { if (a) [_trackingAreas addObject:a]; }
- (void)removeTrackingArea:(id)a { [_trackingAreas removeObject:a]; }
- (NSArray *)trackingAreas { return [_trackingAreas copy]; }
- (void)updateTrackingAreas {}
- (NSPoint)convertPoint:(NSPoint)p toView:(NSView *)v { return p; }
- (NSPoint)convertPoint:(NSPoint)p fromView:(NSView *)v { return p; }
- (NSRect)convertRectToBacking:(NSRect)r
{
    CGFloat s = HadesBackingScale();
    return CGRectMake(r.origin.x * s, r.origin.y * s, r.size.width * s, r.size.height * s);
}
@end

#pragma mark - NSWindow

@implementation NSWindow {
    CGSize _lastSize;
}
HADES_CATCH_ALL

+ (NSRect)frameRectForContentRect:(NSRect)r styleMask:(NSWindowStyleMask)m { return r; }
+ (NSRect)contentRectForFrameRect:(NSRect)r styleMask:(NSWindowStyleMask)m { return r; }

- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style backing:(NSUInteger)backing
                              defer:(BOOL)defer screen:(NSScreen *)screen
{
    if ((self = [super init])) {
        _styleMask = style;
        [HadesWindows addObject:self];
        SHIM_LOG("NSWindow %s requested %.0fx%.0f, using full screen", class_getName(self.class),
                 rect.size.width, rect.size.height);
    }
    return self;
}

- (instancetype)initWithContentRect:(NSRect)rect styleMask:(NSWindowStyleMask)style backing:(NSUInteger)backing defer:(BOOL)defer
{
    return [self initWithContentRect:rect styleMask:style backing:backing defer:defer screen:nil];
}

- (void)setContentView:(NSView *)v
{
    [_contentView.hostView removeFromSuperview];
    _contentView = v;
    v.window = self;
    [self hades_attach];
}

- (void)hades_attach
{
    UIView *root = HadesRootViewController.view;
    UIView *host = _contentView.hostView;
    if (!root || !host) return;
    host.frame = HadesGameAreaInRoot();   // re-applied on every root layout (hades_postResize)
    [root addSubview:host];
    [root layoutIfNeeded];
}

- (void)hades_postResize
{
    _contentView.hostView.frame = HadesGameAreaInRoot();
    CGSize s = HadesScreenBoundsLandscape().size;
    if (CGSizeEqualToSize(s, _lastSize)) return;
    _lastSize = s;
    SHIM_LOG("window resize -> %.0fx%.0f pt", s.width, s.height);
    NotifyDelegate(self, @selector(windowDidResize:), @"NSWindowDidResizeNotification");
}

- (NSRect)frame { return HadesScreenBoundsLandscape(); }
- (NSRect)contentRectForFrameRect:(NSRect)r { return r; }
- (NSRect)frameRectForContentRect:(NSRect)r { return r; }
- (NSRect)contentLayoutRect { return HadesScreenBoundsLandscape(); }
- (NSRect)convertRectToScreen:(NSRect)r { return r; }
- (NSRect)convertRectFromScreen:(NSRect)r { return r; }
- (NSPoint)mouseLocationOutsideOfEventStream { return CGPointZero; }
- (void)setFrame:(NSRect)f display:(BOOL)d {}
- (void)setFrame:(NSRect)f display:(BOOL)d animate:(BOOL)a {}
- (void)setFrameOrigin:(NSPoint)p {}
- (void)setContentSize:(NSSize)s {}
- (void)setMinSize:(NSSize)s {}
- (void)setTitle:(NSString *)t {}
- (void)setLevel:(NSInteger)l {}
- (void)setCollectionBehavior:(NSUInteger)b {}
- (void)setAcceptsMouseMovedEvents:(BOOL)b {}
- (void)setRestorable:(BOOL)b {}
- (void)setReleasedWhenClosed:(BOOL)b {}
- (void)setOpaque:(BOOL)b {}
- (void)invalidateRestorableState {}
- (void)center {}
- (void)update {}
- (BOOL)isZoomed { return YES; }
- (BOOL)inLiveResize { return NO; }
- (BOOL)isVisible { return YES; }
- (BOOL)isKeyWindow { return YES; }
- (BOOL)isMainWindow { return YES; }
- (BOOL)isMiniaturized { return NO; }
- (NSUInteger)occlusionState { return 1 << 1; }   // NSWindowOcclusionStateVisible
- (NSInteger)windowNumber { return 1; }
- (id)standardWindowButton:(NSUInteger)b { return nil; }
- (NSScreen *)screen { return NSScreen.mainScreen; }
- (CGFloat)backingScaleFactor { return HadesBackingScale(); }
- (id)firstResponder { return _contentView; }
- (BOOL)makeFirstResponder:(id)r { return YES; }
- (void)close { [HadesWindows removeObject:self]; }

- (void)makeKeyAndOrderFront:(id)sender
{
    [self hades_attach];
    NotifyDelegate(self, @selector(windowDidBecomeKey:), NSWindowDidBecomeKeyNotification);
    NotifyDelegate(self, @selector(windowDidBecomeMain:), NSWindowDidBecomeMainNotification);
    [self hades_postResize];
}

- (void)makeMainWindow { NotifyDelegate(self, @selector(windowDidBecomeMain:), NSWindowDidBecomeMainNotification); }
- (void)orderFront:(id)sender { [self makeKeyAndOrderFront:sender]; }

- (void)toggleFullScreen:(id)sender
{
    BOOL entering = !(_styleMask & NSWindowStyleMaskFullScreen);
    _styleMask ^= NSWindowStyleMaskFullScreen;
    NotifyDelegate(self, entering ? @selector(windowDidEnterFullScreen:) : @selector(windowDidExitFullScreen:),
                   entering ? @"NSWindowDidEnterFullScreenNotification" : @"NSWindowDidExitFullScreenNotification");
}
@end

#pragma mark - NSScreen

@implementation NSScreen
HADES_CATCH_ALL
+ (NSScreen *)mainScreen
{
    static NSScreen *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSScreen new]; });
    return s;
}
+ (NSArray *)screens { return @[ self.mainScreen ]; }
- (NSRect)frame { return HadesScreenBoundsLandscape(); }
- (NSRect)visibleFrame { return HadesScreenBoundsLandscape(); }
- (CGFloat)backingScaleFactor { return HadesBackingScale(); }
- (NSString *)localizedName { return UIDevice.currentDevice.name; }
- (NSInteger)maximumFramesPerSecond { return UIScreen.mainScreen.maximumFramesPerSecond; }
- (NSDictionary *)deviceDescription
{
    CGRect b = HadesScreenBoundsLandscape();
    return @{ @"NSScreenNumber": @1, @"NSDeviceSize": [NSValue valueWithCGSize:b.size] };
}
@end
