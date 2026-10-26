#import "VGHearingDevice.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>

@implementation VGHearingStatus

+ (instancetype)current {
    VGHearingStatus *s = [VGHearingStatus new];
    void *h = dlopen(
        "/System/Library/Frameworks/Accessibility.framework/Accessibility",
        RTLD_LAZY | RTLD_GLOBAL);

    typedef NSArray *(*UUIDsFn)(void);
    UUIDsFn pairedFn = (UUIDsFn)dlsym(h, "AXMFiHearingDevicePairedUUIDs");
    if (pairedFn) {
        @try {
            NSMutableArray *uuids = [NSMutableArray array];
            for (NSUUID *u in pairedFn()) [uuids addObject:u.UUIDString];
            s.pairedUUIDs = uuids;
        } @catch (__unused NSException *e) { s.pairedUUIDs = @[]; }
    }

    typedef NSUInteger (*EarFn)(void);
    EarFn earFn = (EarFn)dlsym(h, "AXMFiHearingDeviceStreamingEar");
    if (earFn) { @try { s.streamingEar = earFn(); } @catch (__unused NSException *e) {} }

    typedef BOOL (*BoolFn)(void);
    BoolFn biFn = (BoolFn)dlsym(h, "AXSupportsBidirectionalAXMFiHearingDeviceStreaming");
    if (biFn) { @try { s.bidirectionalSupported = biFn(); } @catch (__unused NSException *e) {} }

    @try { s.pairedEar = UIAccessibilityHearingDevicePairedEar(); }
    @catch (__unused NSException *e) {}

    NSMutableArray *parts = [NSMutableArray array];
    if (s.pairedEar == 0) {
        [parts addObject:@"未连接"];
    } else {
        if (s.leftPaired) [parts addObject:@"左耳已配对"];
        if (s.rightPaired) [parts addObject:@"右耳已配对"];
        if (s.streamingEar) {
            NSMutableArray *st = [NSMutableArray array];
            if (s.leftStreaming) [st addObject:@"左"];
            if (s.rightStreaming) [st addObject:@"右"];
            [parts addObject:[NSString stringWithFormat:@"音频流:%@耳", [st componentsJoinedByString:@"+"]]];
        }
    }
    if (s.bidirectionalSupported) [parts addObject:@"双向免提"];
    s.summary = [parts componentsJoinedByString:@" · "];
    return s;
}

- (BOOL)leftPaired   { return (self.pairedEar & 1) != 0; }
- (BOOL)rightPaired  { return (self.pairedEar & 2) != 0; }
- (BOOL)leftStreaming  { return (self.streamingEar & 1) != 0; }
- (BOOL)rightStreaming { return (self.streamingEar & 2) != 0; }
- (BOOL)anyConnected { return self.pairedEar != 0; }

@end
