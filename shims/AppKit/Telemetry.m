// Session telemetry that survives being unplugged:
//  - stdout+stderr are tee'd to Documents/Logs/session.log (previous run kept as session.prev.log)
//  - frame pacing: CAMetalLayer -nextDrawable is counted; every 2 s log fps, worst frame and footprint
//  - controller connect/disconnect events
#import <GameController/GameController.h>
#import <QuartzCore/CAMetalLayer.h>
#import <mach/mach.h>
#import <mach/mach_time.h>
#import <objc/runtime.h>
#import <pthread.h>
#import "AppKitShim.h"

static int sOrigOut = -1, sOrigErr = -1, sLogFile = -1;

static void *TeeThread(void *arg)
{
    int fd = (int)(intptr_t)arg;
    char buf[16384];
    ssize_t n;
    while ((n = read(fd, buf, sizeof buf)) > 0) {
        write(sOrigErr, buf, n);
        if (sLogFile >= 0) write(sLogFile, buf, n);
    }
    return NULL;
}

static void StartTee(void)
{
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/Logs"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *cur = [dir stringByAppendingPathComponent:@"session.log"];
    NSString *prev = [dir stringByAppendingPathComponent:@"session.prev.log"];
    [NSFileManager.defaultManager removeItemAtPath:prev error:nil];
    [NSFileManager.defaultManager moveItemAtPath:cur toPath:prev error:nil];
    sLogFile = open(cur.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);

    sOrigOut = dup(STDOUT_FILENO);
    sOrigErr = dup(STDERR_FILENO);
    int p[2];
    if (pipe(p) != 0) return;
    dup2(p[1], STDOUT_FILENO);
    dup2(p[1], STDERR_FILENO);
    close(p[1]);
    setvbuf(stdout, NULL, _IOLBF, 0);
    pthread_t t;
    pthread_create(&t, NULL, TeeThread, (void *)(intptr_t)p[0]);
    pthread_detach(t);
}

#pragma mark - Frame pacing

static IMP sNextDrawable;
static uint64_t sLastFrame, sWindowStart, sWorst, sBlocked;
static unsigned sFrames;
static double sTicksToMs;

static void *LayerNextDrawable(id self, SEL _cmd)
{
    uint64_t now = mach_absolute_time();
    if (sLastFrame) {
        uint64_t dt = now - sLastFrame;
        if (dt > sWorst) sWorst = dt;
    }
    sLastFrame = now;
    sFrames++;
    if (!sWindowStart) sWindowStart = now;
    double windowMs = (now - sWindowStart) * sTicksToMs;
    if (windowMs >= 2000) {
        task_vm_info_data_t vm;
        mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
        task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &n);
        SHIM_LOG("perf: %.1f fps, worst frame %.1f ms, avg nextDrawable wait %.2f ms, footprint %llu MB, thermal %ld",
                 sFrames * 1000.0 / windowMs, sWorst * sTicksToMs, sBlocked * sTicksToMs / MAX(sFrames, 1),
                 vm.phys_footprint >> 20, (long)NSProcessInfo.processInfo.thermalState);
        sFrames = 0; sWorst = 0; sBlocked = 0; sWindowStart = now;
    }
    void *d = ((void *(*)(id, SEL))sNextDrawable)(self, _cmd);
    sBlocked += mach_absolute_time() - now;
    return d;
}

static void StartFramePacing(void)
{
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    sTicksToMs = (double)tb.numer / tb.denom / 1e6;
    Method m = class_getInstanceMethod(CAMetalLayer.class, @selector(nextDrawable));
    sNextDrawable = method_setImplementation(m, (IMP)LayerNextDrawable);
}

static void WatchControllers(void)
{
    [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidConnectNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *n) {
        GCController *c = n.object;
        SHIM_LOG("controller connected: %s (%s)", c.vendorName.UTF8String, c.productCategory.UTF8String);
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:GCControllerDidDisconnectNotification object:nil queue:nil
                                                usingBlock:^(NSNotification *n) {
        SHIM_LOG("controller disconnected: %s", [n.object vendorName].UTF8String);
    }];
}

__attribute__((constructor(101))) static void TelemetryInit(void)
{
    StartTee();
    StartFramePacing();
    WatchControllers();
}
