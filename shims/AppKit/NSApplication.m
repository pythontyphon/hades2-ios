// NSApplicationMain -> UIApplicationMain. Once the window scene connects, the game's own
// AppDelegate gets applicationDidFinishLaunching:, which never returns: it runs the Forge
// loop `while (shouldRun) { drain [NSApp nextEventMatchingMask:...]; [controller draw]; }`.
// nextEventMatchingMask: pumps the UIKit run loop and never yields an NSEvent.
#import <objc/message.h>
#import <objc/runtime.h>
#import "AppKitShim.h"

id NSApp;
UIViewController *HadesRootViewController;
BOOL HadesAppInBackground;
NSMutableArray<NSWindow *> *HadesWindows;

NSNotificationName const NSApplicationWillTerminateNotification = @"NSApplicationWillTerminateNotification";
NSNotificationName const NSApplicationDidBecomeActiveNotification = @"NSApplicationDidBecomeActiveNotification";
NSNotificationName const NSApplicationDidResignActiveNotification = @"NSApplicationDidResignActiveNotification";

static void CallDelegate(SEL sel, NSString *notificationName)
{
    NSNotification *n = [NSNotification notificationWithName:notificationName object:NSApp];
    id d = [NSApp delegate];
    if ([d respondsToSelector:sel])
        ((void (*)(id, SEL, id))objc_msgSend)(d, sel, n);
    [NSNotificationCenter.defaultCenter postNotification:n];
}

@implementation NSApplication
HADES_CATCH_ALL

+ (instancetype)sharedApplication
{
    if (!NSApp) NSApp = [[self alloc] init];
    return NSApp;
}

- (id)nextEventMatchingMask:(unsigned long long)mask untilDate:(NSDate *)date inMode:(NSString *)mode dequeue:(BOOL)dequeue
{
    // While backgrounded, block here so the game stops submitting GPU work (iOS kills apps
    // that use the GPU in the background) and resumes seamlessly when foregrounded.
    while (HadesAppInBackground)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.25, false);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0, false);
    return nil;
}

- (void)sendEvent:(id)event {}
- (void)activateIgnoringOtherApps:(BOOL)flag {}
- (void)hide:(id)sender {}
- (void)unhide:(id)sender {}
- (NSArray *)windows { return [HadesWindows copy]; }
- (NSWindow *)mainWindow { return HadesWindows.lastObject; }
- (NSWindow *)keyWindow { return HadesWindows.lastObject; }
- (BOOL)isActive { return !HadesAppInBackground; }
- (void)stopModal {}
- (long)runModalForWindow:(NSWindow *)w { SHIM_LOG("runModalForWindow: ignored"); return 0; }
- (BOOL)tryToPerform:(SEL)action with:(id)object { return NO; }

- (void)terminate:(id)sender
{
    SHIM_LOG("NSApp terminate:");
    CallDelegate(@selector(applicationWillTerminate:), NSApplicationWillTerminateNotification);
    exit(0);
}
@end

#pragma mark - UIKit side

void HadesInstallTouchControls(UIWindow *window);

@interface HadesRootVC : UIViewController
@end

@implementation HadesRootVC
- (void)loadView
{
    self.view = [UIView new];
    self.view.backgroundColor = UIColor.blackColor;
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (void)viewSafeAreaInsetsDidChange
{
    [super viewSafeAreaInsetsDidChange];
    for (NSWindow *w in HadesWindows) [w hades_postResize];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    for (NSWindow *w in HadesWindows) [w hades_postResize];
}
@end

@interface HadesUIAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface HadesSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) CADisplayLink *rateVote;
@end

static BOOL gGameStarted;

@implementation HadesUIAppDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts
{
    HadesWindows = [NSMutableArray new];
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSString *principal = info[@"HadesPrincipalClass"] ?: @"ForgeApplication";
    NSString *delegateName = info[@"HadesAppDelegateClass"] ?: @"AppDelegate";
    Class appClass = NSClassFromString(principal) ?: NSApplication.class;
    [appClass sharedApplication];
    // MainMenu.nib on macOS instantiates AppDelegate and wires it up; do that by hand.
    Class delegateClass = NSClassFromString(delegateName);
    [NSApp setDelegate:[[delegateClass alloc] init]];
    SHIM_LOG("launch: NSApp=%s delegate=%s", class_getName([NSApp class]), class_getName(delegateClass));
    app.idleTimerDisabled = YES;
    return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session
                              options:(UISceneConnectionOptions *)options
{
    UISceneConfiguration *c = [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
    c.delegateClass = HadesSceneDelegate.class;
    return c;
}
@end

@implementation HadesSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)opts
{
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    HadesRootViewController = [HadesRootVC new];
    self.window.rootViewController = HadesRootViewController;
    [self.window makeKeyAndVisible];
    HadesInstallTouchControls(self.window);
    // ProMotion keeps a Metal app at 60 Hz unless it asks for more. This display link does no work;
    // it only votes for the frame rate (HadesTargetFPS, default 120), so nextDrawable paces at that rate.
    NSInteger fps = [NSUserDefaults.standardUserDefaults integerForKey:@"HadesTargetFPS"];
    if (fps <= 0) fps = 120;
    self.rateVote = [CADisplayLink displayLinkWithTarget:self selector:@selector(rateVoteTick:)];
    self.rateVote.preferredFrameRateRange = CAFrameRateRangeMake(MIN(fps, 80), fps, fps);
    [self.rateVote addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    SHIM_LOG("display: requesting %ld Hz", (long)fps);
    // Start the game from a run-loop timer (not a main-queue block) so its nested run-loop
    // pumping can still service the main dispatch queue. Same trick SDL uses on iOS.
    if (!gGameStarted) {
        gGameStarted = YES;
        [self performSelector:@selector(startGame) withObject:nil afterDelay:0];
    }
}

- (void)rateVoteTick:(CADisplayLink *)link {}

- (void)startGame
{
    SHIM_LOG("starting game loop");
    CallDelegate(@selector(applicationWillFinishLaunching:), @"NSApplicationWillFinishLaunchingNotification");
    CallDelegate(@selector(applicationDidFinishLaunching:), @"NSApplicationDidFinishLaunchingNotification");
    SHIM_LOG("game loop returned; exiting");
    exit(0);
}

- (void)sceneDidBecomeActive:(UIScene *)scene
{
    HadesAppInBackground = NO;
    CallDelegate(@selector(applicationDidBecomeActive:), NSApplicationDidBecomeActiveNotification);
}

- (void)sceneWillResignActive:(UIScene *)scene
{
    CallDelegate(@selector(applicationDidResignActive:), NSApplicationDidResignActiveNotification);
}

- (void)sceneDidEnterBackground:(UIScene *)scene { HadesAppInBackground = YES; }
- (void)sceneWillEnterForeground:(UIScene *)scene { HadesAppInBackground = NO; }
@end

int NSApplicationMain(int argc, const char *argv[])
{
    SHIM_LOG("NSApplicationMain -> UIApplicationMain");
    @autoreleasepool {
        return UIApplicationMain(argc, (char **)argv, nil, NSStringFromClass(HadesUIAppDelegate.class));
    }
}
