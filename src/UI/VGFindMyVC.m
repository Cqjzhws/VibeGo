//
//  VGFindMyVC.m — Find My 助听器
//

#import "VGFindMyVC.h"
#import "VGRssiMonitor.h"
#import "VGEarMap.h"

@implementation VGFindMyVC {
    UILabel *_title;
    UILabel *_tip;
    NSMutableArray<UILabel *> *_earLabels;
    NSMutableArray<UIView *> *_rings;
    NSMutableArray<UILabel *> *_distLabels;
    NSMutableArray<UILabel *> *_rssiLabels;
    NSTimer *_tick;
}

- (instancetype)init {
    if ((self = [super init])) {
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"查找"
                                                        image:[UIImage systemImageNamed:@"location.fill"] tag:5];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"查找助听器";
    self.view.backgroundColor = [UIColor colorWithRed:0.035 green:0.055 blue:0.07 alpha:1];

    _earLabels = [NSMutableArray array];
    _rings = [NSMutableArray array];
    _distLabels = [NSMutableArray array];
    _rssiLabels = [NSMutableArray array];

    _title = [self label:22 bold:YES color:UIColor.whiteColor];
    _title.text = @"Find My 助听器";

    _tip = [self label:12 bold:NO color:[UIColor colorWithWhite:0.55 alpha:1]];
    _tip.numberOfLines = 0;
    _tip.text = @"基于 BLE 信号强度估算距离。\n设备越近，圆圈越大越绿；越远越小越红。";

    [self.view addSubview:_title];
    [self.view addSubview:_tip];

    for (int i = 0; i < 2; i++) {
        UILabel *ear = [self label:16 bold:YES color:UIColor.whiteColor];
        ear.textAlignment = NSTextAlignmentCenter;

        UIView *ring = [UIView new];
        ring.layer.cornerRadius = 50;
        ring.layer.borderWidth = 4;

        UILabel *dist = [self label:28 bold:YES color:UIColor.whiteColor];
        dist.textAlignment = NSTextAlignmentCenter;

        UILabel *rssi = [self label:11 bold:NO color:[UIColor colorWithWhite:0.6 alpha:1]];
        rssi.textAlignment = NSTextAlignmentCenter;
        rssi.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];

        [self.view addSubview:ear];
        [self.view addSubview:ring];
        [ring addSubview:dist];
        [self.view addSubview:rssi];

        [_earLabels addObject:ear];
        [_rings addObject:ring];
        [_distLabels addObject:dist];
        [_rssiLabels addObject:rssi];
    }

    _tick = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                                           selector:@selector(refresh) userInfo:nil repeats:YES];
    [self refresh];
}

- (UILabel *)label:(CGFloat)size bold:(BOOL)bold color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.textColor = color;
    return l;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat pad = 20;
    CGFloat y = self.view.safeAreaInsets.top + 8;

    _title.frame = CGRectMake(pad, y, w - pad * 2, 28); y += 34;
    _tip.frame = CGRectMake(pad, y, w - pad * 2, 40); y += 50;

    CGFloat cardW = (w - pad * 3) / 2.0;
    CGFloat cardH = 220;
    for (int i = 0; i < 2; i++) {
        CGFloat x = pad + i * (cardW + pad);
        _earLabels[i].frame = CGRectMake(x, y, cardW, 22);
        _rings[i].frame = CGRectMake(x + (cardW - 100) / 2, y + 30, 100, 100);
        _distLabels[i].frame = CGRectMake(0, 30, 100, 40);
        _rssiLabels[i].frame = CGRectMake(x, y + 140, cardW, 18);
    }
}

- (void)refresh {
    NSArray<VGRssiReading *> *readings = [[VGRssiMonitor shared] readings];

    for (int i = 0; i < 2; i++) {
        UILabel *ear = _earLabels[i];
        UIView *ring = _rings[i];
        UILabel *dist = _distLabels[i];
        UILabel *rssiL = _rssiLabels[i];

        if (i < (int)readings.count) {
            VGRssiReading *r = readings[i];
            NSString *earLabel = [VGEarMap earLabelForKey:r.key];
            ear.text = earLabel.length ? earLabel : (r.localName ?: @"未知设备");

            double rssi = r.avgRSSI;
            double meters = [VGRssiMonitor estimatedDistanceMeters:rssi];
            UIColor *color = [VGRssiMonitor distanceColor:rssi];

            // 圆圈大小随距离变化：近=大，远=小
            NSInteger level = [VGRssiMonitor distanceLevel:rssi];
            CGFloat size = 100 - level * 15;  // 100~40
            CGRect rf = ring.frame;
            ring.frame = CGRectMake(rf.origin.x + (rf.size.width - size) / 2,
                                    rf.origin.y + (rf.size.height - size) / 2,
                                    size, size);
            ring.layer.cornerRadius = size / 2;
            ring.layer.borderColor = color.CGColor;

            dist.text = [NSString stringWithFormat:@"%.1fm", meters];
            dist.textColor = color;

            rssiL.text = [NSString stringWithFormat:@"RSSI %.0f dBm · %@",
                          rssi, [VGRssiMonitor distanceLabel:rssi]];
        } else {
            ear.text = @"—";
            ring.layer.borderColor = [UIColor colorWithWhite:0.2 alpha:1].CGColor;
            dist.text = @"-";
            rssiL.text = @"无信号";
        }
    }
}

- (void)dealloc { [_tick invalidate]; }

@end
