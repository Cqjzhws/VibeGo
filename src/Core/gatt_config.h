//
//  gatt_config.h — Vibe Go（WS Audiology / Signia 平台）实测 GATT 常量
//
//  数据来源：
//    · vg_gatt_20261025_114949.log   只读枚举（服务/特征/初值）
//    · HearingLink.log 2026-10-25 12:07 真机写入实测（音量特征与字节位置）
//

#ifndef HL_GATT_CONFIG_H
#define HL_GATT_CONFIG_H

// ============================================================
//  一、已实测确定的东西（v3.1 内置，装上即生效）
// ============================================================
//
//  麦克风音量特征：1454E9D6-F658-4190-8589-22AA9E3021EB（R/W/WW/N）
//  取值 2 字节，第 1 字节 = 音量档位：
//      拖滑块实测 08 → 03 → 00 → 05 → 08 → 09 （0~9 档）
//      第 2 字节（01/00）与档位无关，同一档位下两种值都出现过 → 是标志位，照抄原值即可
//  写入方式：带响应写（Write With Response）
//  实测行为：写 00 01 → 麦克风静音；写回原值 → 恢复
//
#define HL_DEFAULT_MIC_CHAR_UUID  @"1454E9D6-F658-4190-8589-22AA9E3021EB"

// 音量档位在报文里的字节下标（0 起）。-1 表示未知。
#define HL_DEFAULT_LEVEL_BYTE     0

// 报文最后一字节固定写 0x01。
// 依据：HearingLink(1).log 里第二字节=00 的那只耳，恢复写入 4 次全部「没生效」；
// 第二字节=01 的那只能正常恢复。所以这一位必须 01。
#define HL_FRAME_TRAILER          0x01

// 档位取值：0 = 最低；9 ≈ iOS 滑块 60（实测设备档位能到 0x0A，0~15 区间）
#define HL_DEFAULT_MUTE_LEVEL     0
#define HL_DEFAULT_RESTORE_LEVEL  9

// 档位满量程（百分比换算用）：60% -> round(0.60*15) = 9
#define HL_LEVEL_MAX              15

// 恢复音量默认值：左耳 60%，右耳 0（用户 2026-10-25 要求：右耳麦克风恢复时为 0）
// 可用 HLRestorePercent（全局）/ HLRestorePercentLeft / HLRestorePercentRight 覆盖
// 暂停到恢复之间的等待（监控层防抖）
// 注入版给 jetAudio 用 1.2s（挡拖进度条/切歌）；独立 App 里探针自己已经防抖过，
// 再等 1.2s 就变成「双重防抖」，实测恢复要 4~5 秒，所以压到 0.2s
#ifdef HL_STANDALONE_APP
#define HL_DEFAULT_RESTORE_DELAY          0.0
#else
#define HL_DEFAULT_RESTORE_DELAY          1.2
#endif

#define HL_DEFAULT_RESTORE_PERCENT        60
#define HL_DEFAULT_RESTORE_PERCENT_LEFT   60
#define HL_DEFAULT_RESTORE_PERCENT_RIGHT  0

// ---- 右耳锁定（看门狗）----
// 现象：右耳麦克风会自己跳回打开（设备侧在音频流结束时恢复，或 iOS 重下发系统音量）。
// 做法：每 HLLockInterval 秒读一次被锁耳朵的档位，不是目标值就立刻写回去；
//      麦克风特征有 Notify 属性，设备一变动就能收到通知，比轮询更快。
#define HL_DEFAULT_LOCK_ENABLED   1        // HLLockRightEar
#define HL_DEFAULT_LOCK_LEVEL     0        // HLLockEarLevel：锁到最低（麦克风关）
#define HL_DEFAULT_LOCK_INTERVAL  3.0      // HLLockInterval：秒
#define HL_DEFAULT_LOCK_EARS      @"右耳"  // HLLockEars：逗号分隔，可写 "右耳" 或 "右耳,左耳"
#define HL_DEFAULT_NOTIFY         1        // HLNotify：订阅麦克风特征通知

// ---- 播放中保持档位（0.6.5 新增）----
// 2026-10-26 实测结论：iPhone 侧边音量键会直接改写 1454E9D6（麦克风档位），
// 而且改的是同一只耳的同一个特征——我们播放时压到 0，用户一按音量键就被拉回去，
// 这就是「偶尔播放中左耳没压住」的真正原因（不是断连、不是时序）。
// 做法：只要处于「播放中/通话中」状态，就把所有已连接耳的档位按住不放，
//      被外力改写后 1 秒内按回目标值；暂停后立刻停手（否则恢复不回来）。
#define HL_DEFAULT_HOLD_WHILE_PLAYING 1    // HLHoldWhilePlaying：播放中持续保持
#define HL_HOLD_INTERVAL              1.0  // 保持期间看门狗间隔（秒），比锁定间隔快

// ---- 全局音频探测（独立 App 用）----
// 判定「别的 App 在放声音」：AVAudioSession.isOtherAudioPlaying + secondaryAudioShouldBeSilencedHint
#define HL_DEFAULT_AUDIO_ATTACK    0.4    // 声音持续多久才算「在放」，挡键盘声/提示音
#define HL_DEFAULT_AUDIO_RELEASE   0.4    // 安静多久才恢复；越小越快，抖音滑动间隙大的话调回 1.0~1.5
#define HL_DEFAULT_AUDIO_USE_HINT  1      // 是否把 silencedHint 也算进判定
#define HL_DEFAULT_AUDIO_SESSION   1      // 1=激活一个 ambient+mix 空会话（让 hint 更可靠）
// 用哪个信号做判定：0=任一为真(OR) 1=只看「别家在放」 2=只看「提示」
// 背景：切到别的 App 后环境声不回来，怀疑某个信号卡在 1 不回落，留这个开关用来定位
#define HL_DEFAULT_AUDIO_SIGNAL    0

// ---- 通话模式（iOS 打电话时的单独一套档位）----
// 通话时麦克风全关会听不见自己说话，所以左耳留一点环境声，右耳仍然关死。
#define HL_DEFAULT_CALL_ENABLE       1     // HLCallModeEnable
#define HL_DEFAULT_CALL_LEFT         50    // HLCallMutePercentLeft：通话时左耳档位（百分比）50% -> 档位 8
#define HL_DEFAULT_CALL_RIGHT        0     // HLCallMutePercentRight：通话时右耳档位

// 左右耳识别（2026-10-25 枚举日志实测，配对 ID 跨多次抓包稳定）
#define HL_EAR_ID_CHAR_UUID   @"C97D21D3-D79D-4DF8-9230-BB33FA805F4E"  // 配对 ID
#define HL_EAR_FLAG_CHAR_UUID @"8D17AC2F-1D54-4742-A49A-EF4B20784EB3"  // 01=右 00=左
#define HL_EAR_PAIR_LEFT      @"2FCDA8"
#define HL_EAR_PAIR_RIGHT     @"2FF351"
// ============================================================

// 私有服务 UUID（扫描过滤用；命中任一即认为是目标设备）
#define HL_VENDOR_SERVICE_UUIDS  @[ @"7D74F4BD-C74A-4431-862C-CCE884371592", \
                                    @"56772EAF-2153-4F74-ACF3-4368D99FBF5A", \
                                    @"0A23AE62-C4C2-43D1-87B1-E8C83839A063", \
                                    @"C8F777D0-21B2-45B8-87F8-BD49A13EFF49", \
                                    @"C8F7A831-21B2-45B8-87F8-BD49A13EFF49", \
                                    @"D1D4DC2A-215F-44D2-B44C-0F4DE3C91AF2" ]

// 设备名关键字（广播名 / CBPeripheral.name 命中任一即认）
// "Vibe" 是官方广播名；"王的设备" 是用户在 iOS 里改的名字
#define HL_DEVICE_NAME_KEYS      @[ @"vibe", @"王的设备" ]

// 可写「配置特征」列表：学习模式的候选池（换设备时靠它自己认）
#define HL_CONFIG_CHAR_UUIDS     @[ @"F3F594F9-E210-48F3-85E2-4B0CF235A9D3", \
                                    @"6AC46200-24EA-46D8-A136-81133C65840A", \
                                    @"A391C6F1-20BB-495A-ABBF-2017098FBC61", \
                                    @"A28B6BE1-2FA4-42F8-AEB2-B15A1DBD837A", \
                                    @"9C12A3DB-9CE8-4865-A217-D394B3BC9311", \
                                    @"4656D3AC-C2DF-4096-96E7-713580B69CCD", \
                                    @"68BFA64E-3209-4172-B117-F7EAFCE17414", \
                                    @"535442F7-0FF7-4FEC-9780-742F3EB00EDA", \
                                    @"1454E9D6-F658-4190-8589-22AA9E3021EB", \
                                    @"9215A295-B813-483F-9F85-B700D0B7BC75", \
                                    @"50632720-4C0F-4BC4-960A-2404BDFDFBCA", \
                                    @"51939BB6-A635-4B1E-903B-76CD9DFF3FAC", \
                                    @"EBEE6F69-70B6-4BB9-B13B-9BA84953C233", \
                                    @"8B820C6D-0F0C-40BB-B422-3770FA72A864" ]

// 已知会自己跳变的状态/电平特征——学习时排除，避免误判成音量
// ADC3023D / 42E940EF：实测 3C 05 / 2D 05 之类来回跳，像实时输入电平表
// C8F7xxxx：厂商流通道，会推音频流，别乱读
#define HL_NOISY_CHAR_UUIDS      @[ @"ADC3023D-BFD2-43FD-86F6-7AE05A619092", \
                                    @"42E940EF-98C8-4CCD-A557-30425295AF89", \
                                    @"C8F7FAC0-21B2-45B8-87F8-BD49A13EFF49", \
                                    @"C8F714D6-21B2-45B8-87F8-BD49A13EFF49", \
                                    @"C8F79C9A-21B2-45B8-87F8-BD49A13EFF49", \
                                    @"C8F73DC3-21B2-45B8-87F8-BD49A13EFF49", \
                                    @"C8F7A8E4-21B2-45B8-87F8-BD49A13EFF49", \
                                    @"C8F7A68A-21B2-45B8-87F8-BD49A13EFF49", \
                                    @"C8F723DA-21B2-45B8-87F8-BD49A13EFF49", \
                                    @"C8F7690C-21B2-45B8-87F8-BD49A13EFF49", \
                                    @"2A19" ]

// 最多同时连几只（左右各一只）
#define HL_MAX_PERIPHERALS       2

// 学习采样间隔（秒）；学完后自动降到 5 倍间隔（10s）
#define HL_LEARN_INTERVAL        2.0

#endif // HL_GATT_CONFIG_H
