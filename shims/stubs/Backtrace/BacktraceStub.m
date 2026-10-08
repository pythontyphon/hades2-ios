// Replacement for Backtrace.framework (crash reporting). The game only touches these classes
// through ObjC messaging, so each is a catch-all: any message is accepted, logged once, and
// returns nil/0. Object-returning init*/shared calls get a live instance so chains don't break.
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include "../../common/shimlog.h"

@interface HadesBacktraceStub : NSObject
@end

@implementation HadesBacktraceStub
static id StubIMP(id self, SEL _cmd, ...)
{
    const char *n = sel_getName(_cmd);
    SHIM_LOG("Backtrace stub: %s %s", class_getName(object_getClass(self)), n);
    if (!strncmp(n, "init", 4)) return self;
    if (!strcmp(n, "shared")) return [[[(Class)self class] alloc] init];
    return nil;
}
+ (BOOL)resolveInstanceMethod:(SEL)sel
{
    class_addMethod(self, sel, (IMP)StubIMP, "@@:");
    return YES;
}
+ (BOOL)resolveClassMethod:(SEL)sel
{
    class_addMethod(object_getClass(self), sel, (IMP)StubIMP, "@@:");
    return YES;
}
@end

// Names match the Swift classes' ObjC runtime names (Backtrace module).
@interface _TtC9Backtrace15BacktraceClient : HadesBacktraceStub @end
@implementation _TtC9Backtrace15BacktraceClient @end
@interface _TtC9Backtrace20BacktraceCredentials : HadesBacktraceStub @end
@implementation _TtC9Backtrace20BacktraceCredentials @end
@interface _TtC9Backtrace24BacktraceMetricsSettings : HadesBacktraceStub @end
@implementation _TtC9Backtrace24BacktraceMetricsSettings @end
@interface _TtC9Backtrace25BacktraceDatabaseSettings : HadesBacktraceStub @end
@implementation _TtC9Backtrace25BacktraceDatabaseSettings @end
@interface _TtC9Backtrace28BacktraceClientConfiguration : HadesBacktraceStub @end
@implementation _TtC9Backtrace28BacktraceClientConfiguration @end
