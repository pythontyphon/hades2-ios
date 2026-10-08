// Small AppKit classes: cursor/image (no cursor on iOS), pasteboard, alerts, workspace.
#import "AppKitShim.h"

NSNotificationName const NSWorkspaceDidActivateApplicationNotification = @"NSWorkspaceDidActivateApplicationNotification";
NSNotificationName const NSWorkspaceDidDeactivateApplicationNotification = @"NSWorkspaceDidDeactivateApplicationNotification";

@interface NSImage : NSObject
@end
@implementation NSImage
HADES_CATCH_ALL
- (instancetype)initWithContentsOfFile:(NSString *)p { return [super init]; }
- (instancetype)initByReferencingFile:(NSString *)p { return [super init]; }
- (instancetype)initWithData:(NSData *)d { return [super init]; }
- (NSArray *)representations { return @[]; }
- (NSSize)size { return CGSizeMake(32, 32); }
@end

@interface NSCursor : NSObject
@end
@implementation NSCursor
HADES_CATCH_ALL
+ (instancetype)arrowCursor { return [self new]; }
+ (void)hide {}
+ (void)unhide {}
+ (void)setHiddenUntilMouseMoves:(BOOL)b {}
- (instancetype)initWithImage:(id)image hotSpot:(NSPoint)p { return [super init]; }
- (void)set {}
- (void)push {}
- (void)pop {}
@end

@interface NSTrackingArea : NSObject
@end
@implementation NSTrackingArea
HADES_CATCH_ALL
- (instancetype)initWithRect:(NSRect)r options:(NSUInteger)o owner:(id)owner userInfo:(NSDictionary *)u { return [super init]; }
@end

@interface NSPasteboard : NSObject
@end
@implementation NSPasteboard
HADES_CATCH_ALL
+ (instancetype)generalPasteboard { return [self new]; }
- (NSInteger)clearContents { UIPasteboard.generalPasteboard.items = @[]; return 0; }
- (BOOL)writeObjects:(NSArray *)objs
{
    NSMutableArray *strings = [NSMutableArray new];
    for (id o in objs) if ([o isKindOfClass:NSString.class]) [strings addObject:o];
    UIPasteboard.generalPasteboard.strings = strings;
    return YES;
}
@end

@interface NSAlert : NSObject
@property (nonatomic, copy) NSString *messageText;
@property (nonatomic, copy) NSString *informativeText;
@property (nonatomic) NSUInteger alertStyle;
@end
@implementation NSAlert {
    NSMutableArray<NSString *> *_buttons;
}
HADES_CATCH_ALL
- (instancetype)init { if ((self = [super init])) _buttons = [NSMutableArray new]; return self; }
- (id)addButtonWithTitle:(NSString *)t { [_buttons addObject:t ?: @"OK"]; return nil; }

// Modal: present a UIAlertController and spin the run loop until a button is tapped.
- (NSInteger)runModal
{
    SHIM_LOG("NSAlert: %s - %s", _messageText.UTF8String, _informativeText.UTF8String);
    UIViewController *root = HadesRootViewController;
    if (!root) return 1000;
    __block NSInteger result = -1;
    UIAlertController *a = [UIAlertController alertControllerWithTitle:_messageText message:_informativeText
                                                        preferredStyle:UIAlertControllerStyleAlert];
    NSArray *titles = _buttons.count ? _buttons : @[ @"OK" ];
    [titles enumerateObjectsUsingBlock:^(NSString *t, NSUInteger i, BOOL *stop) {
        [a addAction:[UIAlertAction actionWithTitle:t style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *x) { result = 1000 + (NSInteger)i; }]];
    }];
    [root presentViewController:a animated:YES completion:nil];
    while (result < 0) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, false);
    return result;   // NSAlertFirstButtonReturn = 1000
}
@end

@interface NSRunningApplication : NSObject
@end
@implementation NSRunningApplication
HADES_CATCH_ALL
+ (instancetype)currentApplication { static id a; static dispatch_once_t o; dispatch_once(&o, ^{ a = [self new]; }); return a; }
- (BOOL)activateWithOptions:(NSUInteger)o { return YES; }
- (BOOL)isActive { return !HadesAppInBackground; }
- (NSString *)localizedName { return @"Hades II"; }
- (NSString *)bundleIdentifier { return NSBundle.mainBundle.bundleIdentifier; }
@end

@interface NSWorkspace : NSObject
@end
@implementation NSWorkspace
HADES_CATCH_ALL
+ (instancetype)sharedWorkspace { static id w; static dispatch_once_t o; dispatch_once(&o, ^{ w = [self new]; }); return w; }
- (NSNotificationCenter *)notificationCenter
{
    static NSNotificationCenter *c; static dispatch_once_t o;
    dispatch_once(&o, ^{ c = [NSNotificationCenter new]; });
    return c;
}
- (BOOL)openURL:(NSURL *)u
{
    dispatch_async(dispatch_get_main_queue(), ^{ [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil]; });
    return YES;
}
@end
