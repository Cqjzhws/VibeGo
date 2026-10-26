#import "VGDiagnoseVC.h"
#import "VGStabilityLog.h"
#import "VGMonitor.h"
#import "VGHearingDevice.h"

@interface VGDiagnoseVC ()
@property (nonatomic, strong) UILabel *statsLabel;
@property (nonatomic, strong) UITextView *eventsView;
@end

@implementation VGDiagnoseVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"稳定性诊断";
    self.view.backgroundColor = [UIColor colorWithWhite:0.06 alpha:1];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                      target:self action:@selector(shareCsv)];

    self.statsLabel = [UILabel new];
    self.statsLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    self.statsLabel.textColor = UIColor.whiteColor;
    self.statsLabel.numberOfLines = 0;
    self.statsLabel.backgroundColor = [UIColor colorWithRed:0.10 green:0.16 blue:0.16 alpha:1];
    self.statsLabel.layer.cornerRadius = 12;
    self.statsLabel.layer.masksToBounds = YES;
    self.statsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statsLabel];

    self.eventsView = [UITextView new];
    self.eventsView.editable = NO;
    self.eventsView.font = [UIFont fontWithName:@"Menlo-Regular" size:11];
    self.eventsView.textColor = [UIColor colorWithRed:0.75 green:0.95 blue:0.85 alpha:1];
    self.eventsView.backgroundColor = [UIColor blackColor];
    self.eventsView.layer.cornerRadius = 12;
    self.eventsView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.eventsView];

    [NSLayoutConstraint activateConstraints:@[
        [self.statsLabel.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:14],
        [self.statsLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [self.statsLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [self.eventsView.topAnchor constraintEqualToAnchor:self.statsLabel.bottomAnchor constant:12],
        [self.eventsView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [self.eventsView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [self.eventsView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-14],
    ]];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reload)
                                                 name:VGStatusDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    self.statsLabel.text =
        [NSString stringWithFormat:@"  当前：%@\n\n%@",
            [VGMonitor shared].latest.summary ?: @"-",
            [VGStabilityLog.shared statisticsText]];

    NSDateFormatter *f = [NSDateFormatter new];
    f.dateFormat = @"MM-dd HH:mm:ss";
    NSMutableArray *lines = [NSMutableArray array];
    for (NSDictionary *e in [VGStabilityLog.shared events]) {
        NSDate *ts = [NSDate dateWithTimeIntervalSince1970:[e[@"ts"] doubleValue]];
        NSString *mark = [e[@"state"] isEqual:@"connected"] ? @"🟢" : @"🔴";
        [lines addObject:[NSString stringWithFormat:@"%@ %@ %@",
                          [f stringFromDate:ts], mark, e[@"summary"]]];
    }
    self.eventsView.text = lines.count
        ? [@"连接事件时间线（最近在上）\n\n" stringByAppendingString:[lines componentsJoinedByString:@"\n"]]
        : @"暂无连接事件。打开本应用保持运行，状态变化会被记录。";
}

- (void)shareCsv {
    // 先把当前状态再采样一次，保证导出最新
    [[VGMonitor shared] refresh];
    NSURL *url = [VGStabilityLog.shared exportFile];
    UIActivityViewController *a =
        [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    a.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:a animated:YES completion:nil];
}

@end
