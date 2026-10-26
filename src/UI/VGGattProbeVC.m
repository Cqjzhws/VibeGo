#import "VGGattProbeVC.h"
#import "VGGattProbe.h"
#import "VGProbeDevice.h"
#import "VGProbeSnapshot.h"
#import "VGEarMap.h"
#import <objc/runtime.h>

@interface VGGattProbeVC ()
@property (nonatomic, strong) UILabel *stateLabel;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UITextView *deviceInfoView;
@property (nonatomic, strong) UIStackView *earBtnStack;
@property (nonatomic, strong) UIButton *startBtn;
@property (nonatomic, strong) UIButton *shareBtn;
@property (nonatomic, copy) NSArray<VGProbeDevice *> *currentDevices;
@end

@implementation VGGattProbeVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"GATT 只读探测";
    self.view.backgroundColor = [UIColor colorWithRed:0.035 green:0.055 blue:0.07 alpha:1];

    // 清空比对基线（长跑的语义推断工具：换验配后想重新起基线时用）
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"清基线"
                                         style:UIBarButtonItemStylePlain
                                        target:self action:@selector(resetBaselineTapped)];

    UILabel *warn = [UILabel new];
    warn.text = @"安全只读：不鉴权、不写入、不订阅通知。每次探测结束会与上次自动比对，列出发生变化的特征。";
    warn.font = [UIFont systemFontOfSize:12];
    warn.textColor = [UIColor colorWithRed:0.4 green:0.85 blue:0.8 alpha:1];
    warn.numberOfLines = 0;
    warn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:warn];

    self.stateLabel = [UILabel new];
    self.stateLabel.text = @"空闲";
    self.stateLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.stateLabel.textColor = UIColor.whiteColor;
    self.stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.stateLabel];

    self.startBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startBtn setTitle:@"开始探测（约15–45秒）" forState:UIControlStateNormal];
    self.startBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    [self.startBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.startBtn.backgroundColor = [UIColor colorWithRed:0.10 green:0.55 blue:0.50 alpha:1];
    self.startBtn.layer.cornerRadius = 12;
    self.startBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.startBtn addTarget:self action:@selector(startTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startBtn];

    self.shareBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.shareBtn setTitle:@"分享日志" forState:UIControlStateNormal];
    self.shareBtn.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [self.shareBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    self.shareBtn.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1];
    self.shareBtn.layer.cornerRadius = 12;
    self.shareBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.shareBtn addTarget:self action:@selector(shareTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.shareBtn];

    self.logView = [UITextView new];
    self.logView.editable = NO;
    self.logView.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.logView.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];
    self.logView.textColor = [UIColor colorWithRed:0.8 green:0.95 blue:0.92 alpha:1];
    self.logView.layer.cornerRadius = 12;
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.logView];

    self.deviceInfoView = [UITextView new];
    self.deviceInfoView.editable = NO;
    self.deviceInfoView.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont systemFontOfSize:11];
    self.deviceInfoView.backgroundColor = [UIColor colorWithRed:0.06 green:0.13 blue:0.12 alpha:1];
    self.deviceInfoView.textColor = [UIColor colorWithRed:0.45 green:0.95 blue:0.85 alpha:1];
    self.deviceInfoView.layer.cornerRadius = 12;
    self.deviceInfoView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.deviceInfoView];

    // 左右耳设定行（每只设备一行：短ID + 左耳 + 右耳，点一次全局记忆）
    self.earBtnStack = [UIStackView new];
    self.earBtnStack.axis = UILayoutConstraintAxisVertical;
    self.earBtnStack.spacing = 6;
    self.earBtnStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.earBtnStack];

    [NSLayoutConstraint activateConstraints:@[
        [warn.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:12],
        [warn.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [warn.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.stateLabel.topAnchor constraintEqualToAnchor:warn.bottomAnchor constant:10],
        [self.stateLabel.leadingAnchor constraintEqualToAnchor:warn.leadingAnchor],
        [self.startBtn.topAnchor constraintEqualToAnchor:self.stateLabel.bottomAnchor constant:12],
        [self.startBtn.leadingAnchor constraintEqualToAnchor:warn.leadingAnchor],
        [self.startBtn.trailingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:-6],
        [self.startBtn.heightAnchor constraintEqualToConstant:46],
        [self.shareBtn.topAnchor constraintEqualToAnchor:self.startBtn.topAnchor],
        [self.shareBtn.leadingAnchor constraintEqualToAnchor:self.view.centerXAnchor constant:6],
        [self.shareBtn.trailingAnchor constraintEqualToAnchor:warn.trailingAnchor],
        [self.shareBtn.heightAnchor constraintEqualToConstant:46],
        [self.deviceInfoView.topAnchor constraintEqualToAnchor:self.startBtn.bottomAnchor constant:12],
        [self.deviceInfoView.leadingAnchor constraintEqualToAnchor:warn.leadingAnchor],
        [self.deviceInfoView.trailingAnchor constraintEqualToAnchor:warn.trailingAnchor],
        [self.deviceInfoView.heightAnchor constraintEqualToConstant:110],
        [self.earBtnStack.topAnchor constraintEqualToAnchor:self.deviceInfoView.bottomAnchor constant:8],
        [self.earBtnStack.leadingAnchor constraintEqualToAnchor:warn.leadingAnchor],
        [self.earBtnStack.trailingAnchor constraintEqualToAnchor:warn.trailingAnchor],
        [self.logView.topAnchor constraintEqualToAnchor:self.earBtnStack.bottomAnchor constant:8],
        [self.logView.leadingAnchor constraintEqualToAnchor:warn.leadingAnchor],
        [self.logView.trailingAnchor constraintEqualToAnchor:warn.trailingAnchor],
        [self.logView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-12],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadLog)
                                                 name:VGGattLogNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadState)
                                                 name:VGGattStateNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDevices)
                                                 name:VGGattDevicesNotification object:nil];
    [self reloadLog]; [self reloadState]; [self reloadDevices];
}

- (void)startTapped {
    if ([VGGattProbe shared].running) return;
    [[VGGattProbe shared] start];
    [self reloadLog]; [self reloadState]; [self reloadDevices];
}

- (void)resetBaselineTapped {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"清空探测基线？"
                         message:@"清空后，下次探测会重新记录基线；从再下一次探测起才能看到「哪些特征变了」。"
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive
                                       handler:^(UIAlertAction *a) {
        [VGProbeSnapshot resetAll];
        self.deviceInfoView.text = @"基线已清空。重新探测一次即可建立新基线。";
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)shareTapped {
    NSURL *url = [[VGGattProbe shared] exportFile];
    UIActivityViewController *av = [[UIActivityViewController alloc]
        initWithActivityItems:@[url] applicationActivities:nil];
    av.popoverPresentationController.sourceView = self.shareBtn;
    [self presentViewController:av animated:YES completion:nil];
}

- (void)reloadLog {
    NSArray *lines = [[VGGattProbe shared] lines];
    NSString *text = [lines componentsJoinedByString:@"\n"];
    self.logView.text = text;
    if (lines.count > 0) {
        [self.logView scrollRangeToVisible:NSMakeRange(text.length, 0)];
    }
    self.shareBtn.enabled = lines.count > 0;
}

- (void)reloadState {
    self.stateLabel.text = [VGGattProbe shared].stateText;
    self.startBtn.enabled = ![VGGattProbe shared].running;
    self.startBtn.alpha = [VGGattProbe shared].running ? 0.5 : 1;
}

- (void)reloadDevices {
    NSArray<VGProbeDevice *> *ds = [[VGGattProbe shared] devices];
    self.currentDevices = ds;
    // 同步最新映射到档案（探测时创建的对象可能早于用户设定）
    for (VGProbeDevice *d in ds) d.earLabel = [VGEarMap earLabelForKey:d.earKey];
    if (ds.count == 0) { self.deviceInfoView.text = @""; return; }
    NSMutableArray *parts = [NSMutableArray array];
    for (VGProbeDevice *d in ds) [parts addObject:[d summary]];
    self.deviceInfoView.text = [parts componentsJoinedByString:@"\n\n"];
    [self rebuildEarButtons];
}

#pragma mark - 左右耳设定

- (void)rebuildEarButtons {
    for (UIView *v in self.earBtnStack.arrangedSubviews) [v removeFromSuperview];
    for (VGProbeDevice *d in self.currentDevices) {
        UIStackView *row = [UIStackView new];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 8;

        UILabel *title = [UILabel new];
        title.text = [NSString stringWithFormat:@"…%@ · %@", d.peripheralID ?: @"??????",
                      d.earLabel.length ? d.earLabel : @"未设定耳别"];
        title.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        title.textColor = UIColor.whiteColor;
        [row addArrangedSubview:title];

        UIView *spacer = [UIView new];
        [spacer setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
        [spacer setContentCompressionResistancePriority:1 forAxis:UILayoutConstraintAxisHorizontal];
        [row addArrangedSubview:spacer];

        UIButton *lb = [UIButton buttonWithType:UIButtonTypeSystem];
        [lb setTitle:@"设为左耳" forState:UIControlStateNormal];
        [row addArrangedSubview:lb];

        UIButton *rb = [UIButton buttonWithType:UIButtonTypeSystem];
        [rb setTitle:@"设为右耳" forState:UIControlStateNormal];
        [row addArrangedSubview:rb];

        lb.tag = 0; rb.tag = 1;
        objc_setAssociatedObject(lb, @selector(title), d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(rb, @selector(title), d, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [lb addTarget:self action:@selector(earTapped:) forControlEvents:UIControlEventTouchUpInside];
        [rb addTarget:self action:@selector(earTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self styleEarButton:lb selected:[d.earLabel isEqualToString:@"左耳"]];
        [self styleEarButton:rb selected:[d.earLabel isEqualToString:@"右耳"]];
        [lb.heightAnchor constraintEqualToConstant:32].active = YES;
        [rb.heightAnchor constraintEqualToConstant:32].active = YES;

        [self.earBtnStack addArrangedSubview:row];
    }
}

- (void)styleEarButton:(UIButton *)b selected:(BOOL)selected {
    b.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    b.layer.cornerRadius = 10;
    b.layer.borderWidth = 1;
    b.contentEdgeInsets = UIEdgeInsetsMake(4, 12, 4, 12);
    if (selected) {
        b.backgroundColor = [UIColor colorWithRed:0.10 green:0.55 blue:0.50 alpha:1];
        b.layer.borderColor = [UIColor colorWithRed:0.10 green:0.55 blue:0.50 alpha:1].CGColor;
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    } else {
        b.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
        b.layer.borderColor = [UIColor colorWithWhite:0.25 alpha:1].CGColor;
        [b setTitleColor:[UIColor colorWithWhite:0.75 alpha:1] forState:UIControlStateNormal];
    }
}

- (void)earTapped:(UIButton *)sender {
    VGProbeDevice *d = objc_getAssociatedObject(sender, @selector(title));
    if (!d.earKey.length) return;
    NSString *ear = sender.tag == 0 ? @"左耳" : @"右耳";
    // 再次点击已选中的按钮 = 取消设定
    if ([d.earLabel isEqualToString:ear]) {
        [VGEarMap clearForFullUUID:d.earKey];
    } else {
        [VGEarMap setEar:ear forFullUUID:d.earKey];
    }
    [self reloadDevices];
}

@end
