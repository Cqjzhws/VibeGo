#import "VGDashboardVC.h"
#import "VGMonitor.h"
#import "VGHearingDevice.h"
#import "VGStabilityLog.h"
#import "VGRssiMonitor.h"
#import "VGBatteryMonitor.h"
#import "VGEarMap.h"

#pragma mark - Design tokens

static UIColor *VGBg(void)      { return [UIColor colorWithRed:0.035 green:0.055 blue:0.07 alpha:1]; }
static UIColor *VGCard(void)    { return [UIColor colorWithRed:0.075 green:0.105 blue:0.125 alpha:0.92]; }
static UIColor *VGLine(void)    { return [UIColor colorWithWhite:1 alpha:0.07]; }
static UIColor *VGMuted(void)   { return [UIColor colorWithWhite:0.55 alpha:1]; }
static UIColor *VGTeal(void)    { return [UIColor colorWithRed:0.28 green:0.90 blue:0.83 alpha:1]; }
static UIColor *VGGreen(void)   { return [UIColor colorWithRed:0.32 green:0.86 blue:0.55 alpha:1]; }
static UIColor *VGAmber(void)   { return [UIColor colorWithRed:0.99 green:0.72 blue:0.28 alpha:1]; }
static UIColor *VGRed(void)     { return [UIColor colorWithRed:0.98 green:0.40 blue:0.38 alpha:1]; }
static UIFont  *VGFont(CGFloat s, UIFontWeight w) { return [UIFont systemFontOfSize:s weight:w]; }

typedef NS_ENUM(NSInteger, VGEarPresence) {
    VGEarOffline = 0,   // 灰：未在场
    VGEarLinked  = 1,   // 绿：系统音频直连
    VGEarNearby  = 2,   // 青：BLE 在场（经主耳转发）
};

@interface VGDashboardVC ()
@property (nonatomic, strong) UIView *heroDot;
@property (nonatomic, strong) CAGradientLayer *heroGradient;
@property (nonatomic, strong) UILabel *heroTitle;
@property (nonatomic, strong) UILabel *heroSub;
@property (nonatomic, strong) UIView *leftCard;
@property (nonatomic, strong) UIView *rightCard;
@property (nonatomic, strong) UILabel *pillStream;
@property (nonatomic, strong) UILabel *pillBi;
@property (nonatomic, strong) UILabel *statDisc;
@property (nonatomic, strong) UILabel *statDown;
@property (nonatomic, strong) UILabel *statUptime;
@property (nonatomic, strong) UIStackView *rssiStack;
@property (nonatomic, strong) UILabel *rssiFooter;
@property (nonatomic, strong) UIStackView *battStack;   // 电量/设备信息（真实 GATT 只读）
@property (nonatomic, strong) UILabel *updatedAt;
@property (nonatomic, strong) NSTimer *timer;
@end

@implementation VGDashboardVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Vibe Go";
    self.view.backgroundColor = VGBg();
    [self.navigationController.navigationBar setTitleTextAttributes:@{NSForegroundColorAttributeName:UIColor.whiteColor}];

    // 背景渐变
    CAGradientLayer *bg = [CAGradientLayer layer];
    bg.colors = @[(id)[UIColor colorWithRed:0.03 green:0.09 blue:0.10 alpha:1].CGColor,
                  (id)[UIColor colorWithRed:0.035 green:0.045 blue:0.07 alpha:1].CGColor];
    bg.locations = @[@0, @1];
    bg.frame = self.view.bounds;
    bg.startPoint = CGPointMake(0, 0); bg.endPoint = CGPointMake(0.4, 1);
    [self.view.layer insertSublayer:bg atIndex:0];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    UIStackView *col = [UIStackView new];
    col.axis = UILayoutConstraintAxisVertical;
    col.spacing = 14;
    col.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:col];
    [NSLayoutConstraint activateConstraints:@[
        [col.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:10],
        [col.leadingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.leadingAnchor constant:18],
        [col.trailingAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.trailingAnchor constant:-18],
        [col.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-20],
        [col.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-36],
    ]];

    [col addArrangedSubview:[self buildHero]];
    [col addArrangedSubview:[self buildEarRow]];
    [col addArrangedSubview:[self buildCapsules]];
    [col addArrangedSubview:[self buildBattery]];
    [col addArrangedSubview:[self buildStability]];
    [col addArrangedSubview:[self buildRssi]];

    UILabel *note = [UILabel new];
    note.text = @"电量与设备信息经标准 GATT 只读获取（电池 2A19 / 设备信息 180A），每 60 秒自动刷新，不写入设备。";
    note.font = VGFont(11, UIFontWeightRegular);
    note.textColor = VGMuted();
    note.numberOfLines = 0;
    [col addArrangedSubview:note];

    self.updatedAt = [UILabel new];
    self.updatedAt.font = VGFont(11, UIFontWeightRegular);
    self.updatedAt.textColor = [UIColor colorWithWhite:0.35 alpha:1];
    [col addArrangedSubview:self.updatedAt];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
                                                 name:VGStatusDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
                                                 name:VGRssiDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
                                                 name:VGBatteryDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh)
                                                 name:VGEarMapDidChangeNotification object:nil];
    self.timer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self
                                                selector:@selector(refresh) userInfo:nil repeats:YES];
}

- (void)dealloc { [self.timer invalidate]; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[VGMonitor shared] refresh];
    [self refresh];
}

#pragma mark - Builders

- (UIView *)card {
    UIView *c = [UIView new];
    c.backgroundColor = VGCard();
    c.layer.cornerRadius = 20;
    c.layer.borderWidth = 1;
    c.layer.borderColor = VGLine().CGColor;
    return c;
}

- (UILabel *)sectionTitle:(NSString *)t {
    UILabel *l = [UILabel new];
    l.text = t;
    l.font = VGFont(12, UIFontWeightSemibold);
    l.textColor = VGTeal();
    l.translatesAutoresizingMaskIntoConstraints = NO;
    return l;
}

- (UIView *)buildHero {
    UIView *hero = [UIView new];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.layer.cornerRadius = 24;
    hero.layer.masksToBounds = YES;
    self.heroGradient = [CAGradientLayer layer];
    self.heroGradient.colors = @[(id)[UIColor colorWithRed:0.06 green:0.34 blue:0.33 alpha:1].CGColor,
                                 (id)[UIColor colorWithRed:0.05 green:0.18 blue:0.24 alpha:1].CGColor];
    self.heroGradient.startPoint = CGPointMake(0, 0);
    self.heroGradient.endPoint = CGPointMake(1, 1);
    [hero.layer addSublayer:self.heroGradient];

    self.heroDot = [UIView new];
    self.heroDot.translatesAutoresizingMaskIntoConstraints = NO;
    self.heroDot.backgroundColor = VGTeal();
    self.heroDot.layer.cornerRadius = 13;
    [hero addSubview:self.heroDot];

    self.heroTitle = [UILabel new];
    self.heroTitle.text = @"已连接";
    self.heroTitle.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    self.heroTitle.textColor = UIColor.whiteColor;
    self.heroTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [hero addSubview:self.heroTitle];

    self.heroSub = [UILabel new];
    self.heroSub.font = VGFont(13, UIFontWeightRegular);
    self.heroSub.textColor = [UIColor colorWithWhite:0.82 alpha:1];
    self.heroSub.numberOfLines = 0;
    self.heroSub.translatesAutoresizingMaskIntoConstraints = NO;
    [hero addSubview:self.heroSub];

    [NSLayoutConstraint activateConstraints:@[
        [self.heroDot.leadingAnchor constraintEqualToAnchor:hero.leadingAnchor constant:22],
        [self.heroDot.centerYAnchor constraintEqualToAnchor:hero.centerYAnchor],
        [self.heroDot.widthAnchor constraintEqualToConstant:26],
        [self.heroDot.heightAnchor constraintEqualToConstant:26],
        [self.heroTitle.leadingAnchor constraintEqualToAnchor:self.heroDot.trailingAnchor constant:16],
        [self.heroTitle.topAnchor constraintEqualToAnchor:hero.topAnchor constant:22],
        [self.heroTitle.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-20],
        [self.heroSub.leadingAnchor constraintEqualToAnchor:self.heroTitle.leadingAnchor],
        [self.heroSub.topAnchor constraintEqualToAnchor:self.heroTitle.bottomAnchor constant:6],
        [self.heroSub.trailingAnchor constraintEqualToAnchor:hero.trailingAnchor constant:-20],
        [self.heroSub.bottomAnchor constraintEqualToAnchor:hero.bottomAnchor constant:-22],
        [hero.heightAnchor constraintGreaterThanOrEqualToConstant:104],
    ]];
    return hero;
}

- (UIView *)buildEarRow {
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 12;
    row.distribution = UIStackViewDistributionFillEqually;
    self.leftCard  = [self earCardWithSide:@"左耳"];
    self.rightCard = [self earCardWithSide:@"右耳"];
    [row addArrangedSubview:self.leftCard];
    [row addArrangedSubview:self.rightCard];
    return row;
}

- (UIView *)earCardWithSide:(NSString *)side {
    UIView *c = [self card];
    UIImageView *icon = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:@"ear.fill"] ?: [UIImage systemImageNamed:@"circle.fill"]];
    icon.tintColor = [UIColor colorWithWhite:0.4 alpha:1];
    icon.tag = 10;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:icon];

    UILabel *name = [UILabel new];
    name.text = side;
    name.font = VGFont(14, UIFontWeightSemibold);
    name.textColor = [UIColor colorWithWhite:0.6 alpha:1];
    name.tag = 11;
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:name];

    UILabel *state = [UILabel new];
    state.text = @"待机";
    state.font = VGFont(12, UIFontWeightMedium);
    state.textColor = VGMuted();
    state.tag = 12;
    state.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:state];

    UIView *dot = [UIView new];
    dot.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
    dot.layer.cornerRadius = 5;
    dot.tag = 13;
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:dot];

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [icon.topAnchor constraintEqualToAnchor:c.topAnchor constant:16],
        [icon.widthAnchor constraintEqualToConstant:26],
        [icon.heightAnchor constraintEqualToConstant:26],
        [name.leadingAnchor constraintEqualToAnchor:icon.leadingAnchor],
        [name.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:12],
        [state.leadingAnchor constraintEqualToAnchor:icon.leadingAnchor],
        [state.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:3],
        [state.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-14],
        [dot.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],
        [dot.topAnchor constraintEqualToAnchor:c.topAnchor constant:18],
        [dot.widthAnchor constraintEqualToConstant:10],
        [dot.heightAnchor constraintEqualToConstant:10],
    ]];
    return c;
}

- (UIView *)buildCapsules {
    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 10;
    row.distribution = UIStackViewDistributionFillEqually;
    self.pillStream = [self pillText:@"音频流"];
    self.pillBi = [self pillText:@"双向免提"];
    [row addArrangedSubview:self.pillStream];
    [row addArrangedSubview:self.pillBi];
    return row;
}

- (UILabel *)pillText:(NSString *)t {
    UILabel *l = [UILabel new];
    l.text = [NSString stringWithFormat:@"  %@  ", t];
    l.font = VGFont(13, UIFontWeightSemibold);
    l.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    l.textAlignment = NSTextAlignmentCenter;
    l.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    l.layer.cornerRadius = 16;
    l.layer.masksToBounds = YES;
    [l.heightAnchor constraintEqualToConstant:38].active = YES;
    return l;
}

- (UIView *)buildBattery {
    UIView *c = [self card];
    UILabel *title = [self sectionTitle:@"电量 · 设备信息（实时只读）"];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:title];

    self.battStack = [UIStackView new];
    self.battStack.axis = UILayoutConstraintAxisVertical;
    self.battStack.spacing = 12;
    self.battStack.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:self.battStack];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:c.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [self.battStack.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
        [self.battStack.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [self.battStack.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],
        [self.battStack.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-16],
    ]];

    [self refreshBatteryRows];
    return c;
}

- (UIView *)batteryRow:(VGBatteryDevice *)d ear:(NSString *)ear {
    UIView *row = [UIView new];

    UILabel *name = [UILabel new];
    name.text = ear;
    name.font = VGFont(15, UIFontWeightSemibold);
    name.textColor = UIColor.whiteColor;
    name.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:name];

    // 电量数字 + 颜色
    UILabel *pct = [UILabel new];
    UIColor *battColor;
    if (d.battery == nil) {
        pct.text = @"-- %";
        battColor = VGMuted();
    } else {
        NSInteger b = d.battery.integerValue;
        pct.text = [NSString stringWithFormat:@"%ld %%", (long)b];
        battColor = b > 40 ? VGGreen() : (b > 15 ? VGAmber() : VGRed());
    }
    pct.font = [UIFont fontWithName:@"Menlo-Bold" size:17] ?: VGFont(17, UIFontWeightBold);
    pct.textColor = battColor;
    pct.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:pct];

    // 电量条
    UIView *track = [UIView new];
    track.backgroundColor = [UIColor colorWithWhite:0.16 alpha:1];
    track.layer.cornerRadius = 3;
    track.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:track];
    UIView *fill = [UIView new];
    fill.backgroundColor = battColor;
    fill.layer.cornerRadius = 3;
    fill.translatesAutoresizingMaskIntoConstraints = NO;
    [track addSubview:fill];
    CGFloat ratio = d.battery == nil ? 0 : MIN(1.0, d.battery.integerValue / 100.0);
    [NSLayoutConstraint activateConstraints:@[
        [fill.leadingAnchor constraintEqualToAnchor:track.leadingAnchor],
        [fill.topAnchor constraintEqualToAnchor:track.topAnchor],
        [fill.bottomAnchor constraintEqualToAnchor:track.bottomAnchor],
        [fill.widthAnchor constraintEqualToAnchor:track.widthAnchor multiplier:ratio],
    ]];

    // 序列号 + 固件
    NSMutableString *info = [NSMutableString string];
    if (d.serial.length)   [info appendFormat:@"SN %@  ", d.serial];
    if (d.firmware.length) [info appendFormat:@"固件 %@  ", d.firmware];
    else if (d.model.length) [info appendFormat:@"%@ %@  ", d.manufacturer ?: @"", d.model];
    if (d.rssi != nil)     [info appendFormat:@"%ld dBm", (long)d.rssi.integerValue];
    if (info.length == 0)  [info appendString:@"读取中…连接建立后自动获取"];
    UILabel *sub = [UILabel new];
    sub.text = info;
    sub.font = VGFont(11, UIFontWeightRegular);
    sub.textColor = VGMuted();
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    [row addSubview:sub];

    [NSLayoutConstraint activateConstraints:@[
        [name.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [name.topAnchor constraintEqualToAnchor:row.topAnchor],
        [pct.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [pct.firstBaselineAnchor constraintEqualToAnchor:name.firstBaselineAnchor],
        [track.leadingAnchor constraintEqualToAnchor:name.trailingAnchor constant:12],
        [track.centerYAnchor constraintEqualToAnchor:pct.centerYAnchor],
        [track.heightAnchor constraintEqualToConstant:6],
        [track.trailingAnchor constraintEqualToAnchor:pct.leadingAnchor constant:-10],
        [sub.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:4],
        [sub.trailingAnchor constraintLessThanOrEqualToAnchor:row.trailingAnchor],
        [sub.bottomAnchor constraintEqualToAnchor:row.bottomAnchor],
    ]];
    return row;
}

- (void)refreshBatteryRows {
    if (!self.battStack) return;
    for (UIView *v in self.battStack.arrangedSubviews) [v removeFromSuperview];

    NSArray<VGBatteryDevice *> *ds = [VGBatteryMonitor shared].devices;
    NSMutableArray *live = [NSMutableArray array];
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-300]; // 5 分钟内有更新才算在场
    for (VGBatteryDevice *d in ds) {
        if (d.connected || (d.updatedAt && [d.updatedAt compare:cutoff] == NSOrderedDescending)) [live addObject:d];
    }

    if (live.count == 0) {
        UILabel *e = [UILabel new];
        e.text = @"正在连接助听器读取电量与设备信息…连接建立后约几秒出数，60 秒自动刷新。";
        e.font = VGFont(13, UIFontWeightRegular);
        e.textColor = VGMuted();
        e.numberOfLines = 0;
        [self.battStack addArrangedSubview:e];
        return;
    }

    NSUInteger n = 0;
    for (VGBatteryDevice *d in live) {
        NSString *fallback = live.count >= 2 ? (n == 0 ? @"耳①" : @"耳②") : @"助听器";
        NSString *ear = [VGEarMap earLabelForKey:d.uuidString];
        [self.battStack addArrangedSubview:[self batteryRow:d ear:ear.length ? ear : fallback]];
        n++;
        if (n >= 2) break;
    }

    // 当前程序名（双耳一致，取任一即可）
    NSString *prog = [VGBatteryMonitor shared].currentProgramName;
    if (prog.length) {
        UILabel *p = [UILabel new];
        p.text = [NSString stringWithFormat:@"当前程序：%@", prog];
        p.font = VGFont(12, UIFontWeightMedium);
        p.textColor = VGTeal();
        [self.battStack addArrangedSubview:p];
    }
}

- (UIView *)buildStability {
    UIView *c = [self card];
    UILabel *title = [self sectionTitle:@"连接稳定性 · 近 24 小时"];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:title];

    self.statUptime = [UILabel new];
    self.statUptime.font = VGFont(12, UIFontWeightMedium);
    self.statUptime.textColor = VGMuted();
    self.statUptime.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *row = [UIStackView new];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *b1 = [UIView new];
    self.statDisc = [UILabel new];
    self.statDisc.text = @"0";
    self.statDisc.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    self.statDisc.textColor = VGTeal();
    self.statDisc.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *cap1 = [UILabel new]; cap1.text = @"断连次数";
    cap1.font = VGFont(11, UIFontWeightRegular); cap1.textColor = VGMuted();
    cap1.translatesAutoresizingMaskIntoConstraints = NO;
    [b1 addSubview:self.statDisc]; [b1 addSubview:cap1];
    [self.statDisc.leadingAnchor constraintEqualToAnchor:b1.leadingAnchor].active = YES;
    [self.statDisc.topAnchor constraintEqualToAnchor:b1.topAnchor].active = YES;
    [cap1.leadingAnchor constraintEqualToAnchor:b1.leadingAnchor].active = YES;
    [cap1.topAnchor constraintEqualToAnchor:self.statDisc.bottomAnchor constant:2].active = YES;
    [cap1.bottomAnchor constraintEqualToAnchor:b1.bottomAnchor].active = YES;

    UIView *b2 = [UIView new];
    self.statDown = [UILabel new];
    self.statDown.text = @"0 分";
    self.statDown.font = [UIFont systemFontOfSize:26 weight:UIFontWeightBold];
    self.statDown.textColor = VGTeal();
    self.statDown.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *cap2 = [UILabel new]; cap2.text = @"累计离线";
    cap2.font = VGFont(11, UIFontWeightRegular); cap2.textColor = VGMuted();
    cap2.translatesAutoresizingMaskIntoConstraints = NO;
    [b2 addSubview:self.statDown]; [b2 addSubview:cap2];
    [self.statDown.leadingAnchor constraintEqualToAnchor:b2.leadingAnchor].active = YES;
    [self.statDown.topAnchor constraintEqualToAnchor:b2.topAnchor].active = YES;
    [cap2.leadingAnchor constraintEqualToAnchor:b2.leadingAnchor].active = YES;
    [cap2.topAnchor constraintEqualToAnchor:self.statDown.bottomAnchor constant:2].active = YES;
    [cap2.bottomAnchor constraintEqualToAnchor:b2.bottomAnchor].active = YES;

    [row addArrangedSubview:b1];
    [row addArrangedSubview:b2];
    [c addSubview:row];
    [c addSubview:self.statUptime];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:c.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [row.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
        [row.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],
        [self.statUptime.topAnchor constraintEqualToAnchor:row.bottomAnchor constant:10],
        [self.statUptime.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [self.statUptime.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-16],
    ]];
    return c;
}

- (UIView *)buildRssi {
    UIView *c = [self card];
    UILabel *title = [self sectionTitle:@"信号强度 · BLE 控制链路"];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:title];

    self.rssiStack = [UIStackView new];
    self.rssiStack.axis = UILayoutConstraintAxisVertical;
    self.rssiStack.spacing = 10;
    self.rssiStack.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:self.rssiStack];

    self.rssiFooter = [UILabel new];
    self.rssiFooter.font = VGFont(11, UIFontWeightRegular);
    self.rssiFooter.textColor = VGMuted();
    self.rssiFooter.numberOfLines = 0;
    self.rssiFooter.translatesAutoresizingMaskIntoConstraints = NO;
    [c addSubview:self.rssiFooter];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:c.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [self.rssiStack.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
        [self.rssiStack.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [self.rssiStack.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],
        [self.rssiFooter.topAnchor constraintEqualToAnchor:self.rssiStack.bottomAnchor constant:12],
        [self.rssiFooter.leadingAnchor constraintEqualToAnchor:c.leadingAnchor constant:16],
        [self.rssiFooter.trailingAnchor constraintEqualToAnchor:c.trailingAnchor constant:-16],
        [self.rssiFooter.bottomAnchor constraintEqualToAnchor:c.bottomAnchor constant:-14],
    ]];
    return c;
}

- (UIView *)signalBars:(NSInteger)level color:(UIColor *)color {
    UIStackView *s = [UIStackView new];
    s.axis = UILayoutConstraintAxisHorizontal;
    s.spacing = 3;
    s.alignment = UIStackViewAlignmentBottom;
    for (NSInteger i = 1; i <= 4; i++) {
        UIView *b = [UIView new];
        b.backgroundColor = i <= level ? color : [UIColor colorWithWhite:0.18 alpha:1];
        b.layer.cornerRadius = 1.5;
        CGFloat h = 6 + i * 3.5;
        [b.heightAnchor constraintEqualToConstant:h].active = YES;
        [b.widthAnchor constraintEqualToConstant:5].active = YES;
        [s addArrangedSubview:b];
    }
    [s.heightAnchor constraintEqualToConstant:22].active = YES;
    return s;
}

#pragma mark - Refresh

- (void)applyEarCard:(UIView *)card presence:(VGEarPresence)presence detail:(NSString *)detail {
    UIColor *accent;
    if (presence == VGEarLinked)      accent = VGGreen();
    else if (presence == VGEarNearby) accent = VGTeal();
    else                              accent = [UIColor colorWithWhite:0.25 alpha:1];

    UIImageView *icon = [card viewWithTag:10];
    UILabel *name = [card viewWithTag:11];
    UILabel *state = [card viewWithTag:12];
    UIView *dot = [card viewWithTag:13];
    icon.tintColor = presence == VGEarOffline ? [UIColor colorWithWhite:0.4 alpha:1] : accent;
    name.textColor = presence == VGEarOffline ? [UIColor colorWithWhite:0.6 alpha:1] : UIColor.whiteColor;
    state.text = detail;
    state.textColor = presence == VGEarOffline ? VGMuted() : accent;
    dot.backgroundColor = accent;
}

- (void)setPill:(UILabel *)pill on:(BOOL)on {
    pill.textColor = on ? UIColor.whiteColor : [UIColor colorWithWhite:0.55 alpha:1];
    pill.backgroundColor = on
        ? [UIColor colorWithRed:0.10 green:0.42 blue:0.40 alpha:1]
        : [UIColor colorWithWhite:0.12 alpha:1];
}

- (void)refresh {
    VGHearingStatus *s = [VGMonitor shared].latest ?: [VGHearingStatus current];
    NSUInteger fresh = [VGRssiMonitor shared].freshDeviceCount;
    BOOL connected = s.anyConnected;

    // Hero
    self.heroTitle.text = connected ? @"已连接" : @"未连接";
    self.heroDot.backgroundColor = connected ? VGTeal() : VGRed();
    if (connected) [self addPulseTo:self.heroDot]; else [self.heroDot.layer removeAnimationForKey:@"pulse"];
    NSString *extra = fresh >= 2 ? @"双耳均在附近" : (fresh == 1 ? @"单耳在附近" : @"");
    NSString *prog = [VGBatteryMonitor shared].currentProgramName;
    if (prog.length) extra = extra.length ? [NSString stringWithFormat:@"%@ · 程序：%@", extra, prog] : [NSString stringWithFormat:@"程序：%@", prog];
    self.heroSub.text = s.summary.length ? s.summary : (extra ?: @"等待助听器…");

    // 双耳
    [self applyEarCard:self.rightCard presence:s.rightPaired ? VGEarLinked : VGEarOffline
                detail:s.rightPaired ? @"音频直连" : @"待机"];
    VGEarPresence leftPresence;
    NSString *leftDetail;
    if (s.leftPaired) { leftPresence = VGEarLinked; leftDetail = @"音频直连"; }
    else if (fresh >= 2) { leftPresence = VGEarNearby; leftDetail = @"在场·右耳转发"; }
    else { leftPresence = VGEarOffline; leftDetail = @"待机"; }
    [self applyEarCard:self.leftCard presence:leftPresence detail:leftDetail];

    [self setPill:self.pillStream on:s.streamingEar != 0];
    [self setPill:self.pillBi on:s.bidirectionalSupported];

    // 稳定性
    NSArray *events = [VGStabilityLog shared].events;
    NSDate *dayAgo = [NSDate dateWithTimeIntervalSinceNow:-24*3600];
    NSUInteger disc = 0; NSTimeInterval down = 0; NSDate *downSince = nil;
    for (NSDictionary *e in [[events reverseObjectEnumerator] allObjects]) {
        NSDate *ts = [NSDate dateWithTimeIntervalSince1970:[e[@"ts"] doubleValue]];
        if ([ts compare:dayAgo] == NSOrderedAscending) continue;
        if ([e[@"state"] isEqual:@"disconnected"]) { disc++; downSince = ts; }
        else if (downSince) { down += [ts timeIntervalSinceDate:downSince]; downSince = nil; }
    }
    if (downSince) down += [[NSDate date] timeIntervalSinceDate:downSince];
    self.statDisc.text = [NSString stringWithFormat:@"%lu", (unsigned long)disc];
    self.statDisc.textColor = disc == 0 ? VGGreen() : VGAmber();
    NSInteger mm = (NSInteger)(down/60);
    self.statDown.text = [NSString stringWithFormat:@"%ld 分", (long)mm];
    self.statUptime.text = connected ? @"当前连接稳定，持续监测中" : @"当前未连接，恢复后自动记录";

    // RSSI
    [self refreshRssiRows];

    // 电量/设备信息
    [self refreshBatteryRows];

    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"更新于 HH:mm:ss";
    self.updatedAt.text = [f stringFromDate:NSDate.date];
}

- (void)refreshRssiRows {
    for (UIView *v in self.rssiStack.arrangedSubviews) [v removeFromSuperview];
    NSArray<VGRssiReading *> *rs = [VGRssiMonitor shared].readings;
    NSMutableArray *fresh2 = [NSMutableArray array];
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-20];
    for (VGRssiReading *r in rs) if ([r.updatedAt compare:cutoff] == NSOrderedDescending) [fresh2 addObject:r];

    if (fresh2.count == 0) {
        UILabel *e = [UILabel new];
        e.text = @"正在监听 Vibe 广播…助听器低功率广播为间歇发送，请稍候";
        e.font = VGFont(13, UIFontWeightRegular);
        e.textColor = VGMuted();
        e.numberOfLines = 0;
        [self.rssiStack addArrangedSubview:e];
        self.rssiFooter.text = @"锌空电池助听器 BLE 常态约 -85 ~ -95 dBm，属正常低功率，不代表音频会断。";
        return;
    }

    NSUInteger n = 0;
    for (VGRssiReading *r in fresh2) {
        NSString *fallback = fresh2.count >= 2 ? (n == 0 ? @"耳①" : @"耳②") : @"助听器";
        NSString *ear = [VGEarMap earLabelForKey:r.key];
        [self.rssiStack addArrangedSubview:[self rssiRow:ear.length ? ear : fallback reading:r]];
        n++;
        if (n >= 2) break;
    }
    self.rssiFooter.text = @"锌空助听器低功率常态约 -85 ~ -95 dBm；≥ -85 优，-85 ~ -95 正常，< -102 才需警惕断连。";
}

- (UIView *)rssiRow:(NSString *)ear reading:(VGRssiReading *)r {
    UIView *row = [UIView new];
    UILabel *name = [UILabel new];
    name.text = ear;
    name.font = VGFont(15, UIFontWeightSemibold);
    name.textColor = UIColor.whiteColor;

    UIView *bars = [self signalBars:[VGRssiMonitor signalBars:r.avgRSSI]
                              color:[VGRssiMonitor qualityColor:r.avgRSSI]];
    UILabel *dbm = [UILabel new];
    dbm.text = [NSString stringWithFormat:@"%.0f dBm", r.avgRSSI];
    dbm.font = [UIFont fontWithName:@"Menlo-Bold" size:15] ?: VGFont(15, UIFontWeightBold);
    dbm.textColor = [VGRssiMonitor qualityColor:r.avgRSSI];
    UILabel *q = [UILabel new];
    q.text = [VGRssiMonitor qualityLabel:r.avgRSSI];
    q.font = VGFont(11, UIFontWeightSemibold);
    q.textColor = [VGRssiMonitor qualityColor:r.avgRSSI];

    for (UIView *v in @[name,bars,dbm,q]) {
        v.translatesAutoresizingMaskIntoConstraints = NO;
        [row addSubview:v];
    }
    [NSLayoutConstraint activateConstraints:@[
        [name.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [name.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [bars.leadingAnchor constraintEqualToAnchor:name.trailingAnchor constant:12],
        [bars.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [q.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [q.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [dbm.trailingAnchor constraintEqualToAnchor:q.leadingAnchor constant:-10],
        [dbm.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [row.heightAnchor constraintEqualToConstant:26],
    ]];
    return row;
}

- (void)addPulseTo:(UIView *)dot {
    if ([dot.layer animationForKey:@"pulse"]) return;
    CABasicAnimation *scale = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    scale.fromValue = @1; scale.toValue = @1.9;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0.5; fade.toValue = @0;
    CAAnimationGroup *g = [CAAnimationGroup animation];
    g.animations = @[scale, fade];
    g.duration = 1.6; g.repeatCount = HUGE_VALF; g.timingFunction =
        [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [dot.layer addAnimation:g forKey:@"pulse"];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.heroGradient.frame = self.heroDot.superview.bounds;
    for (CALayer *l in self.view.layer.sublayers) {
        if ([l isKindOfClass:[CAGradientLayer class]] && l != self.heroGradient) l.frame = self.view.bounds;
    }
}

@end
