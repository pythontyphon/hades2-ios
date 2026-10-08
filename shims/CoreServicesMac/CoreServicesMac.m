// LSOpenCFURLRef (open a URL in the default app) -> UIApplication openURL.
#import <UIKit/UIKit.h>
#include "../common/shimlog.h"

OSStatus LSOpenCFURLRef(CFURLRef url, CFURLRef *outLaunchedURL)
{
    NSURL *u = (__bridge NSURL *)url;
    SHIM_LOG("LSOpenCFURLRef %s", u.absoluteString.UTF8String);
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIApplication.sharedApplication openURL:u options:@{} completionHandler:nil];
    });
    if (outLaunchedURL) *outLaunchedURL = NULL;
    return 0;
}
