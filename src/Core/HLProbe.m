//
//  HLProbe.m — 全局音频/通话探测 + 启动装配
//
//  把 GlobalHA 那套「判断别的 App 在不在放声音」搬进 VibeGo 助手进程，
//  GATT 部分完全复用 HearingLink.m（同一份源码，注入版 / 独立版 / 本 App 三处一致）。
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <objc/message.h>

// CallKit runtime load — 避免 clang 链接到 __OBJC_PROTOCOL_$_CXCallObserverDelegate
// 只用 @class 前向声明，HLCallProbe2_RT 不带任何 protocol
@class CXCallObserver, CXCall;

@interface HLCallProbe2_RT : NSObject
@property (nonatomic, copy) void (^onChanged)(void);
@end

#import "gatt_config.h"

extern void HLSetPlayingProvider(BOOL (^p)(void));
extern void HLSetLogSink(void (^sink)(NSString *line));
extern void HLExternalLog(NSString *fmt, ...);
extern void HLSetCallMode(BOOL on);
extern void HLReapplyNow(void);
extern NSString *HLStatusText(void);

static id APref(NSString *key, id fallback) {
    @try {
        NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
                          stringByAppendingPathComponent:@"hearinglink.plist"];
        NSDictionary *f = [NSDictionary dictionaryWithContentsOfFile:path];
        if (f[key]) return f[key];
    } @catch (NSException *e) {}
    id v = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    return v ?: fallback;
}

#pragma mark - 日志环形缓冲（给界面看）

static NSMutableArray<NSString *> *HL_ring = nil;

static void HLRingAppend(NSString *line) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ HL_ring = [NSMutableArray array]; });
    @synchronized (HL_ring) {
        [HL_ring addObject:[line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]]];
        while (HL_ring.count > 200) [HL_ring removeObjectAtIndex:0];
    }
}

NSArray<NSString *> *HLRecentLines(void) {
    return HL_ring ? [HL_ring copy] : @[];
}
#pragma mark - 音频探测

@interface HLAudioProbe2 : NSObject
+ (instancetype)shared;
- (void)start;
@property (nonatomic, readonly) BOOL playing;
@property (nonatomic, readonly) BOOL rawOther;
@property (nonatomic, readonly) BOOL rawHint;
@end

@implementation HLAudioProbe2 {
    NSTimer *_timer;
    BOOL _playing;
    BOOL _lastOther, _lastHint;
    BOOL _hasLast;
    NSTimeInterval _audioSince;
    NSTimeInterval _silenceSince;
    NSTimeInterval _rawSince;
    NSTimeInterval _lastBeat;
    NSTimeInterval _lastReactivate;
    double _reactivateGap;          // 当前重试间隔（失败就翻倍到 120s）
    NSString *_lastActivateErr;     // 上次失败原因，重复的不再刷日志
}

+ (instancetype)shared {
    static HLAudioProbe2 *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [HLAudioProbe2 new]; });
    return s;
}

- (BOOL)playing  { return _playing; }
- (BOOL)rawOther { return _lastOther; }
- (BOOL)rawHint  { return _lastHint; }

- (void)start {
    NSInteger mode = [APref(@"HLAudioSessionMode", @(HL_DEFAULT_AUDIO_SESSION)) integerValue];
    AVAudioSession *s = [AVAudioSession sharedInstance];
    if (mode == 1) {
        NSError *e = nil;
        [s setCategory:AVAudioSessionCategoryAmbient
                  mode:AVAudioSessionModeDefault
               options:AVAudioSessionCategoryOptionMixWithOthers
                 error:&e];
        if (e) HLExternalLog(@"[音频] 设类别失败：%@", e.localizedDescription);
        e = nil;
        [s setActive:YES error:&e];
        HLExternalLog(@"[音频] 空会话已激活（ambient+mix）%@",
                      e ? [@" 失败：" stringByAppendingString:e.localizedDescription] : @"");
    }

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(onHint:)
               name:AVAudioSessionSilenceSecondaryAudioHintNotification object:nil];
    [nc addObserver:self selector:@selector(onInterruption:)
               name:AVAudioSessionInterruptionNotification object:nil];

    _timer = [NSTimer scheduledTimerWithTimeInterval:0.15 target:self
                                            selector:@selector(tick) userInfo:nil repeats:YES];
    [self tick];
}

- (void)onHint:(NSNotification *)n {
    NSUInteger t = [n.userInfo[AVAudioSessionSilenceSecondaryAudioHintTypeKey] unsignedIntegerValue];
    HLExternalLog(@"[音频] 静音提示通知 type=%lu", (unsigned long)t);
    dispatch_async(dispatch_get_main_queue(), ^{ [self tick]; });
}

- (void)onInterruption:(NSNotification *)n {
    NSUInteger t = [n.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    HLExternalLog(@"[音频] 中断通知 type=%lu", (unsigned long)t);
    dispatch_async(dispatch_get_main_queue(), ^{ [self tick]; });
}

- (void)tick {
    @try {
        AVAudioSession *s = [AVAudioSession sharedInstance];
        BOOL other = s.isOtherAudioPlaying;
        BOOL hint  = s.secondaryAudioShouldBeSilencedHint;
        BOOL useHint = [APref(@"HLAudioUseHint", @(HL_DEFAULT_AUDIO_USE_HINT)) boolValue];
        NSInteger sigMode = [APref(@"HLAudioSignalMode", @(HL_DEFAULT_AUDIO_SIGNAL)) integerValue];

        BOOL raw;
        if (sigMode == 1)      raw = other;
        else if (sigMode == 2) raw = hint;
        else                   raw = other || (useHint && hint);

        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];

        // 后台没有音频播放权时 setActive:YES 必然失败（"Session activation failed"）。
        // 这不是错误，只是拿不到会话；判定靠 isOtherAudioPlaying/hint，不需要会话活跃。
        // 所以：失败就退避（15s→30s→60s→120s），同样的原因只报一次，别刷日志。
        if (_reactivateGap <= 0) _reactivateGap = 15.0;
        if (now - _lastReactivate >= _reactivateGap) {
            _lastReactivate = now;
            NSError *e = nil;
            if ([s setActive:YES error:&e]) {
                if (_lastActivateErr) HLExternalLog(@"[音频] 会话已恢复激活");
                _lastActivateErr = nil;
                _reactivateGap = 15.0;
            } else {
                NSString *msg = e.localizedDescription ?: @"未知";
                if (![_lastActivateErr isEqualToString:msg]) {
                    HLExternalLog(@"[音频] 会话激活失败（后台常见，不影响判定）：%@", msg);
                    _lastActivateErr = msg;
                }
                _reactivateGap = MIN(_reactivateGap * 2.0, 120.0);
            }
        }

        if (!_hasLast || other != _lastOther || hint != _lastHint) {
            double held = _rawSince > 0 ? (now - _rawSince) : 0;
            _hasLast = YES;
            _lastOther = other;
            _lastHint  = hint;
            if (_rawSince > 0) HLExternalLog(@"[音频] 上一状态维持了 %.1fs", held);
            _rawSince = now;
            _lastBeat = now;
            HLExternalLog(@"[音频] 别家在放=%d 提示=%d → 原始判定=%d", other, hint, raw);
        }

        if (raw && now - _lastBeat >= 20.0) {
            _lastBeat = now;
            HLExternalLog(@"[音频] 仍在放，已持续 %.0fs", now - _rawSince);
        }

        double attack  = [APref(@"HLAudioAttack",  @(HL_DEFAULT_AUDIO_ATTACK))  doubleValue];
        double release = [APref(@"HLAudioRelease", @(HL_DEFAULT_AUDIO_RELEASE)) doubleValue];

        if (raw) {
            if (_audioSince <= 0) _audioSince = now;
            BOOL real = (now - _audioSince) >= attack;
            if (real) {
                _silenceSince = 0;
                if (!_playing) {
                    _playing = YES;
                    HLExternalLog(@"[音频] 判定 → 有声音，压麦克风");
                }
            }
        } else {
            _audioSince = 0;
            if (_playing) {
                if (_silenceSince <= 0) _silenceSince = now;
                else if (now - _silenceSince >= release) {
                    _playing = NO; _silenceSince = 0;
                    HLExternalLog(@"[音频] 判定 → 安静 %.1fs，恢复麦克风", release);
                }
            }
        }
    } @catch (NSException *e) {
        HLExternalLog(@"[音频] tick 异常：%@", e.reason);
    }
}

@end

#pragma mark - 后台保活（音频断言兜底）

//  为什么需要：
//    主保活是 Info.plist 的 bluetooth-central + 一直握着 BLE 连接，实测够用。
//    但系统在某些情况下（内存压力、长时间不用）仍可能回收进程。这时补一条
//    「正在播放音频」的断言，让系统把它当音乐类 App 看待，几乎不会被杀。
//
//  为什么默认关闭：
//    它会占用本 App 的音频会话（category 变成 Playback），可能扰动
//    isOtherAudioPlaying / silencedHint 的取值。功能优先，所以做成开关，
//    只有确实遇到「后台被杀」时才打开。
//
//  怎么做到不打扰别人：
//    Playback + MixWithOthers，音量 0.01，播放 ±1 LSB 的极低幅噪声
//    （纯 0 有些系统会判定为「静音流」而不产生断言）。

@interface HLKeepAlive : NSObject
+ (instancetype)shared;
- (BOOL)enabled;
- (void)setEnabled:(BOOL)on;
- (void)start;
@property (nonatomic, readonly) BOOL running;
@end

@implementation HLKeepAlive {
    AVAudioPlayer *_player;
    BOOL _running;
}

+ (instancetype)shared {
    static HLKeepAlive *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [HLKeepAlive new]; });
    return s;
}

- (BOOL)running { return _running; }

- (BOOL)enabled {
    return [APref(@"HLKeepAliveAudio", @0) boolValue];
}

- (void)setEnabled:(BOOL)on {
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"HLKeepAliveAudio"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    if (on) [self start];
    else    [self stop];
}

// 22050Hz / 单声道 / 16bit / 1 秒，±1 LSB 噪声
static NSData *HLLowNoiseWav(void) {
    UInt32 sr = 22050, ch = 1, bps = 16;
    UInt32 dataLen = sr * ch * (bps / 8);
    NSMutableData *d = [NSMutableData data];
    [d appendBytes:"RIFF" length:4];
    UInt32 riffSz = 36 + dataLen;  [d appendBytes:&riffSz length:4];
    [d appendBytes:"WAVEfmt " length:8];
    UInt32 fmtSz = 16;             [d appendBytes:&fmtSz length:4];
    UInt16 fmt = 1;                [d appendBytes:&fmt length:2];
    UInt16 nc = (UInt16)ch;        [d appendBytes:&nc length:2];
    [d appendBytes:&sr length:4];
    UInt32 byteRate = sr * ch * (bps / 8); [d appendBytes:&byteRate length:4];
    UInt16 align = (UInt16)(ch * bps / 8); [d appendBytes:&align length:2];
    UInt16 bits = (UInt16)bps;     [d appendBytes:&bits length:2];
    [d appendBytes:"data" length:4];
    [d appendBytes:&dataLen length:4];

    NSMutableData *pcm = [NSMutableData dataWithLength:dataLen];
    int16_t *p = pcm.mutableBytes;
    for (NSUInteger i = 0; i < dataLen / 2; i++) p[i] = (i % 2) ? 1 : -1;
    [d appendData:pcm];
    return d;
}

- (void)start {
    if (_running) return;
    if (![self enabled]) { HLExternalLog(@"[保活] 音频保活关闭（HLKeepAliveAudio=0）"); return; }
    @try {
        AVAudioSession *s = [AVAudioSession sharedInstance];
        NSError *e = nil;
        [s setCategory:AVAudioSessionCategoryPlayback
                  mode:AVAudioSessionModeDefault
               options:AVAudioSessionCategoryOptionMixWithOthers
                 error:&e];
        if (e) HLExternalLog(@"[保活] 设类别失败：%@", e.localizedDescription);
        e = nil;
        [s setActive:YES error:&e];
        if (e) HLExternalLog(@"[保活] 激活失败：%@", e.localizedDescription);

        _player = [[AVAudioPlayer alloc] initWithData:HLLowNoiseWav() error:&e];
        if (!_player) {
            HLExternalLog(@"[保活] 播放器创建失败：%@", e.localizedDescription ?: @"未知");
            return;
        }
        _player.numberOfLoops = -1;
        _player.volume = 0.01f;
        _player.meteringEnabled = NO;
        BOOL ok = [_player play];
        _running = ok;
        HLExternalLog(@"[保活] 音频断言%@（Playback+mix，音量 1%%）", ok ? @"已开启" : @"开启失败");
    } @catch (NSException *ex) {
        HLExternalLog(@"[保活] 异常：%@", ex.reason);
    }
}

- (void)stop {
    if (!_running && !_player) return;
    @try {
        [_player stop];
        _player = nil;
        _running = NO;
        HLExternalLog(@"[保活] 音频断言已关闭");
    } @catch (NSException *ex) {}
}

@end

BOOL HLKeepAliveRunning(void) { return [HLKeepAlive shared].running; }
void HLSetKeepAlive(BOOL on)  { [[HLKeepAlive shared] setEnabled:on]; }
BOOL HLKeepAliveEnabled(void) { return [[HLKeepAlive shared] enabled]; }

#pragma mark - 通话探测

typedef BOOL (*AVSCGetVolNameFn)(id, SEL, float *, NSString **);

static id HL_AVSystemController(void) {
    static id inst = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience", RTLD_NOW);
        if (!h) { HLExternalLog(@"[通话] MediaExperience 打不开"); return; }
        Class c = NSClassFromString(@"AVSystemController");
        if (!c) { HLExternalLog(@"[通话] 没有 AVSystemController 类"); return; }
        SEL sel = NSSelectorFromString(@"sharedAVSystemController");
        if (![c respondsToSelector:sel]) { HLExternalLog(@"[通话] 没有 sharedAVSystemController"); return; }
        @try {
            inst = ((id (*)(id, SEL))objc_msgSend)(c, sel);
            HLExternalLog(@"[通话] AVSystemController 已就绪");
        } @catch (NSException *e) {
            HLExternalLog(@"[通话] 取实例失败：%@", e.reason);
        }
    });
    return inst;
}

static NSString *HL_ActiveCategory(void) {
    id inst = HL_AVSystemController();
    if (!inst) return nil;
    SEL sel = NSSelectorFromString(@"getActiveCategoryVolume:andName:");
    if (![inst respondsToSelector:sel]) return nil;
    float vol = 0.f; NSString *name = nil;
    BOOL ok = NO;
    @try { ok = ((AVSCGetVolNameFn)objc_msgSend)(inst, sel, &vol, &name); } @catch (NSException *e) { return nil; }
    return ok ? name : nil;
}

@interface HLCallProbe2 : NSObject
+ (instancetype)shared;
- (void)start;
@property (nonatomic, readonly) BOOL inCall;
@property (nonatomic, readonly) BOOL ctCall;
@property (nonatomic, readonly, copy) NSString *category;
@end

// MARK: - CXCallObserver replacement
// CTCallCenter 在 iOS 10 就 deprecated，后台 App 拿不到 currentCalls。
// CXCallObserver 是 CallKit 框架提供的后台可用替代——不需要用户权限、不需要 entilement。

// Runtime CXCallObserver — 避免 zig clang 找不到 CallKit.framework Headers
@interface HLCallProbe2 ()
@property (nonatomic, strong) id observer;          // CXCallObserver, runtime 加载
@property (nonatomic, strong) id rtDelegate;         // HLCallProbe2_RT 实例
@end

@implementation HLCallProbe2 {
    NSTimer *_timer;
    BOOL _inCall;
    BOOL _lastCT;
    BOOL _lastSessionCall;
    NSString *_lastCat;
    BOOL _hasLast;
}

+ (instancetype)shared {
    static HLCallProbe2 *s; static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [HLCallProbe2 new]; });
    return s;
}

- (BOOL)inCall   { return _inCall; }
- (BOOL)ctCall   { return _lastCT; }
- (NSString *)category { return _lastCat ?: @"-"; }

// runtime: [obj setValue:val forKey:@"delegate"] 或 objc_setAssociatedObject
static void HL_SetDelegate(id obj, id delegate) {
    @try {
        [obj setValue:delegate forKey:@"delegate"];
    } @catch (NSException *e) {
        // 有些版本 CallKit delegate 属性是 readonly fallback 到 objc runtime
    }
}

static NSArray *HL_GetCalls(id observer) {
    @try {
        return ((NSArray *(*)(id, SEL))objc_msgSend)(observer, NSSelectorFromString(@"calls"));
    } @catch (NSException *e) { return nil; }
}

- (void)start {
    if (![APref(@"HLCallModeEnable", @(HL_DEFAULT_CALL_ENABLE)) boolValue]) {
        HLExternalLog(@"[通话] 通话模式已关闭");
        return;
    }
    Class obsCls = NSClassFromString(@"CXCallObserver");
    if (!obsCls) {
        HLExternalLog(@"[通话] 找不到 CXCallObserver 类（CallKit.framework 未加载）");
    } else {
        _observer = [obsCls new];
        // HLCallProbe2_RT 实现 CXCallObserverDelegate，runtime 设置 delegate
        __weak HLCallProbe2 *weakSelf = self;
        _rtDelegate = [HLCallProbe2_RT new];
        ((HLCallProbe2_RT *)_rtDelegate).onChanged = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf tick];
            });
        };
        HL_SetDelegate(_observer, _rtDelegate);
        HLExternalLog(@"[通话] CXCallObserver 已注册（runtime, 替代 CTCallCenter）");
    }

    _timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self
                                            selector:@selector(tick) userInfo:nil repeats:YES];
    [self tick];
}

// MARK: 状态判定

- (void)tick {
    NSString *cat = HL_ActiveCategory();

    // 从 CXCallObserver runtime 拿活跃通话列表
    BOOL ct = NO;
    if (_observer) {
        NSArray *calls = HL_GetCalls(_observer);
        for (id c in calls) {
            BOOL ended = NO;
            @try { ended = ((BOOL (*)(id, SEL))objc_msgSend)(c, NSSelectorFromString(@"hasEnded")); } @catch (NSException *e) {}
            if (!ended) { ct = YES; break; }
        }
    }

    // 也用 AVAudioSession.mode 兜底：VoiceChat/VideoChat 都是通话中
    AVAudioSession *sess = [AVAudioSession sharedInstance];
    NSString *mode = sess.mode ?: @"";
    BOOL sessionCall = ([mode isEqualToString:AVAudioSessionModeVoiceChat] ||
                        [mode isEqualToString:AVAudioSessionModeVideoChat]);

    BOOL isCall = ct || sessionCall || (cat && [cat rangeOfString:@"PhoneCall"].location != NSNotFound);

    if (!_hasLast || ct != _lastCT || sessionCall != _lastSessionCall ||
        !((cat == _lastCat) || (cat && _lastCat && [cat isEqualToString:_lastCat]))) {
        _hasLast = YES;
        _lastCT = ct;
        _lastSessionCall = sessionCall;
        _lastCat = cat;
        HLExternalLog(@"[通话] CX=%d session=%d category=%@ → 判定=%d", ct, sessionCall, cat ?: @"?", isCall);
    }

    if (isCall != _inCall) {
        _inCall = isCall;
        HLExternalLog(@"[通话] %@", isCall ? @"进入通话（左耳按通话档位）" : @"通话结束");
        HLSetCallMode(isCall);
        HLReapplyNow();
    }
}

@end

// MARK: HLCallProbe2_RT — CXCallObserverDelegate runtime impl
@implementation HLCallProbe2_RT
- (void)callObserver:(id)callObserver callChanged:(id)call {
    if (self.onChanged) self.onChanged();
}
@end

#pragma mark - 对外状态

BOOL HLMediaPlaying(void) { return [HLAudioProbe2 shared].playing; }
BOOL HLInCall(void)       { return [HLCallProbe2 shared].inCall; }
NSString *HLCallCategory(void) { return [HLCallProbe2 shared].category; }

#pragma mark - 装配

__attribute__((constructor))
static void HLProbeBootstrap(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        HLSetLogSink(^(NSString *line) { HLRingAppend(line); });

        HLAudioProbe2 *probe = [HLAudioProbe2 shared];
        HLSetPlayingProvider(^BOOL{ return probe.playing || [HLCallProbe2 shared].inCall; });
        [probe start];
        [[HLCallProbe2 shared] start];
        [[HLKeepAlive shared] start];

        // 版本号从 Info.plist 读，别再硬编码（0.6.5 就因为这个，日志里一直显示 0.6.4）
        NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        HLExternalLog(@"VibeGo 助手 %@：麦克风联动 + 实验室（探测/GATT/保活均内置）", ver ?: @"?");
    });
}
