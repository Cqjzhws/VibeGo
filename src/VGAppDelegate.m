#import "VGAppDelegate.h"
#import "VGDashboardVC.h"
#import "VGMicrophoneVC.h"
#import "VGLabVC.h"
#import "VGDiagnoseVC.h"
#import "VGGattProbeVC.h"
#import "VGMonitor.h"
#import "VGRssiMonitor.h"
#import "VGBatteryMonitor.h"

@implementation VGAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    UIViewController *(^nav)(UIViewController *, NSString *, NSString *) = ^(UIViewController *vc, NSString *title, NSString *icon) {
        UINavigationController *n = [[UINavigationController alloc] initWithRootViewController:vc];
        n.tabBarItem = [[UITabBarItem alloc] initWithTitle:title
                                                     image:[UIImage systemImageNamed:icon] tag:0];
        return n;
    };

    UITabBarController *tabs = [UITabBarController new];
    tabs.viewControllers = @[
        nav([VGDashboardVC new], @"状态", @"waveform"),
        nav([VGMicrophoneVC new], @"麦克风", @"mic.fill"),
        nav([VGLabVC new], @"实验室", @"testtube.2"),
        nav([VGDiagnoseVC new], @"诊断", @"stethoscope"),
        nav([VGGattProbeVC new], @"GATT", @"antenna.radiowaves.left.and.right"),
    ];

    self.window.rootViewController = tabs;
    [self.window makeKeyAndVisible];

    [[VGMonitor shared] start];
    [[VGRssiMonitor shared] start];
    [[VGBatteryMonitor shared] start];
    return YES;
}

@end
