#import "VGMonitor.h"
#import "VGStabilityLog.h"
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <dlfcn.h>

NSNotificationName const VGStatusDidChangeNotification = @"VGStatusDidChangeNotification";
static NSString *const kVGNotifyKey = @"vg_notify_disconnect";

@interface VGMonitor ()
@property (nonatomic, strong) VGHearingStatus *latest;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL notifiedDisconnected;
@end

@implementation VGMonitor

+ (instancetype)shared {
    static VGMonitor *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ m = [VGMonitor new]; });
    return m;
}

- (void)start {
    if (self.timer) return;

    [UNUserNotificationCenter.currentNotificationCenter
        requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                      completionHandler:^(BOOL granted, NSError *_Nullable e) {
        if (!granted) NSLog(@"[VibeGo] notify denied %@", e);
    }];

    void *h = dlopen(
        "/System/Library/Frameworks/Accessibility.framework/Accessibility",
        RTLD_LAZY | RTLD_GLOBAL);
    NSArray<NSString *> *names = @[
        @"AXHearingDevicePairedUUIDsDidChangeNotification",
        @"AXHearingDeviceStreamingEarDidChangeNotification"
    ];
    for (NSString *sym in names) {
        void *addr = dlsym(h, sym.UTF8String);
        if (addr) {
            NSString *n = *(NSString * __strong *)addr;
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(changed)
                                                         name:n object:nil];
        }
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(changed)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    self.latest = [VGHearingStatus current];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                  target:self selector:@selector(changed)
                                                userInfo:nil repeats:YES];
}

- (void)refresh { [self changed]; }

- (void)changed {
    dispatch_async(dispatch_get_main_queue(), ^{
        VGHearingStatus *now = [VGHearingStatus current];
        BOOL changed = (now.pairedEar != self.latest.pairedEar) ||
                       (now.streamingEar != self.latest.streamingEar) ||
                       (now.pairedUUIDs.count != self.latest.pairedUUIDs.count);
        self.latest = now;
        [[NSNotificationCenter defaultCenter] postNotificationName:VGStatusDidChangeNotification object:nil];
        if (changed) [self transition:now];
    });
}

- (void)transition:(VGHearingStatus *)now {
    [[VGStabilityLog shared] recordConnected:now.anyConnected ear:now.pairedEar summary:now.summary];

    BOOL notifyOn = [[NSUserDefaults standardUserDefaults] objectForKey:kVGNotifyKey]
        ? [[NSUserDefaults standardUserDefaults] boolForKey:kVGNotifyKey] : YES;

    if (!now.anyConnected && !self.notifiedDisconnected) {
        self.notifiedDisconnected = YES;
        if (notifyOn) [self notifyTitle:@"Vibe Go 已断开" body:@"双耳均未连接，请检查助听器电量或靠近手机。"];
    } else if (now.anyConnected && self.notifiedDisconnected) {
        self.notifiedDisconnected = NO;
        if (notifyOn) [self notifyTitle:@"Vibe Go 已重新连接" body:now.summary];
    }
}

- (void)notifyTitle:(NSString *)title body:(NSString *)body {
    UNMutableNotificationContent *c = [UNMutableNotificationContent new];
    c.title = title; c.body = body; c.sound = UNNotificationSound.defaultSound;
    [UNUserNotificationCenter.currentNotificationCenter
        addNotificationRequest:[UNNotificationRequest requestWithIdentifier:NSUUID.UUID.UUIDString
                                                                    content:c trigger:nil]
         withCompletionHandler:nil];
}

- (void)dealloc { [self.timer invalidate]; }

@end
