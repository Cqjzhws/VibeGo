//
//  VGLabVC.m — 实验室
//
//  四个分区：
//   ① 矩阵    全部 116 条特征 + 语义注解 + 能力标记，可全量读、导出 JSON
//   ② 对比    快照对比：记一次基线 → 去 iOS 里改一个设置 → 找差异
//             这是定位「程序切换 / 总音量 / 降噪 / 方向性」最快的方法
//   ③ 写入    写入实验台：列出所有可写特征，点一行输入十六进制写入，
//             输入框默认填当前值，写错了再点一次改回去即可
//   ④ 设备    制造商 / 型号 / 序列号 / 固件 / 电量 / 当前程序名
//

#import "VGLabVC.h"

extern NSArray<NSDictionary *> *HLCapabilityReport(void);
extern void HLReadAllChars(void);
extern void HLReadDeviceInfo(void);
extern NSString *HLMicLiveText(void);
extern NSString *HLStatusText(void);
extern NSDictionary<NSString *, NSString *> *HLSnapshotValues(void);
extern BOOL HLWriteCharHex(NSString *ear, NSString *uuid, NSString *hex);
extern NSDictionary *HLDeviceInfo(void);
extern NSInteger HLGetLevelMax(void);

static UIColor *VGTeal(void)  { return [UIColor colorWithRed:0.30 green:0.85 blue:0.75 alpha:1]; }
static UIColor *VGBg(void)    { return [UIColor colorWithRed:0.035 green:0.055 blue:0.07 alpha:1]; }
static UIColor *VGCard(void)  { return [UIColor colorWithWhite:0.06 alpha:1]; }
static UIColor *VGDim(void)   { return [UIColor colorWithWhite:0.55 alpha:1]; }

@interface VGLabVC () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UILabel *statusLine;
@property (nonatomic, strong) UISegmentedControl *seg;

@property (nonatomic, strong) UIView *pageMatrix, *pageDiff, *pageWrite, *pageDevice;

// 矩阵页
@property (nonatomic, strong) UITextView *matrixText;
@property (nonatomic, strong) UIButton *readBtn, *exportBtn;

// 对比页
@property (nonatomic, strong) UILabel *diffHint;
@property (nonatomic, strong) UIButton *baseBtn, *diffBtn;
@property (nonatomic, strong) UITextView *diffText;
@property (nonatomic, strong) NSDictionary<NSString *, NSString *> *baseline;
@property (nonatomic, strong) NSString *baselineAt;

// 写入页
@property (nonatomic, strong) UITableView *writeTable;
@property (nonatomic, strong) NSArray<NSDictionary *> *writableRows;

// 设备页
@property (nonatomic, strong) UITextView *deviceText;

@property (nonatomic, strong) NSTimer *tick;

@end

@implementation VGLabVC

- (instancetype)init {
    if ((self = [super init])) {
        self.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"实验室"
                                                        image:[UIImage systemImageNamed:@"testtube.2"] tag:3];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"实验室";
    self.view.backgroundColor = VGBg();

    _statusLine = [UILabel new];
    _statusLine.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _statusLine.textColor = VGDim();
    _statusLine.numberOfLines = 2;

    _seg = [[UISegmentedControl alloc] initWithItems:@[@"矩阵", @"对比", @"写入", @"设备"]];
    _seg.selectedSegmentIndex = 0;
    _seg.selectedSegmentTintColor = [UIColor colorWithRed:0.12 green:0.45 blue:0.42 alpha:1];
    [_seg setTitleTextAttributes:@{NSForegroundColorAttributeName: UIColor.whiteColor}
                        forState:UIControlStateSelected];
    [_seg addTarget:self action:@selector(segmentChanged) forControlEvents:UIControlEventValueChanged];

    [self buildMatrixPage];
    [self buildDiffPage];
    [self buildWritePage];
    [self buildDevicePage];

    for (UIView *v in @[_statusLine, _seg, _pageMatrix, _pageDiff, _pageWrite, _pageDevice])
        [self.view addSubview:v];

    [self loadBaselineIfAny];
    [self segmentChanged];

    _tick = [NSTimer scheduledTimerWithTimeInterval:3.0 target:self
                                           selector:@selector(slowRefresh) userInfo:nil repeats:YES];
}

#pragma mark - 建页

- (UITextView *)textView {
    UITextView *t = [UITextView new];
    t.editable = NO;
    t.font = [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular];
    t.backgroundColor = VGCard();
    t.textColor = [UIColor colorWithRed:0.8 green:0.95 blue:0.92 alpha:1];
    t.layer.cornerRadius = 10;
    t.textContainerInset = UIEdgeInsetsMake(6, 6, 6, 6);
    return t;
}

- (UIButton *)button:(NSString *)title color:(UIColor *)color {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.backgroundColor = color;
    b.layer.cornerRadius = 9;
    return b;
}

- (void)buildMatrixPage {
    _pageMatrix = [UIView new];

    _readBtn = [self button:@"全量读取" color:[UIColor colorWithRed:0.10 green:0.55 blue:0.50 alpha:1]];
    [_readBtn addTarget:self action:@selector(readTapped) forControlEvents:UIControlEventTouchUpInside];
    _exportBtn = [self button:@"导出 JSON" color:[UIColor colorWithWhite:0.16 alpha:1]];
    [_exportBtn addTarget:self action:@selector(exportTapped) forControlEvents:UIControlEventTouchUpInside];

    _matrixText = [self textView];
    for (UIView *v in @[_readBtn, _exportBtn, _matrixText]) [_pageMatrix addSubview:v];
}

- (void)buildDiffPage {
    _pageDiff = [UIView new];

    _diffHint = [UILabel new];
    _diffHint.font = [UIFont systemFontOfSize:12];
    _diffHint.textColor = VGDim();
    _diffHint.numberOfLines = 3;
    _diffHint.text = @"① 记基线 → 去 iOS 设置里改一个东西（切程序 / 调音量 / 改降噪）→ ② 找差异";

    _baseBtn = [self button:@"① 记基线" color:[UIColor colorWithRed:0.10 green:0.55 blue:0.50 alpha:1]];
    [_baseBtn addTarget:self action:@selector(baseTapped) forControlEvents:UIControlEventTouchUpInside];
    _diffBtn = [self button:@"② 找差异" color:[UIColor colorWithRed:0.60 green:0.42 blue:0.10 alpha:1]];
    [_diffBtn addTarget:self action:@selector(diffTapped) forControlEvents:UIControlEventTouchUpInside];

    _diffText = [self textView];
    _diffText.text = @"还没记基线。\n\n用法：\n1. 点「全量读取」（在矩阵页）让所有特征都读到值\n2. 回来点「① 记基线」\n3. 打开厂商 App，只改一项（声音平衡 / 音量 / 方向性）\n4. 从多任务划掉厂商 App，回来点「② 找差异」\n\n单字节的值后面会跟一个括号：\n  09（9）        正数\n  F9（249 / 有符号 -7）   ← 声音平衡这类参数是 4 位有符号数，看到负数就对了\n\n变化了的特征会一字不差列出来，那些就是以后能做成功能的入口。";

    for (UIView *v in @[_diffHint, _baseBtn, _diffBtn, _diffText]) [_pageDiff addSubview:v];
}

- (void)buildWritePage {
    _pageWrite = [UIView new];

    UILabel *warn = [UILabel new];
    warn.font = [UIFont systemFontOfSize:11];
    warn.textColor = [UIColor colorWithRed:1.0 green:0.62 blue:0.35 alpha:1];
    warn.numberOfLines = 3;
    warn.text = @"⚠️ 只对「可写」特征开放。输入框默认是当前值，写坏了再点一次改回去。\n不认识的uuid别乱填，尤其是命令通道那五条。";
    warn.tag = 901;

    _writeTable = [UITableView new];
    _writeTable.backgroundColor = [UIColor clearColor];
    _writeTable.separatorColor = [UIColor colorWithWhite:0.16 alpha:1];
    _writeTable.dataSource = self;
    _writeTable.delegate = self;
    _writeTable.rowHeight = 54;
    _writeTable.sectionHeaderHeight = 0;

    [_pageWrite addSubview:warn];
    [_pageWrite addSubview:_writeTable];
}

- (void)buildDevicePage {
    _pageDevice = [UIView new];
    _deviceText = [self textView];
    [_pageDevice addSubview:_deviceText];
    [self refreshDevice];
}

#pragma mark - 布局

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width, pad = 14;
    CGFloat y = self.view.safeAreaInsets.top + 4;

    _statusLine.frame = CGRectMake(pad, y, w - pad * 2, 28);        y += 30;
    _seg.frame = CGRectMake(pad, y, w - pad * 2, 30);               y += 38;

    CGFloat h = self.view.bounds.size.height - y - self.view.safeAreaInsets.bottom - 6;
    for (UIView *p in @[_pageMatrix, _pageDiff, _pageWrite, _pageDevice])
        p.frame = CGRectMake(0, y, w, h);

    // 矩阵
    CGFloat bw = (w - pad * 2 - 10) / 2;
    _readBtn.frame = CGRectMake(pad, 0, bw, 34);
    _exportBtn.frame = CGRectMake(pad + bw + 10, 0, bw, 34);
    _matrixText.frame = CGRectMake(pad, 40, w - pad * 2, h - 46);

    // 对比
    _diffHint.frame = CGRectMake(pad, 0, w - pad * 2, 46);
    _baseBtn.frame = CGRectMake(pad, 50, bw, 34);
    _diffBtn.frame = CGRectMake(pad + bw + 10, 50, bw, 34);
    _diffText.frame = CGRectMake(pad, 90, w - pad * 2, h - 96);

    // 写入
    UIView *warn = [_pageWrite viewWithTag:901];
    warn.frame = CGRectMake(pad, 0, w - pad * 2, 44);
    _writeTable.frame = CGRectMake(pad, 46, w - pad * 2, h - 50);

    // 设备
    _deviceText.frame = CGRectMake(pad, 0, w - pad * 2, h - 4);
}

- (void)segmentChanged {
    NSInteger i = _seg.selectedSegmentIndex;
    _pageMatrix.hidden = (i != 0);
    _pageDiff.hidden   = (i != 1);
    _pageWrite.hidden  = (i != 2);
    _pageDevice.hidden = (i != 3);

    if (i == 0) [self refreshMatrix];
    if (i == 2) [self reloadWritable];
    if (i == 3) [self refreshDevice];

    [self.view setNeedsLayout];
}

- (void)slowRefresh {
    _statusLine.text = [NSString stringWithFormat:@"%@   满量程 %ld 档",
                        HLStatusText() ?: @"未连接", (long)HLGetLevelMax()];
    if (!_pageDevice.hidden) [self refreshDevice];
}

#pragma mark - 矩阵

- (void)refreshMatrix {
    NSArray<NSDictionary *> *rows = HLCapabilityReport();
    _statusLine.text = [NSString stringWithFormat:@"%@   满量程 %ld 档",
                        HLStatusText() ?: @"未连接", (long)HLGetLevelMax()];

    if (!rows.count) {
        _matrixText.text = @"还没连上耳朵。\n等「麦克风」页显示「左耳✓ 右耳✓」再回来看。";
        return;
    }

    NSUInteger writable = 0, notify = 0;
    for (NSDictionary *r in rows) {
        if ([r[@"writable"] boolValue]) writable++;
        if ([r[@"notify"] boolValue]) notify++;
    }

    NSMutableArray *ears = [NSMutableArray array];
    NSMutableDictionary *byEar = [NSMutableDictionary dictionary];
    for (NSDictionary *r in rows) {
        NSString *ear = r[@"ear"];
        if (!byEar[ear]) { byEar[ear] = [NSMutableArray array]; [ears addObject:ear]; }
        [byEar[ear] addObject:r];
    }

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"共 %lu 条　可写 %lu　可通知 %lu\n", (unsigned long)rows.count,
                       (unsigned long)writable, (unsigned long)notify];
    [out appendFormat:@"音量特征 %@\n", HLMicLiveText() ?: @"-"];
    [out appendString:@"\n图例：✎可写 🔔通知 ⭐已确认 ?未知"];

    for (NSString *ear in ears) {
        [out appendFormat:@"\n\n═══ %@ ═══", ear];
        NSMutableArray *svcs = [NSMutableArray array];
        NSMutableDictionary *bySvc = [NSMutableDictionary dictionary];
        for (NSDictionary *r in byEar[ear]) {
            NSString *svc = r[@"service"];
            if (!bySvc[svc]) { bySvc[svc] = [NSMutableArray array]; [svcs addObject:svc]; }
            [bySvc[svc] addObject:r];
        }
        for (NSString *svc in svcs) {
            [out appendFormat:@"\n\n▸ 服务 %@\n", [self short:svc]];
            for (NSDictionary *r in bySvc[svc]) {
                BOOL wr = [r[@"writable"] boolValue];
                BOOL nt = [r[@"notify"] boolValue];
                NSString *mark = wr ? @"✎" : (nt ? @"🔔" : @" ");
                NSString *val = [r[@"value"] length] ? r[@"value"] : @"-";
                if ([r[@"writeOnly"] boolValue]) val = @"(只写)";
                NSString *note = [r[@"note"] length] ? r[@"note"] : @"";
                [out appendFormat:@"%@ %@ %-7@ %-18@ %@\n",
                 mark, [self short:r[@"uuid"]], r[@"props"], val, note];
            }
        }
    }
    _matrixText.text = out;
}

- (NSString *)short:(NSString *)uuid {
    return uuid.length > 8 ? [uuid substringToIndex:8] : uuid;
}

- (void)readTapped {
    HLReadAllChars();
    HLReadDeviceInfo();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self refreshMatrix]; });
}

- (void)exportTapped {
    NSArray<NSDictionary *> *rows = HLCapabilityReport();
    NSDictionary *doc = @{
        @"exportedAt": @([[NSDate date] timeIntervalSince1970]),
        @"ears": HLStatusText() ?: @"",
        @"mic": HLMicLiveText() ?: @"",
        @"device": HLDeviceInfo() ?: @{},
        @"characteristics": rows
    };
    NSError *err = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:doc
                                                    options:NSJSONWritingPrettyPrinted
                                                      error:&err];
    if (err) { _statusLine.text = [@"导出失败：" stringByAppendingString:err.localizedDescription]; return; }

    NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)
                      .firstObject stringByAppendingPathComponent:@"VibeGo-能力矩阵.json"];
    [json writeToFile:path atomically:YES];

    UIActivityViewController *a = [[UIActivityViewController alloc]
                                   initWithActivityItems:@[[NSURL fileURLWithPath:path]]
                                   applicationActivities:nil];
    a.popoverPresentationController.sourceView = _exportBtn;
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 快照对比

// 这些特征一直在自己跳（电平表 / 计数器 / 状态字节 / 电量），对比时纯噪声。
// 单列出来，免得真正的设置变化被淹没。
static BOOL HLIsNoiseUUID(NSString *u) {
    static NSSet *noise; static dispatch_once_t once;
    dispatch_once(&once, ^{
        noise = [NSSet setWithArray:@[@"42E940EF", @"ADC3023D", @"BC6829C4", @"2A19",
                                      @"F3F594F9", @"C8F7FAC0", @"D01AB591", @"24E1DFF3",
                                      @"58BBCCC5", @"16438C66",
                                      // 2026-10-26 实测定性：C8F7690C 是设备主动推送的计数器
                                      // （两份旧快照里都是空，只有推送时才出现；byte1 单调变化，
                                      //  两耳独立。00:00 那次它被误判成「重点」，其实是噪声）
                                      @"C8F7690C"]];
    });
    return [noise containsObject:[u uppercaseString]];
}

- (NSString *)baselinePath {
    return [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)
            .firstObject stringByAppendingPathComponent:@"VibeGo-baseline.plist"];
}

// 基线落盘：App 被系统杀掉、或者切去厂商 App 时，基线不能丢
- (void)saveBaseline {
    if (!_baseline.count) return;
    NSDictionary *doc = @{@"at": _baselineAt ?: @"", @"values": _baseline};
    [doc writeToFile:[self baselinePath] atomically:YES];
}

- (void)loadBaselineIfAny {
    NSDictionary *doc = [NSDictionary dictionaryWithContentsOfFile:[self baselinePath]];
    NSDictionary *v = doc[@"values"];
    if (![v isKindOfClass:[NSDictionary class]] || !v.count) return;
    _baseline = v;
    _baselineAt = doc[@"at"] ?: @"?";
    _diffHint.text = [NSString stringWithFormat:@"已载入上次基线 %@（%lu 条）。可直接点「② 找差异」。",
                      _baselineAt, (unsigned long)_baseline.count];
}

- (void)baseTapped {
    // 先全量读一遍，否则很多特征还没值，对比时全是「(无) → X」的假差异
    HLReadAllChars();
    HLReadDeviceInfo();
    _diffHint.text = @"正在全量读取…";
    _baseBtn.enabled = NO;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        _baseline = HLSnapshotValues();
        NSDateFormatter *f = [NSDateFormatter new];
        f.dateFormat = @"HH:mm:ss";
        _baselineAt = [f stringFromDate:[NSDate date]];
        _baseBtn.enabled = YES;

        NSUInteger filled = 0;
        for (NSString *k in _baseline) if ([_baseline[k] length]) filled++;

        if (filled < _baseline.count / 2) {
            _diffHint.text = @"基线没读全";
            _diffText.text = [NSString stringWithFormat:
                              @"只读到 %lu 条有值（共 %lu 条）。\n\n"
                              @"多半是刚启动还没连稳。等「麦克风」页显示「左耳✓ 右耳✓」，再点一次「① 记基线」。",
                              (unsigned long)filled, (unsigned long)_baseline.count];
            return;
        }
        [self saveBaseline];
        _diffHint.text = [NSString stringWithFormat:@"基线已记：%lu 条（有值 %lu）%@",
                          (unsigned long)_baseline.count, (unsigned long)filled, _baselineAt];
        _diffText.text = @"基线已存好（已落盘，App 被杀也不丢）。\n\n"
                          "现在按这个顺序操作：\n\n"
                          "1. 打开厂商 App，改一个设置（切程序 / 拖音量 / 调降噪）\n"
                          "2. 从多任务里把厂商 App 划掉，让它松开蓝牙\n"
                          "3. 回到这里，点「② 找差异」\n\n"
                          "（第 2 步很重要：厂商 App 占着蓝牙时，我们连不上，读不到值）";
    });
}

- (void)diffTapped {
    if (!_baseline.count) {
        _diffText.text = @"还没有基线。先点「① 记基线」。";
        return;
    }
    _diffBtn.enabled = NO;
    [self waitLinkForDiff:0];
}

// 等两只耳都连上再读 —— 上一版就是没等，切去厂商 App 后连接是断的，
// 拍出来是空快照，116 条全变成「(无)」，白折腾一轮。
- (void)waitLinkForDiff:(NSInteger)tryCount {
    NSString *st = HLStatusText() ?: @"未连接";
    BOOL both = [st containsString:@"左耳✓"] && [st containsString:@"右耳✓"];

    if (both) { [self readThenDiff]; return; }

    if (tryCount >= 40) {          // 最多等 20 秒
        _diffHint.text = @"连不上，没法对比";
        _diffText.text = [NSString stringWithFormat:
                          @"等了 20 秒，两只耳还是没连上。\n\n当前状态：%@\n\n"
                          @"请检查：\n"
                          @"· 厂商 App 是不是还在后台占着蓝牙？（从多任务里划掉它）\n"
                          @"· 「麦克风」页是不是显示「左耳✓ 右耳✓」？\n\n"
                          @"连上之后再点「② 找差异」，基线还在，不用重记。", st];
        _diffBtn.enabled = YES;
        return;
    }

    _diffHint.text = [NSString stringWithFormat:@"等待重连… %.1fs   当前：%@", tryCount * 0.5, st];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ [self waitLinkForDiff:tryCount + 1]; });
}

- (void)readThenDiff {
    _diffHint.text = @"已连上，正在读取全部特征…";
    HLReadAllChars();
    HLReadDeviceInfo();

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSDictionary<NSString *, NSString *> *now = HLSnapshotValues();
        NSUInteger filled = 0;
        for (NSString *k in now) if ([now[k] length]) filled++;

        if (filled < _baseline.count / 2) {
            _diffHint.text = @"读取不完整";
            _diffText.text = [NSString stringWithFormat:
                              @"这次只读到 %lu 条有值（基线 %lu 条），比不出来的。\n\n"
                              @"刚重连上时设备还没回完值，再点一次「② 找差异」，通常就好。",
                              (unsigned long)filled, (unsigned long)_baseline.count];
            _diffBtn.enabled = YES;
            return;
        }
        [self computeDiff:now];
        _diffBtn.enabled = YES;
    });
}

// 单字节值补一个有符号解释。
// 「声音平衡」实测范围 -8 ~ +7，正好是 4 位有符号数（int4）的完整区间，
// 所以这类参数在报文里很可能是 F8~07 的补码。差异里看到 "F9" 反应不过来是 -7，
// 这里直接写清楚，省得每次都要手算。
static NSString *HLSignedHint(NSString *hex) {
    if (!hex.length || [hex isEqualToString:@"(无)"]) return @"";
    NSArray *b = [hex componentsSeparatedByString:@" "];
    if (b.count != 1) return @"";
    NSString *s = b[0];
    if (s.length != 2) return @"";
    unsigned v = 0;
    NSScanner *sc = [NSScanner scannerWithString:s];
    sc.scanLocation = 0;
    if (![sc scanHexInt:&v] || sc.scanLocation != 2) return @"";
    int n = (int)(int8_t)(v & 0xFF);
    if (n >= 0) return [NSString stringWithFormat:@"（%u）", v];
    return [NSString stringWithFormat:@"（%u / 有符号 %d）", v, n];
}

- (void)computeDiff:(NSDictionary<NSString *, NSString *> *)now {
    NSMutableArray *key = [NSMutableArray array];      // 可能是设置项
    NSMutableArray *noise = [NSMutableArray array];    // 电平 / 计数 / 状态

    NSMutableSet *keys = [NSMutableSet setWithArray:_baseline.allKeys];
    [keys addObjectsFromArray:now.allKeys];

    // 注解表（此时已连上，能取到）
    NSMutableDictionary *notes = [NSMutableDictionary dictionary];
    for (NSDictionary *r in HLCapabilityReport()) {
        NSString *u = [self short:r[@"uuid"]];
        if (u.length && r[@"note"]) notes[u] = r[@"note"];
    }

    for (NSString *k in keys) {
        NSString *a = _baseline[k] ?: @"(无)";
        NSString *b = now[k] ?: @"(无)";
        if ([a isEqualToString:b]) continue;

        NSArray *parts = [k componentsSeparatedByString:@"|"];
        NSString *ear = parts.count > 0 ? parts[0] : @"?";
        NSString *uuid = parts.count > 1 ? parts[1] : @"?";
        NSString *note = notes[[uuid uppercaseString]] ?: @"";

        NSString *line = [NSString stringWithFormat:@"%@ %@  %@\n   %@%@  →  %@%@",
                          ear, uuid, note, a, HLSignedHint(a), b, HLSignedHint(b)];
        if (HLIsNoiseUUID(uuid)) [noise addObject:line];
        else                     [key addObject:line];
    }

    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"HH:mm:ss";
    NSString *nowStr = [f stringFromDate:[NSDate date]];
    NSUInteger total = key.count + noise.count;

    _diffHint.text = [NSString stringWithFormat:@"%@ → %@：重点 %lu 条，噪声 %lu 条",
                      _baselineAt, nowStr, (unsigned long)key.count, (unsigned long)noise.count];

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"基线 %@ → %@\n共 %lu 条变化\n\n", _baselineAt, nowStr, (unsigned long)total];

    if (key.count) {
        [out appendString:@"═══ 重点：可能是设置项 ═══\n\n"];
        for (NSString *l in key) [out appendFormat:@"%@\n\n", l];
    } else {
        [out appendString:@"═══ 没有发现设置项变化 ═══\n\n"];
        [out appendString:@"只有噪声（电平/计数/状态）在跳。可能原因：\n"
                        @"· 这个设置走加密的 FAPI 命令通道，不落在 BLE 特征上\n"
                        @"· 或者厂商 App 里这项其实没改\n"
                        @"· 或者改了但设备只在断开时保存（需要重连后才读得到）\n\n"];
    }

    if (noise.count) {
        [out appendString:@"═══ 噪声（忽略即可）═══\n\n"];
        for (NSString *l in noise) [out appendFormat:@"%@\n\n", l];
    }

    [out appendString:@"——\n把这块发我就行。"];
    _diffText.text = out;
}

#pragma mark - 写入实验台

- (void)reloadWritable {
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *r in HLCapabilityReport()) {
        if (![r[@"writable"] boolValue]) continue;
        if ([r[@"isMic"] boolValue]) continue;      // 麦克风走联动逻辑，别在这里手写
        [rows addObject:r];
    }
    // 有注解的先排前面
    [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        BOOL na = [a[@"note"] length] > 0, nb = [b[@"note"] length] > 0;
        if (na != nb) return na ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"uuid"] compare:b[@"uuid"]];
    }];
    _writableRows = rows;
    [_writeTable reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _writableRows.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"wcell";
    UITableViewCell *c = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!c) c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];

    NSDictionary *r = _writableRows[indexPath.row];
    c.backgroundColor = [UIColor clearColor];
    c.textLabel.textColor = UIColor.whiteColor;
    c.detailTextLabel.textColor = VGDim();
    c.textLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
    c.detailTextLabel.font = [UIFont systemFontOfSize:11];
    c.detailTextLabel.numberOfLines = 2;

    NSString *val = [r[@"value"] length] ? r[@"value"] : (([r[@"writeOnly"] boolValue]) ? @"只写" : @"(空)");
    c.textLabel.text = [NSString stringWithFormat:@"%@ %@  = %@", r[@"ear"], [self short:r[@"uuid"]], val];
    c.detailTextLabel.text = [NSString stringWithFormat:@"%@  %@",
                              r[@"props"], [r[@"note"] length] ? r[@"note"] : @"—"];
    return c;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *r = _writableRows[indexPath.row];

    NSString *ear = r[@"ear"];
    NSString *uuid = r[@"uuid"];
    NSString *cur = [r[@"value"] length] ? r[@"value"] : @"";

    NSString *title = [NSString stringWithFormat:@"写入 %@ %@", ear, [self short:uuid]];
    NSString *msg = [NSString stringWithFormat:@"%@\n属性 %@\n\n输入十六进制，如 09 01\n输入框里是当前值，写坏了原样写回即可。",
                     [r[@"note"] length] ? r[@"note"] : @"(无注解)", r[@"props"]];

    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                              message:msg
                                                       preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.text = cur;
        tf.placeholder = @"如 09 01";
        tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.font = [UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightRegular];
    }];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"写入" style:UIAlertActionStyleDestructive
                                       handler:^(UIAlertAction *act) {
        NSString *hex = a.textFields.firstObject.text ?: @"";
        BOOL ok = HLWriteCharHex(ear, uuid, hex);
        _statusLine.text = ok ? [NSString stringWithFormat:@"已写 %@ %@ = %@", ear, [self short:uuid], hex]
                              : [NSString stringWithFormat:@"写入失败：%@ %@", ear, [self short:uuid]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ [self reloadWritable]; });
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 设备信息

- (void)refreshDevice {
    NSDictionary *d = HLDeviceInfo() ?: @{};
    NSMutableString *out = [NSMutableString string];
    [out appendString:@"═══ 设备 ═══\n"];
    for (NSString *k in @[@"制造商", @"型号", @"序列号", @"硬件", @"固件", @"软件", @"电量"]) {
        NSString *v = d[k] ?: @"";
        [out appendFormat:@"%-6@  %@\n", k, v.length ? v : @"(未读到)"];
    }

    NSString *prog = d[@"程序名"] ?: @"";
    [out appendFormat:@"\n═══ 当前聆听程序 ═══\n"];
    [out appendFormat:@"%@\n", prog.length ? prog : @"(未读到)"];
    [out appendFormat:@"原值 %@\n", d[@"程序原值"] ?: @""];
    if (prog.length) {
        [out appendString:@"\n这是从 7BE94A55 读出来的 30 字节 ASCII。\n"
                        "它是 R/W —— 可能能直接切程序。\n"
                        "想试的话：先用「对比」记基线，去 iOS 里切一个程序，\n"
                        "看这条会不会跟着变；变了就说明能写，再拿「写入」试。"];
    }

    [out appendFormat:@"\n═══ 联动参数 ═══\n满量程 %ld 档\n音量特征 %@\n",
     (long)HLGetLevelMax(), HLMicLiveText() ?: @"-"];

    [out appendString:@"\n═══ 已知结论 ═══\n"
                    "1454E9D6  麦克风音量 [档位][01] ⭐已确认\n"
                    "8B820C6D  疑似总音量，和麦克风同构 [档位][01]\n"
                    "7BE94A55  当前程序名（ASCII 30 字节）\n"
                    "8D17AC2F  00=左 01=右，判侧别用这个\n"
                    "F3F594F9  状态字节，会跟着写入乱跳，别校验它\n"
                    "6D5758A1 / 786FF607 / 6EFAB52E / 62DCC92F / 8B8276E8\n"
                    "          纯命令通道（只写），改设置大概率走这五条\n"
                    "\n⚠️ 想挖 EQ / 压缩 / 方向性：\n"
                    "它们多半走命令通道，写进去不回报值，\n"
                    "「对比」也看不到。要么抓厂商 App 的包，\n"
                    "要么一条条试写 —— 后者风险高，别动助听器主力配置。"];

    _deviceText.text = out;
}

- (void)dealloc { [_tick invalidate]; }

@end
