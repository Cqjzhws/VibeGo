//
//  VGMicrophoneVC.m — 麦克风联动控制面板
//
//  0.6.0 改动：
//   · 滑块改为「吸附到设备档位」——拖到 56% 会自动落在真实档位 8（53%），
//     显示数字和实际写入报文的档位永远一致，不再出现「显示 56 实际写 53」
//   · 每行标签同时显示「档位 N · P%」，方便对照日志里的 档位= 数值
//   · 新增「后台音频保活」开关（默认关），App 老被后台杀掉时打开
//

#import "VGMicrophoneVC.h"
#import <CoreBluetooth/CoreBluetooth.h>

extern BOOL HLMediaPlaying(void);
extern BOOL HLInCall(void);
extern NSString *HLCallCategory(void);
extern NSString *HLStatusText(void);
extern NSString *HLMicLiveText(void);
extern void HLReapplyNow(void);
extern NSArray<NSString *> *HLRecentLines(void);
extern NSInteger HLGetLevelMax(void);
extern BOOL HLKeepAliveRunning(void);
extern void HLSetKeepAlive(BOOL on);
extern BOOL HLKeepAliveEnabled(void);
extern void HLSetAutomation(BOOL on);
extern BOOL HLGetAutomation(void);
// 自适应麦克风（0.8.0）
extern BOOL HLAdaptiveEnabled(void);
extern void HLSetAdaptive(BOOL on);
extern double HLAdaptiveCurrentDB(void);
extern NSInteger HLAdaptiveRestorePercent(void);

@implementation VGMicrophoneVC {
    UILabel *_big, *_sub, *_ears, *_micLive;
    UILabel *_lblRestore, *_lblCall, *_lblMute;
    UISlider *_slRestore, *_slCall, *_slMute;
    UISwitch *_lockSwitch;
    UILabel *_lockLabel;
    UISwitch *_keepSwitch;
    UILabel *_keepLabel;
    UISwitch *_autoSwitch;
    UILabel *_autoLabel;
    UISwitch *_holdSwitch;
    UILabel *_holdLabel;
    UISwitch *_adaptiveSwitch;      // 0.8.0 自适应麦克风
    UILabel *_adaptiveLabel;
    UILabel *_adaptiveInfo;         // 显示当前 dB 和有效档位
    UIButton *_applyBtn;
    UITextView *_logView;
    NSTimer *_tick;
    NSUInteger _lastLogCount;
    BOOL _keepWasRunning;
}

- (instancetype)init {
    if ((self = [super init])) {
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"麦克风"
                                                        image:[UIImage systemImageNamed:@"mic.fill"] tag:1];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"麦克风联动";
    self.view.backgroundColor = [UIColor colorWithRed:0.035 green:0.055 blue:0.07 alpha:1];

    _big = [self label:30 bold:YES color:UIColor.whiteColor];
    _sub = [self label:12 bold:NO color:[UIColor colorWithWhite:0.55 alpha:1]];
    _sub.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    _ears = [self label:14 bold:NO color:[UIColor colorWithWhite:0.8 alpha:1]];
    _micLive = [self label:11 bold:NO color:[UIColor colorWithRed:0.45 green:0.9 blue:0.8 alpha:1]];
    _micLive.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _micLive.numberOfLines = 2;

    UIColor *teal = [UIColor colorWithRed:0.30 green:0.85 blue:0.75 alpha:1];

    _lblRestore = [self label:13 bold:NO color:[UIColor colorWithWhite:0.75 alpha:1]];
    _slRestore = [self slider:teal tag:1];
    _slRestore.value = [self prefInt:@"HLRestorePercentLeft" dflt:60];

    _lblCall = [self label:13 bold:NO color:[UIColor colorWithWhite:0.75 alpha:1]];
    _slCall = [self slider:teal tag:2];
    _slCall.value = [self prefInt:@"HLCallMutePercentLeft" dflt:50];

    _lblMute = [self label:13 bold:NO color:[UIColor colorWithWhite:0.75 alpha:1]];
    _slMute = [self slider:teal tag:3];
    _slMute.value = [self prefInt:@"HLMutePercent" dflt:0];

    // 初始化时也吸附一次，保证界面数字 = 真实档位
    for (UISlider *s in @[_slRestore, _slCall, _slMute]) [self snap:s persist:NO];

    _lockLabel = [self label:13 bold:NO color:[UIColor colorWithWhite:0.75 alpha:1]];
    _lockLabel.text = @"右耳锁定在 0（设备自己打开也会按回去）";
    _lockSwitch = [UISwitch new];
    _lockSwitch.onTintColor = teal;
    _lockSwitch.on = [self prefBool:@"HLLockRightEar" dflt:YES];
    [_lockSwitch addTarget:self action:@selector(lockChanged:) forControlEvents:UIControlEventValueChanged];

    _keepLabel = [self label:12 bold:NO color:[UIColor colorWithWhite:0.7 alpha:1]];
    _keepLabel.numberOfLines = 2;
    _keepSwitch = [UISwitch new];
    _keepSwitch.onTintColor = teal;
    _keepSwitch.on = HLKeepAliveEnabled();
    [_keepSwitch addTarget:self action:@selector(keepChanged:) forControlEvents:UIControlEventValueChanged];

    // 联动总开关：关掉后一个字节都不写，但连接和读取照常。
    // 测参数（记基线 → 改设置 → 找差异）必须先关它，否则我们自己写的 1454E9D6
    // 会在差异里反复出现，把真正的变化盖掉。
    _autoLabel = [self label:12 bold:NO color:[UIColor colorWithWhite:0.7 alpha:1]];
    _autoLabel.numberOfLines = 2;
    _autoSwitch = [UISwitch new];
    _autoSwitch.onTintColor = teal;
    _autoSwitch.on = HLGetAutomation();
    [_autoSwitch addTarget:self action:@selector(autoChanged:) forControlEvents:UIControlEventValueChanged];

    // 0.6.5：播放中保持。实测 iPhone 音量键会直接改写麦克风档位，
    // 打开后播放/通话期间被改写会在 1 秒内按回去；关掉则只写一次。
    _holdLabel = [self label:12 bold:NO color:[UIColor colorWithWhite:0.7 alpha:1]];
    _holdLabel.numberOfLines = 2;
    _holdSwitch = [UISwitch new];
    _holdSwitch.onTintColor = teal;
    _holdSwitch.on = [self prefBool:@"HLHoldWhilePlaying" dflt:YES];
    [_holdSwitch addTarget:self action:@selector(holdChanged:) forControlEvents:UIControlEventValueChanged];

    // 0.8.0 自适应麦克风：根据环境噪音自动调节恢复档位
    _adaptiveLabel = [self label:12 bold:NO color:[UIColor colorWithWhite:0.7 alpha:1]];
    _adaptiveLabel.numberOfLines = 2;
    _adaptiveSwitch = [UISwitch new];
    _adaptiveSwitch.onTintColor = teal;
    _adaptiveSwitch.on = HLAdaptiveEnabled();
    [_adaptiveSwitch addTarget:self action:@selector(adaptiveChanged:) forControlEvents:UIControlEventValueChanged];
    _adaptiveInfo = [self label:11 bold:NO color:[UIColor colorWithWhite:0.55 alpha:1]];
    _adaptiveInfo.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _adaptiveInfo.numberOfLines = 2;

    _applyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_applyBtn setTitle:@"立即重新应用" forState:UIControlStateNormal];
    _applyBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [_applyBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    _applyBtn.backgroundColor = [UIColor colorWithRed:0.10 green:0.55 blue:0.50 alpha:1];
    _applyBtn.layer.cornerRadius = 10;
    [_applyBtn addTarget:self action:@selector(applyTapped) forControlEvents:UIControlEventTouchUpInside];

    _logView = [UITextView new];
    _logView.editable = NO;
    _logView.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    _logView.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    _logView.textColor = [UIColor colorWithRed:0.8 green:0.95 blue:0.92 alpha:1];
    _logView.layer.cornerRadius = 10;
    _logView.textContainerInset = UIEdgeInsetsMake(6, 6, 6, 6);

    for (UIView *v in @[_big, _sub, _ears, _micLive,
                        _lblRestore, _slRestore, _lblCall, _slCall,
                        _lblMute, _slMute, _lockLabel, _lockSwitch,
                        _keepLabel, _keepSwitch,
                        _autoLabel, _autoSwitch,
                        _holdLabel, _holdSwitch,
                        _adaptiveLabel, _adaptiveSwitch, _adaptiveInfo,
                        _applyBtn, _logView]) {
        [self.view addSubview:v];
    }

    [self refreshLabels];

    _tick = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                                           selector:@selector(refreshAll) userInfo:nil repeats:YES];
}

- (UILabel *)label:(CGFloat)size bold:(BOOL)bold color:(UIColor *)color {
    UILabel *l = [UILabel new];
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.textColor = color;
    return l;
}

- (UISlider *)slider:(UIColor *)tint tag:(NSInteger)tag {
    UISlider *s = [UISlider new];
    s.minimumTrackTintColor = tint;
    s.minimumValue = 0;
    s.maximumValue = 100;
    s.tag = tag;
    [s addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    return s;
}

- (NSInteger)prefInt:(NSString *)key dflt:(NSInteger)d {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v integerValue] : d;
}

- (BOOL)prefBool:(NSString *)key dflt:(BOOL)d {
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ? [v boolValue] : d;
}

#pragma mark - 档位吸附

// 百分比 → 设备档位 → 反算百分比，保证滑块位置和实际报文档位一致
- (void)snap:(UISlider *)s persist:(BOOL)persist {
    NSInteger mx = HLGetLevelMax();
    if (mx < 1) mx = 15;
    NSInteger lv = (NSInteger)lround(s.value / 100.0 * (double)mx);
    lv = MAX(0, MIN(lv, mx));
    NSInteger pct = (NSInteger)lround(lv * 100.0 / (double)mx);
    if (fabs(s.value - pct) > 0.01) s.value = (float)pct;

    if (!persist) return;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if (s.tag == 1)      [d setInteger:pct forKey:@"HLRestorePercentLeft"];
    else if (s.tag == 2) [d setInteger:pct forKey:@"HLCallMutePercentLeft"];
    else if (s.tag == 3) [d setInteger:pct forKey:@"HLMutePercent"];
    [d synchronize];
}

- (NSInteger)levelOf:(UISlider *)s {
    NSInteger mx = HLGetLevelMax();
    return (NSInteger)lround(s.value / 100.0 * (double)mx);
}

#pragma mark - 布局

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat pad = 16;
    CGFloat y = self.view.safeAreaInsets.top + 6;

    _big.frame = CGRectMake(pad, y, w - pad * 2, 38);            y += 40;
    _sub.frame = CGRectMake(pad, y, w - pad * 2, 16);            y += 19;
    _ears.frame = CGRectMake(pad, y, w - pad * 2, 18);           y += 19;
    _micLive.frame = CGRectMake(pad, y, w - pad * 2, 28);        y += 31;

    _lblRestore.frame = CGRectMake(pad, y, w - pad * 2, 16);
    _slRestore.frame = CGRectMake(pad, y + 15, w - pad * 2, 28);  y += 45;
    _lblCall.frame = CGRectMake(pad, y, w - pad * 2, 16);
    _slCall.frame = CGRectMake(pad, y + 15, w - pad * 2, 28);     y += 45;
    _lblMute.frame = CGRectMake(pad, y, w - pad * 2, 16);
    _slMute.frame = CGRectMake(pad, y + 15, w - pad * 2, 28);     y += 47;

    _lockLabel.frame = CGRectMake(pad, y, w - pad * 2 - 64, 32);
    _lockSwitch.frame = CGRectMake(w - pad - 51, y + 1, 51, 31);  y += 34;

    _holdLabel.frame = CGRectMake(pad, y, w - pad * 2 - 64, 32);
    _holdSwitch.frame = CGRectMake(w - pad - 51, y + 1, 51, 31);  y += 34;

    _adaptiveLabel.frame = CGRectMake(pad, y, w - pad * 2 - 64, 32);
    _adaptiveSwitch.frame = CGRectMake(w - pad - 51, y + 1, 51, 31); y += 34;
    _adaptiveInfo.frame = CGRectMake(pad, y, w - pad * 2, 28);      y += 32;

    _keepLabel.frame = CGRectMake(pad, y, w - pad * 2 - 64, 32);
    _keepSwitch.frame = CGRectMake(w - pad - 51, y + 1, 51, 31);  y += 34;

    _autoLabel.frame = CGRectMake(pad, y, w - pad * 2 - 64, 32);
    _autoSwitch.frame = CGRectMake(w - pad - 51, y + 1, 51, 31);  y += 38;

    _applyBtn.frame = CGRectMake(pad, y, w - pad * 2, 36);        y += 43;

    CGFloat logH = self.view.bounds.size.height - y - self.view.safeAreaInsets.bottom - 8;
    _logView.frame = CGRectMake(pad, y, w - pad * 2, MAX(50, logH));
}

#pragma mark - 刷新

- (void)refreshLabels {
    BOOL playing = HLMediaPlaying();
    BOOL call = HLInCall();

    NSString *text;
    UIColor *color;
    if (call) {
        text = @"通话中 · 左耳按通话档位";
        color = [UIColor colorWithRed:0.45 green:0.75 blue:1.0 alpha:1];
    } else if (playing) {
        text = @"麦克风已压低";
        color = [UIColor colorWithRed:1.0 green:0.72 blue:0.25 alpha:1];
    } else {
        text = @"麦克风正常";
        color = [UIColor colorWithRed:0.42 green:0.86 blue:0.55 alpha:1];
    }
    _big.text = text;
    _big.textColor = color;

    _sub.text = [NSString stringWithFormat:@"声音=%@  通话=%@  类别=%@",
                 playing ? @"有" : @"无", call ? @"是" : @"否", HLCallCategory() ?: @"-"];

    _ears.text = [@"耳机：" stringByAppendingString:HLStatusText() ?: @"?"];
    _micLive.text = [@"音量特征 " stringByAppendingString:HLMicLiveText() ?: @"-"];

    NSInteger rl = [self levelOf:_slRestore];
    NSInteger cl = [self levelOf:_slCall];
    NSInteger ml = [self levelOf:_slMute];

    _lblRestore.text = [NSString stringWithFormat:@"安静时左耳恢复：档位 %ld · %ld%%", (long)rl, (long)lround(_slRestore.value)];
    _lblCall.text    = [NSString stringWithFormat:@"通话时左耳：档位 %ld · %ld%%", (long)cl, (long)lround(_slCall.value)];
    _lblMute.text    = [NSString stringWithFormat:@"其他 App 出声时压低到：档位 %ld · %ld%%（右耳始终 0）", (long)ml, (long)lround(_slMute.value)];

    BOOL running = HLKeepAliveRunning();
    BOOL enabled = HLKeepAliveEnabled();
    if (!enabled) {
        _keepLabel.text = @"后台音频保活：关（推荐保持关闭，BLE 保活已够）";
        _keepLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    } else if (running) {
        _keepLabel.text = @"后台音频保活：运行中（防后台被杀）";
        _keepLabel.textColor = [UIColor colorWithRed:0.42 green:0.86 blue:0.55 alpha:1];
    } else {
        _keepLabel.text = @"后台音频保活：已开但未运行，点开关重试";
        _keepLabel.textColor = [UIColor colorWithRed:1.0 green:0.72 blue:0.25 alpha:1];
    }
    if (_keepSwitch.on != enabled) _keepSwitch.on = enabled;

    BOOL auto_ = HLGetAutomation();
    if (auto_) {
        _autoLabel.text = @"联动写入：运行中（正常使用）";
        _autoLabel.textColor = [UIColor colorWithRed:0.42 green:0.86 blue:0.55 alpha:1];
    } else {
        _autoLabel.text = @"联动写入：已暂停（测参数用，不写任何东西）";
        _autoLabel.textColor = [UIColor colorWithRed:1.0 green:0.72 blue:0.25 alpha:1];
    }
    if (_autoSwitch.on != auto_) _autoSwitch.on = auto_;

    BOOL hold = [self prefBool:@"HLHoldWhilePlaying" dflt:YES];
    if (hold) {
        _holdLabel.text = @"播放中保持：开（音量键改档 1 秒内按回）";
        _holdLabel.textColor = [UIColor colorWithRed:0.42 green:0.86 blue:0.55 alpha:1];
    } else {
        _holdLabel.text = @"播放中保持：关（只在切换瞬间写一次）";
        _holdLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1];
    }
    if (_holdSwitch.on != hold) _holdSwitch.on = hold;

    // 0.8.0 自适应麦克风
    BOOL adaptive = HLAdaptiveEnabled();
    if (adaptive) {
        double db = HLAdaptiveCurrentDB();
        NSInteger pct = HLAdaptiveRestorePercent();
        _adaptiveLabel.text = @"自适应麦克风：运行中（环境噪音自动调档）";
        _adaptiveLabel.textColor = [UIColor colorWithRed:0.42 green:0.86 blue:0.55 alpha:1];
        _adaptiveInfo.text = [NSString stringWithFormat:@"环境 %.0f dB · 恢复档位 %ld%%",
                              db, (long)pct];
    } else {
        _adaptiveLabel.text = @"自适应麦克风：关（手动调档）";
        _adaptiveLabel.textColor = [UIColor colorWithWhite:0.55 alpha:1];
        _adaptiveInfo.text = @"打开后根据环境噪音自动调节恢复档位";
    }
    if (_adaptiveSwitch.on != adaptive) _adaptiveSwitch.on = adaptive;
}

- (void)refreshAll {
    [self refreshLabels];

    NSArray<NSString *> *lines = HLRecentLines();
    if (lines.count != _lastLogCount) {
        _lastLogCount = lines.count;
        NSUInteger from = lines.count > 120 ? lines.count - 120 : 0;
        _logView.text = [[lines subarrayWithRange:NSMakeRange(from, lines.count - from)]
                         componentsJoinedByString:@"\n"];
        [_logView scrollRangeToVisible:NSMakeRange(_logView.text.length, 0)];
    }
}

#pragma mark - 交互

- (void)sliderChanged:(UISlider *)s {
    [self snap:s persist:YES];
    [self refreshLabels];
}

- (void)lockChanged:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:@"HLLockRightEar"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    HLReapplyNow();
}

- (void)autoChanged:(UISwitch *)sw {
    HLSetAutomation(sw.on);
    [self refreshLabels];
}

- (void)holdChanged:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:@"HLHoldWhilePlaying"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self refreshLabels];
}

- (void)adaptiveChanged:(UISwitch *)sw {
    HLSetAdaptive(sw.on);
    [self refreshLabels];
}

- (void)keepChanged:(UISwitch *)sw {
    HLSetKeepAlive(sw.on);
    [self refreshLabels];
}

- (void)applyTapped {
    HLReapplyNow();
    [self refreshAll];
}

- (void)dealloc { [_tick invalidate]; }

@end
