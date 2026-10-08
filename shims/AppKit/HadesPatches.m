// Runtime fixes for running the macOS build on iOS, installed when the AppKit shim loads:
//  - Metal: macOS-only API (Managed storage, isLowPower, macOS feature sets, displaySyncEnabled)
//  - NSBundle: the game finds Content/ via [[NSBundle mainBundle] resourceURL]; point that at
//    Documents/ (where the content is pushed once) for calls made from the game binary only.
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#import <objc/runtime.h>
#import "AppKitShim.h"

static void AddMethod(Class c, SEL sel, IMP imp, const char *types)
{
    if (!class_addMethod(c, sel, imp, types))
        SHIM_LOG("patch: %s already has %s", class_getName(c), sel_getName(sel));
}

static IMP Swizzle(Class c, SEL sel, IMP imp)
{
    Method m = class_getInstanceMethod(c, sel);
    if (!m) { SHIM_LOG("patch: %s lacks %s", class_getName(c), sel_getName(sel)); return NULL; }
    if (class_addMethod(c, sel, imp, method_getTypeEncoding(m)))   // was inherited: wrap the inherited one
        return method_getImplementation(m);
    return method_setImplementation(m, imp);
}

#pragma mark - Metal

// Wrappers for new*/copy* methods return `void *` and call the originals through `void *`-returning
// casts so ARC adds no retain/autorelease: the engine creates per-frame buffers on its own render
// thread, which has no draining autorelease pool, and an ARC autorelease there leaks every buffer.
static _Atomic unsigned long long gBufCount, gBufBytes, gTexCount, gTexBytes;

#define MTLStorageModeManaged_ 1
#define MTLResourceStorageModeMask_ 0xF0
#define MTLResourceStorageModeManaged_ (MTLStorageModeManaged_ << MTLResourceStorageModeShift)

static MTLResourceOptions FixOptions(MTLResourceOptions o)
{
    if ((o & MTLResourceStorageModeMask_) == MTLResourceStorageModeManaged_) {
        SHIM_LOG_ONCE("metal: Managed storage -> Shared");
        o &= ~(MTLResourceOptions)MTLResourceStorageModeMask_;   // Shared == 0
    }
    return o;
}

static IMP sBufLen, sBufBytes, sBufNoCopy, sTexSetStorage, sTexSetOpts, sHeapSetStorage, sHeapBuf, sHeapBufOff;
static IMP sSupportsFeatureSet, sNewHeap, sNewTex;

static void *DevNewHeap(id s, SEL c, MTLHeapDescriptor *d)
{
    static _Atomic int count;
    int n = ++count;
    SHIM_VLOG("metal: heap %.1f MB (storage %lu, type %ld)", d.size / 1048576.0, (unsigned long)d.storageMode, (long)d.type);
    if (HadesVerbose() && (n == 50 || n == 120))
        SHIM_LOG("metal: heap #%d created from:\n%s", n, [NSThread.callStackSymbols componentsJoinedByString:@"\n"].UTF8String);
    return ((void * (*)(id, SEL, id))sNewHeap)(s, c, d);
}

static void *DevNewTexture(id s, SEL c, MTLTextureDescriptor *d)
{
    MTLSizeAndAlign sa = [(id<MTLDevice>)s heapTextureSizeAndAlignWithDescriptor:d];
    gTexCount++; gTexBytes += sa.size;
    if (sa.size >= (32u << 20))
        SHIM_LOG("metal: texture %lux%lu fmt %lu %.1f MB", (unsigned long)d.width, (unsigned long)d.height,
                 (unsigned long)d.pixelFormat, sa.size / 1048576.0);
    return ((void * (*)(id, SEL, id))sNewTex)(s, c, d);
}

#define BIG (32u << 20)
static void LogBig(const char *what, NSUInteger len)
{
    static _Atomic unsigned long long total;
    total += len;
    if (len >= BIG) SHIM_LOG("metal: %s %.1f MB (big-alloc total %.1f MB)", what, len / 1048576.0, total / 1048576.0);
}

static void *DevNewBufferLen(id s, SEL c, NSUInteger len, MTLResourceOptions o)
{ LogBig("buffer", len); gBufCount++; gBufBytes += len; return ((void * (*)(id, SEL, NSUInteger, MTLResourceOptions))sBufLen)(s, c, len, FixOptions(o)); }
static void *DevNewBufferBytes(id s, SEL c, const void *p, NSUInteger len, MTLResourceOptions o)
{ gBufCount++; gBufBytes += len; return ((void * (*)(id, SEL, const void *, NSUInteger, MTLResourceOptions))sBufBytes)(s, c, p, len, FixOptions(o)); }
static void *DevNewBufferNoCopy(id s, SEL c, void *p, NSUInteger len, MTLResourceOptions o, id dealloc)
{ return ((void * (*)(id, SEL, void *, NSUInteger, MTLResourceOptions, id))sBufNoCopy)(s, c, p, len, FixOptions(o), dealloc); }
static void *HeapNewBuffer(id s, SEL c, NSUInteger len, MTLResourceOptions o)
{ return ((void * (*)(id, SEL, NSUInteger, MTLResourceOptions))sHeapBuf)(s, c, len, FixOptions(o)); }
static void *HeapNewBufferOff(id s, SEL c, NSUInteger len, MTLResourceOptions o, NSUInteger off)
{
    void *b = ((void * (*)(id, SEL, NSUInteger, MTLResourceOptions, NSUInteger))sHeapBufOff)(s, c, len, FixOptions(o), off);
    if (!b) SHIM_LOG("metal: heap placement of buffer %lu @%lu FAILED (opts 0x%lx)", (unsigned long)len, (unsigned long)off, (unsigned long)o);
    return b;
}

static IMP sHeapTexOff;
static void *HeapNewTextureOff(id s, SEL c, MTLTextureDescriptor *d, NSUInteger off)
{
    void *t = ((void * (*)(id, SEL, id, NSUInteger))sHeapTexOff)(s, c, d, off);
    gTexCount++;
    if (!t) SHIM_LOG("metal: heap placement of texture %lux%lu fmt %lu storage %lu @%lu FAILED (heap storage %lu)",
                     (unsigned long)d.width, (unsigned long)d.height, (unsigned long)d.pixelFormat,
                     (unsigned long)d.storageMode, (unsigned long)off, (unsigned long)[(id<MTLHeap>)s storageMode]);
    return t;
}

// The game sizes its GPU budgets from this (it saw 8 GB and allocated like a desktop GPU), but an
// iOS process dies at its jetsam limit (6 GB here, shared by CPU and GPU). Default 3 GB; tune with
// `defaults`-style key HadesWorkingSetMB.
static uint64_t DevWorkingSet(id s, SEL c)
{
    NSInteger mb = [NSUserDefaults.standardUserDefaults integerForKey:@"HadesWorkingSetMB"];
    return (uint64_t)(mb > 0 ? mb : 3072) << 20;
}

static void TexSetStorage(id s, SEL c, MTLStorageMode m)
{ ((void (*)(id, SEL, MTLStorageMode))sTexSetStorage)(s, c, m == MTLStorageModeManaged_ ? MTLStorageModeShared : m); }
static void TexSetOpts(id s, SEL c, MTLResourceOptions o)
{ ((void (*)(id, SEL, MTLResourceOptions))sTexSetOpts)(s, c, FixOptions(o)); }
static void HeapSetStorage(id s, SEL c, MTLStorageMode m)
{ ((void (*)(id, SEL, MTLStorageMode))sHeapSetStorage)(s, c, m == MTLStorageModeManaged_ ? MTLStorageModeShared : m); }

static BOOL DevIsLowPower(id s, SEL c) { return NO; }
static BOOL DevD24S8(id s, SEL c) { return NO; }
static BOOL DevSupportsFeatureSet(id s, SEL c, NSUInteger fs)
{
    // MTLFeatureSet_macOS_GPUFamily1_v1 (10000) ... macOS_GPUFamily2_v1 (10005): Apple GPUs cover them.
    // Must stay bounded: the renderer counts up from 9999 while this returns YES.
    if (fs >= 10000) return fs <= 10005;
    return sSupportsFeatureSet ? ((BOOL (*)(id, SEL, NSUInteger))sSupportsFeatureSet)(s, c, fs) : NO;
}
static void LayerSetDisplaySync(id s, SEL c, BOOL b) {}
static BOOL LayerDisplaySync(id s, SEL c) { return YES; }

static IMP sNewLibData, sNewFunc;

static void *DevNewLibraryWithData(id s, SEL c, dispatch_data_t data, NSError **err)
{
    NSError *e = nil;
    void *lib = ((void * (*)(id, SEL, dispatch_data_t, NSError **))sNewLibData)(s, c, data, &e);
    if (!lib) SHIM_LOG("metal: newLibraryWithData failed (%zu bytes): %s", dispatch_data_get_size(data),
                       e.localizedDescription.UTF8String);
    if (err) *err = e;
    return lib;
}

static void *LibNewFunction(id s, SEL c, NSString *name)
{
    void *f = ((void * (*)(id, SEL, NSString *))sNewFunc)(s, c, name);
    if (!f) SHIM_LOG("metal: function '%s' not found; library has: %s", name.UTF8String,
                     [[s functionNames] componentsJoinedByString:@","].UTF8String);
    return f;
}

static void PatchMetal(void)
{
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    Class dc = object_getClass(dev);
    SHIM_LOG("metal: %s (%s), BC textures: %s", dev.name.UTF8String, class_getName(dc),
             dev.supportsBCTextureCompression ? "yes" : "NO");
    sBufLen = Swizzle(dc, @selector(newBufferWithLength:options:), (IMP)DevNewBufferLen);
    sBufBytes = Swizzle(dc, @selector(newBufferWithBytes:length:options:), (IMP)DevNewBufferBytes);
    sBufNoCopy = Swizzle(dc, @selector(newBufferWithBytesNoCopy:length:options:deallocator:), (IMP)DevNewBufferNoCopy);
    sNewHeap = Swizzle(dc, @selector(newHeapWithDescriptor:), (IMP)DevNewHeap);
    sNewTex = Swizzle(dc, @selector(newTextureWithDescriptor:), (IMP)DevNewTexture);
    SHIM_LOG("metal: real recommendedMaxWorkingSetSize %.0f MB", dev.recommendedMaxWorkingSetSize / 1048576.0);
    Swizzle(dc, @selector(recommendedMaxWorkingSetSize), (IMP)DevWorkingSet);
    sNewLibData = Swizzle(dc, @selector(newLibraryWithData:error:), (IMP)DevNewLibraryWithData);
    id<MTLLibrary> probe = [dev newLibraryWithSource:@"kernel void k(){}" options:nil error:nil];
    if (probe) sNewFunc = Swizzle(object_getClass(probe), @selector(newFunctionWithName:), (IMP)LibNewFunction);
    AddMethod(dc, @selector(isLowPower), (IMP)DevIsLowPower, "B@:");
    AddMethod(dc, @selector(isDepth24Stencil8PixelFormatSupported), (IMP)DevD24S8, "B@:");
    if (class_getInstanceMethod(dc, @selector(supportsFeatureSet:)))
        sSupportsFeatureSet = Swizzle(dc, @selector(supportsFeatureSet:), (IMP)DevSupportsFeatureSet);
    else
        AddMethod(dc, @selector(supportsFeatureSet:), (IMP)DevSupportsFeatureSet, "B@:Q");

    Class tdc = object_getClass([MTLTextureDescriptor new]);
    sTexSetStorage = Swizzle(tdc, @selector(setStorageMode:), (IMP)TexSetStorage);
    sTexSetOpts = Swizzle(tdc, @selector(setResourceOptions:), (IMP)TexSetOpts);
    Class hdc = object_getClass([MTLHeapDescriptor new]);
    sHeapSetStorage = Swizzle(hdc, @selector(setStorageMode:), (IMP)HeapSetStorage);

    MTLHeapDescriptor *hd = [MTLHeapDescriptor new];
    hd.size = 1 << 16;
    id<MTLHeap> heap = [dev newHeapWithDescriptor:hd];
    if (heap) {
        Class hc = object_getClass(heap);
        sHeapBuf = Swizzle(hc, @selector(newBufferWithLength:options:), (IMP)HeapNewBuffer);
        sHeapBufOff = Swizzle(hc, @selector(newBufferWithLength:options:offset:), (IMP)HeapNewBufferOff);
        sHeapTexOff = Swizzle(hc, @selector(newTextureWithDescriptor:offset:), (IMP)HeapNewTextureOff);
    }

    AddMethod(CAMetalLayer.class, @selector(setDisplaySyncEnabled:), (IMP)LayerSetDisplaySync, "v@:B");
    AddMethod(CAMetalLayer.class, @selector(displaySyncEnabled), (IMP)LayerDisplaySync, "B@:");
}

#pragma mark - Reported RAM

// The game picks 1080p vs 720p packages, VO streaming and quality presets from hw.memsize
// ("720p packages because totalRam < 9000 mb"). An iOS app can only use its jetsam limit (6 GB
// here), not the phone's 12 GB. HadesAssetSet = "1080p" (default) reports 9216 MB, just above that
// line, and forces voice-bank streaming via settings (see SyncSettings); "720p" reports 8192 MB,
// which makes the game take its own low-memory path. HadesReportedRAMMB overrides both.
static BOOL HadesWantsLowResAssets(void)
{
    return [[NSUserDefaults.standardUserDefaults stringForKey:@"HadesAssetSet"] isEqualToString:@"720p"];
}
static BOOL CalledFromGame(void *ret);

static int HadesSysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen)
{
    void *ret = __builtin_return_address(0);
    int r = sysctl(name, namelen, oldp, oldlenp, newp, newlen);
    if (r == 0 && namelen >= 2 && name[0] == CTL_HW && name[1] == HW_MEMSIZE && oldp && oldlenp &&
        *oldlenp == sizeof(uint64_t) && CalledFromGame(ret)) {
        NSInteger mb = [NSUserDefaults.standardUserDefaults integerForKey:@"HadesReportedRAMMB"];
        if (mb <= 0) mb = HadesWantsLowResAssets() ? 8192 : 9216;
        *(uint64_t *)oldp = (uint64_t)mb << 20;
        SHIM_LOG_ONCE("hw.memsize reported to game as %llu MB", *(uint64_t *)oldp >> 20);
    }
    return r;
}

__attribute__((used, section("__DATA,__interpose"))) static const struct { const void *replacement, *original; }
    sInterposeSysctl = { (const void *)HadesSysctl, (const void *)sysctl };

#pragma mark - Content redirect

static const struct mach_header *sMainHeader;
static uintptr_t sMainStart, sMainEnd;
static IMP sResourceURL, sResourcePath;

static BOOL CalledFromGame(void *ret)
{
    return (uintptr_t)ret >= sMainStart && (uintptr_t)ret < sMainEnd;
}

static NSURL *ContentRoot(void)
{
    static NSURL *u;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        u = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        BOOL dir = NO;
        BOOL ok = [NSFileManager.defaultManager fileExistsAtPath:[u.path stringByAppendingPathComponent:@"Content"] isDirectory:&dir] && dir;
        SHIM_LOG("content root: %s (Content/ %s)", u.path.UTF8String, ok ? "present" : "MISSING - push it with tools/sync_content.py");
    });
    return u;
}

__attribute__((noinline)) static NSURL *BundleResourceURL(NSBundle *s, SEL c)
{
    if (s == NSBundle.mainBundle && CalledFromGame(__builtin_return_address(0))) return ContentRoot();
    return ((NSURL * (*)(id, SEL))sResourceURL)(s, c);
}

__attribute__((noinline)) static NSString *BundleResourcePath(NSBundle *s, SEL c)
{
    if (s == NSBundle.mainBundle && CalledFromGame(__builtin_return_address(0))) return ContentRoot().path;
    return ((NSString * (*)(id, SEL))sResourcePath)(s, c);
}

static void PatchBundle(void)
{
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const struct mach_header_64 *h = (const void *)_dyld_get_image_header(i);
        if (h->filetype != MH_EXECUTE) continue;
        sMainHeader = (const void *)h;
        intptr_t slide = _dyld_get_image_vmaddr_slide(i);
        const struct load_command *lc = (const void *)(h + 1);
        for (uint32_t j = 0; j < h->ncmds; j++, lc = (const void *)((const char *)lc + lc->cmdsize)) {
            const struct segment_command_64 *seg = (const void *)lc;
            if (lc->cmd == LC_SEGMENT_64 && !strcmp(seg->segname, "__TEXT")) {
                sMainStart = seg->vmaddr + slide;
                sMainEnd = sMainStart + seg->vmsize;
            }
        }
    }
    sResourceURL = Swizzle(NSBundle.class, @selector(resourceURL), (IMP)BundleResourceURL);
    sResourcePath = Swizzle(NSBundle.class, @selector(resourcePath), (IMP)BundleResourcePath);
}

#pragma mark - Memory telemetry

#import <mach/mach.h>
static void StartFootprintLog(void)
{
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 0), 10 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(t, ^{
        task_vm_info_data_t vm;
        mach_msg_type_number_t n = TASK_VM_INFO_COUNT;
        if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&vm, &n) == KERN_SUCCESS)
            SHIM_LOG("mem: footprint %llu MB | dev buffers %llu (%llu MB) | textures %llu (%llu MB dev-alloc)",
                     vm.phys_footprint >> 20, gBufCount, gBufBytes >> 20, gTexCount, gTexBytes >> 20);
    });
    dispatch_resume(t);
    static dispatch_source_t keep;
    keep = t;
    (void)keep;
}

#pragma mark - Saved settings

// Settings the iOS port needs in GlobalSettingsmacOS.sjson, applied before the game reads the file:
//  - X/Y: the game boots parts of its pipeline at the stored resolution; if the game area changed
//    (e.g. safe-area insets) the image comes out squeezed, so keep them equal to the game area.
//  - ForceVoiceBankStreaming: stream VO instead of loading every voice bank into RAM (needed to fit
//    1080p assets in the 6 GB process limit); AutoDetect/UseLowResAssets follow HadesAssetSet.
static void SetOption(NSMutableString *m, NSString *key, NSString *value)
{
    NSString *pattern = [NSString stringWithFormat:@"(?m)^(\\s*%@ = ).*$", key];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSString *escaped = [NSRegularExpression escapedTemplateForString:value];
    if ([re replaceMatchesInString:m options:0 range:NSMakeRange(0, m.length) withTemplate:[@"$1" stringByAppendingString:escaped]] == 0) {
        NSRange open = [m rangeOfString:@"{"];
        if (open.location != NSNotFound)
            [m insertString:[NSString stringWithFormat:@"\n  %@ = %@", key, value] atIndex:open.location + 1];
    }
}

static void SyncSettings(void)
{
    NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Supergiant Games/Hades II"];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *px = [NSUserDefaults.standardUserDefaults stringForKey:@"HadesGameAreaPx"];
    BOOL lowRes = HadesWantsLowResAssets();
    for (NSString *name in @[ @"GlobalSettingsmacOS.sjson", @"GlobalSettingsmacOS.sjson.bak" ]) {
        NSString *path = [dir stringByAppendingPathComponent:name];
        NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] ?: @"{\n}\n";
        NSMutableString *m = [text mutableCopy];
        if (px) {
            CGSize size = CGSizeFromString(px);
            SetOption(m, @"X", [NSString stringWithFormat:@"%d", (int)size.width]);
            SetOption(m, @"Y", [NSString stringWithFormat:@"%d", (int)size.height]);
        }
        SetOption(m, @"ForceVoiceBankStreaming", @"true");
        NSString *vsync = [NSUserDefaults.standardUserDefaults stringForKey:@"HadesVSync"];   // "true"/"false"; unset = game's choice
        if (vsync) SetOption(m, @"VSync", vsync);
        NSInteger fps = [NSUserDefaults.standardUserDefaults integerForKey:@"HadesFpsLimit"];   // 0 = game's choice
        if (fps > 0) SetOption(m, @"FpsLimit", [NSString stringWithFormat:@"%ld", (long)fps]);
        SetOption(m, @"AutoDetectLowResAssets", @"false");
        SetOption(m, @"UseLowResAssets", lowRes ? @"true" : @"false");
        if (![m isEqualToString:text]) {
            [m writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            SHIM_LOG("settings: updated %s", name.UTF8String);
        }
    }
}

__attribute__((constructor)) static void HadesPatchesInit(void)
{
    SyncSettings();
    StartFootprintLog();
    setvbuf(stderr, NULL, _IONBF, 0);
    SHIM_LOG("Hades II iOS shim loaded");
    PatchBundle();
    PatchMetal();
}
