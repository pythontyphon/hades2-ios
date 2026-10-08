#import <objc/runtime.h>
#import "AppKitShim.h"

void HadesCatchAllLog(id self, SEL _cmd)
{
    static NSMutableSet *seen;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet new]; });
    NSString *key = [NSString stringWithFormat:@"%s %s", class_getName(object_getClass(self)), sel_getName(_cmd)];
    @synchronized (seen) {
        if ([seen containsObject:key]) return;
        [seen addObject:key];
    }
    SHIM_LOG("AppKit unimplemented: %s", key.UTF8String);
}

// Zero x0/x1 and d0-d3 after logging, so id/int/BOOL/NSRect returns all read as 0.
__attribute__((naked)) static void CatchAllIMP(void)
{
    __asm__ volatile(
        "stp x29, x30, [sp, #-16]!\n"
        "mov x29, sp\n"
        "bl _HadesCatchAllLog\n"
        "ldp x29, x30, [sp], #16\n"
        "mov x0, #0\n"
        "mov x1, #0\n"
        "movi d0, #0\n"
        "movi d1, #0\n"
        "movi d2, #0\n"
        "movi d3, #0\n"
        "ret\n");
}

void HadesShimInstallCatchAllFor(Class cls, SEL sel, BOOL isClassMethod)
{
    Class target = isClassMethod ? object_getClass(cls) : cls;
    class_addMethod(target, sel, (IMP)CatchAllIMP, "@@:");
}
