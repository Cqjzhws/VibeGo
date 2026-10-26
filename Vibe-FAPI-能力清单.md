# Vibe 助听器 FAPI 能力清单
从 `Vibe App 2.7.0`（`com.hicontrol.rta`，.NET MAUI）的 `WSA.Foundation.FapiAccessLayer.dll` 提取。
格式为 `Feature 版本 - 参数名`，共 55 个 Feature、535 个参数名。

> 这些都是**设备固件里真实存在的参数**，但只能通过 FAPI 帧读写，> 不能直接写 BLE 特征。见文末「为什么不能直接用」。

## 音质 / 均衡（EQ）

**ChannelGain**（6）
```
  BroadbandGain
  BroadbandGainLimit
  GainLimitOffsets
  NumberOfActiveGainChannels
  NumberOfLogicalGainChannels
  PhysicalGains
```

**ClassBasedFrequencyShaping**（4）
```
  CbfsClassFreezeStatus
  CbfsGainOffsetCar
  CbfsGainOffsetMusic
  ConfiguredClassMapping
```

**DynamicRange**（1）
```
  DynamicRangeShiftInputCompressionForTestDisable
```

**FrequencyCompression**（1）
```
  FcoCutOffFrequency
```

**Compression**（11）
```
  AgcCompressionConcept
  AlmCompressionConfiguration
  CompressionKneepoint1
  CompressionKneepoint1ByChannel
  CompressionKneepoint2
  CompressionKneepoint2ByChannel
  CompressionKneepointOffset
  CompressionType
  InsituOffsetMode
  MaxCompressionRatio
  MaximumAllowedCompressionRatio
```

**MaximumPowerOutput**（26）
```
  AgcoLowfreqFrequency
  AgcoLowfreqThreshold
  AgcoReserve
  BroadbandChannelMpoOffset
  BroadbandMpo
  BroadbandMpoMode
  BroadbandMpoThreshold
  ChannelMpo
  ChannelMpoLowfreqAttenuationOpenSet1
  ChannelMpoLowfreqAttenuationOpenSet2
  ChannelMpoLowfreqAttenuationOpenSet3
  ChannelMpoLowfreqAttenuationOpenSet4
  ChannelMpoLowfreqAttenuationSet1
  ChannelMpoLowfreqAttenuationSet2
  ChannelMpoLowfreqAttenuationSet3
  ChannelMpoLowfreqAttenuationSet4
  ChannelMpoOffset
  ChannelMpoThresholds
  ConfiguredAgcoReserve
  LowFrequencySplitbandFilterFrequency
  LowFrequencyThreshold
  MaximumPowerOutputOffset
  MpoThresholdsForSafetyLimiter
  MpoType
  OppFilterOrder
  PhysicalChannelMpoThresholds
```

**SafetyLimiter**（9）
```
  ConfiguredHlaSafetyLimiterThresholdsForConnexxUseCase
  GainTimeConstantAttack
  GainTimeConstantRelease
  HlaSafetyLimiterThresholdsForConnexxUseCase
  LevelTimeConstantAttack
  LevelTimeConstantRelease
  ReceiverTestModeEnabled
  SafetyLimiterEnabled
  SafetyLimiterThresholds
```

**AcousticCoupling**（12）
```
  AcpEarMold
  AcpEarhook
  AcpEarhookToTableMapping
  AcpHorn
  AcpLifeTubeLength
  AcpVent
  AcpVentCategory
  AovVentType
  EceFmax
  EceFmin
  EffectiveCouplingEstimationFmax
  EffectiveCouplingEstimationFmin
```

**OpenVentOptimization**（3）
```
  CurrentVentDtgRange
  NumberOfDeactivatedChannelsForOpenVentOpt
  NumberOfLowGainChannels
```

## 降噪 / 方向性

**NoiseReduction**（18）
```
  FancyBroadbandStrength
  FineStrength
  SpassStrength
  SpeechNoiseManagementBroadbandStrength
  SpeechNoiseManagementMode
  SpeechNoiseManagementMultichannelModeAllowed
  SpeechNoiseManagementMultichannelModeAvailable
  SpeechNoiseManagementMultichannelStrength
  VadAntiSetBand01
  VadAntiSetBand02
  VadAntiSetBand03
  VadAntiSetBand04
  VadBroadbandStrength
  VadMultichannelStrength
  VadSetBand01
  VadSetBand02
  VadSetBand03
  VadSetBand04
```

**RegionBeam**（5）
```
  RegbSceneAnalysisNoiseInd
  RegbSceneAnalysisProxiFlag
  RegionBeamMode
  RegionBeamSceneAnalysisMode
  RegionBeamStrength
```

**NaturalFocus**（1）
```
  NaturalFocusStrengthPreset
```

**MicMode**（23）
```
  AmixerOpenOptimizer
  AmixerSpatialomni
  AmixerStatDir
  BwncNotAvailable
  DirectionalMicFrequencyCorrectionOffset
  DirectionalMicManualOutputSignalSelection
  DirectionalMicMicDistanceIndex
  DirectionalMicMicMatchingThreshold
  DirectionalMicReplaceOmniDirMicWithSpatialOmniDirMic
  DirectionalMicSpatialOnmiAParameter
  DirectionalMicStaticDirectivityAParameter
  FeedbackPathMicMode
  FittingMicMode
  FmmLimitLower
  FmmLimitUpper
  FogFrequencyShapingIndex
  InputModeCurveMapping
  MatchingRefFrequency
  MicBinauralDistanceIndex
  MicDelayMode
  MicFrequencyCompensationOffset
  MicMode
  MicrophoneDistanceIndex
```

**EWindScreen**（2）
```
  EWindScreenStrength
  WncSet
```

**FeedbackCancellation**（2）
```
  FbcNumDelay
  FbcStrength
```

**SensorNoiseReduction**（2）
```
  AuxInrMaxAtt
  MnrTimingBehavior
```

**OwnVoiceDetection**（8）
```
  OvdAdaptationMode
  OvdApplicationMode
  OvdAvailable
  OvdConstrainedBeamFormerMode
  OvdCurveIndex
  OvdStrength
  OvdTrainingFinished
  OvdTrainingMode
```

**AIEnhancedConversation**（7）
```
  ConversationEqualizerCosy
  ConversationEqualizerVeryLoud
  ConversationSupportModerateLoud
  EqualizerClassSelected
  SurroundingEqualizerCar
  SurroundingEqualizerOtherNoises
  SurroundingEqualizerTraffic
```

## 程序 / 用户控制

**ProgramHandling**（4）
```
  IsTinnitusProgram
  ListeningSituationConfig
  NumberOfActivePrograms
  RfProgramCategoryId
```

**UserControl**（20）
```
  CallControlAccessMode
  ConfigurableUserControlSelection
  GpioPinConfiguration
  PowerOnDelay
  PowerOnDelayEnable
  PushButtonLongPressConfiguration
  PushButtonMediumPressConfiguration
  PushButtonShortPressConfiguration
  RockerSwitchEndlessTrimmerDirection
  RockerSwitchLongPressConfiguration
  RockerSwitchMediumPressConfiguration
  RockerSwitchShortPressConfiguration
  UserConfigurationPin1
  UserConfigurationPin2
  UserConfigurationPin3
  UserConfigurationPin4
  UserConfigurationPin5
  UserConfigurationPin6
  UserControlLongPressConfiguration
  UserControlVeryLongPressConfiguration
```

**UserConfigurableFeatures**（5）
```
  IntelliZoomValue
  SEqMpoChannelGainOffset
  SideLookNarrowFocusState
  TinVcRange
  VcRange
```

**SignalRouting**（27）
```
  ActiveAuxTCoilFelixGainPreAmpOut
  ActiveMicFelixGainPreAmpOut
  AuxTCoilFelixGainPreAmpOut
  BiquadSetConfiguration
  IppFilterOrderFrontAndRearMic
  IppFilterOrderPinnaMic
  IppFilterOrderTcoil
  MicConnection
  MicFelixGainPreAmpOut
  MicPathSingleMic
  MicPrimary
  NumberOfTcoilNotches
  OutputModeSelection
  PinnaMicInput
  RearMicAdcDecActivated
  RearMicInput
  ReceiverOutputMode
  SbssLastStreamingSource
  SbssSource
  SbssSourceSelected
  SignalRoutingSbssActiveStreamedSource
  TCoilFelixGainPreAmpIn
  TCoilType
  TcoilFelixCurrBooster
  TcoilFelixGainBooster
  VcoilVoltage
  VmicVcoilVoltage
```

**AuxMode**（4）
```
  MicAttenuationForAudioStreaming
  MicAttenuationForTcoil
  NearEndListeningEnhancementUserDisable
  SbssMicAttenuationForTelephoneStreaming
```

**TwinPhone**（1）
```
  TwinPhoneRemoteMicLevel
```

**TvStreamer**（1）
```
  RfTvStreamerAllowed
```

## 耳鸣 / 助听评估

**TinnitusTherapy**（12）
```
  NttNotchFrequency
  NumberOfLogicalTinnitusChannels
  PhysicalTinnitusGains
  TinnitusFrequencyShapingSet1
  TinnitusFrequencyShapingSet2
  TinnitusFrequencyShapingSet3
  TinnitusFrequencyShapingSet4
  TinnitusMaskerMode
  TinnitusMasterGain
  TinnitusNoisePreset
  TinnitusOceanSetting
  TinnitusOceanSync
```

**HearingLossAssessment**（10）
```
  FrequencyIndex
  HearingLossAssessmentAvailable
  HlaToneFrequencies
  IssClient
  IssUseCase
  SequenceNumber
  ToneCycles
  ToneDurationForTimeOff
  ToneDurationForTimeOn
  ToneFrequency
```

**EasyFit**（10）
```
  EasyFitChannelMpo
  EasyFitCluster
  EasyFitCompressionKneepoint1
  EasyFitCompressionKneepoint2
  EasyFitCoupling
  EasyFitMpoThresholdsForSafetyLimiter
  EasyFitOpenVentOptimzationCoupling1
  EasyFitOpenVentOptimzationCoupling2
  EasyFitOpenVentOptimzationCoupling3
  EasyFitOpenVentOptimzationCoupling4
```

**AutomaticAcclimatization**（6）
```
  AacAcclimatizationLevel
  AacExperienceLevel
  AacGainOffset
  AacMode
  AacProfile
  AacStrategy
```

## 无线 / 电源 / 日志

**Wireless**（28）
```
  KeepAliveSendInterval
  MiBerTestResult
  MiTransmitterDisabled
  NfmiBitErrorRateStateMachineState
  NfmiHalcLinkState
  NfmiLinkCtrlState
  NfmiModalityRx
  NfmiResonanceCircuitQuality
  NfmiSyncState
  NfmiTransmitterDisabled
  NfmiTrimSuccess
  PhoneClipBonded
  ResonanceCircuitQuality
  RfAvailable
  RfBootState
  RfLeAudioAllowed
  RfMulticonAllowed
  RfOpMode
  RfOperatingMode
  RfProductionTestStatus
  SyncPulseTreshold
  WirelessMiHalcLinkState
  WirelessMiModalityRx
  WirelessMiSyncState
  WirelessMiTrimSuccess
  WlsAudioTransmissionScheme
  WlsMasterSlaveConfigOverride
  WlsTestMode
```

**WirelessBT**（14）
```
  ClearAllOrAllButMe
  KeepAliveSendInterval
  RfAuracastAllowed
  RfAvailable
  RfBootState
  RfBtcBatteryBalancingEnable
  RfBtcCurrentRole
  RfIcPinConfiguration
  RfLeau48kHzLc3Allowed
  RfLeauAllowed
  RfMultiConnection
  RfOpMode
  RfOperatingMode
  RfStandByClockSelection
```

**PowerManagement**（12）
```
  BatteryType
  ChargingResistance
  ChargingType
  CurrentBatteryStatus
  CurrentPwmMode
  OutputPowerMode
  PmicDischargingStatus
  PmicStuck
  PmicStuckRelease
  PowerConsumptionType
  ProchargeThreshold
  TwoWayCommunication
```

**Datalogging**（3）
```
  DataAnalysisUsageLevel
  DischgIntervalHistogramRecent
  RuntimeHistogramRecent
```

**DigitalAssistant**（3）
```
  CbfsClassFreezeStatus
  CbfsClassSelection
  CbfsSituationSelected
```

**Indicators**（7）
```
  IndicatorBatteryInterval
  IndicatorFrequencyShift
  IndicatorLoudness
  IndicatorSoundProfile
  RepeatStartupMelody
  SpeechIndicatorLanguage
  SpeechIndicatorVoiceGender
```

## 生产 / 测试（不用管）

**ElectroAcousticTest**（48）
```
  AgcoLowfreqThreshold
  AgcoReserve
  AmixerStatDir
  ChargerTwoWayCommunicationEnable
  DeviceAcousticTestConfiguration
  FogFrequencyShapingIndex
  Gain
  IndicatorLoudness
  InputModeCurveMapping
  InputMute
  IssClient
  IssUseCase
  KeepAliveSendInterval
  MatchingRefFrequency
  MicConnection
  MicFrequencyCompensationOffset
  MicMode
  MicPrimary
  MotionSensorAvailable
  NfcNotAvailable
  NumberOfActiveMicrophones
  OlgFinished
  PureToneFrequency
  PushButtonConnection
  ResonanceCircuitQuality
  RfAvailable
  RfBootState
  RfOpMode
  RfOperatingMode
  RockerSwitchEndlessTrimmerDirection
  SignalSource
  SlkNotAvailable
  SyncPulseTreshold
  TCoilFelixGainPreAmpIn
  TCoilType
  TcoilFelixCurrBooster
  TcoilFelixGainBooster
  TinnitusFrequencyShapingSet1
  ToneCycles
  ToneDurationForTimeOff
  ToneDurationForTimeOn
  ToneFrequency
  TrimmingLevelDone
  TrimmingPhaseDone
  UserConfigurationPin2
  UserConfigurationPin4
  VmicVcoilVoltage
  WirelessMiTrimSuccess
```

**ElectricalTest**（15）
```
  AGpio1ConfigForTest
  AGpio2ConfigForTest
  AGpio3ConfigForTest
  AGpio4ConfigForTest
  AGpio5ConfigForTest
  AGpio6ConfigForTest
  ActiveFwMode
  ChargingMode
  HiFirmwareReady
  MiWlsTransceiverTestResult
  Prepare
  SetStateLeds
  TestConfiguration
  WirelessMiSyncState
  WirelessMiTrimSuccess
```

**RfTest**（15）
```
  ClearAllOrAllButMe
  RafAdvChannelDis
  RafAdvIntChangeDis
  RafBootState
  RafMfiEnable
  RafTestState
  RalfOperationMode
  RfBootState
  RfIcPinConfiguration
  RfIcPowerSupplyConfig
  RfOperationMode
  RfStandByClockSelection
  RfSystemOperationMode
  RfTestMode
  RfTxPowerLevelReduction
```

**SelfCheck**（3）
```
  FbcCoefficientScaling
  GainClassification
  OlgFinished
```

**PmicTest**（5）
```
  ChargingType
  PmicDischargingStatus
  PmicFlashWriteEnable
  PmicTempLow
  ResTestSteps
```

**MiBitErrorRateTest**（7）
```
  McuDummyLoadReduction
  MiBerTestDevice
  MiBerTestResult
  MiBerTestTrimSuccess
  ResonanceCircuitQuality
  SyncPulseTreshold
  TinnitusGainShape
```

**RechargingTest**（13）
```
  BatFailTime
  ChargingType
  CommEn
  CvMax
  MaxChgTemp
  MaxFastChgTemp
  PreChgTime
  ProchargeThreshold
  ProtectionCircuitPSpkChCurStep
  ProtectionCircuitVbatMonIntNorm
  ResOverTemperatureDetector
  ResOverVoltageDetector
  TempBatMin
```

**PwmTrimming**（8）
```
  BatFailTime
  CvMax
  MaxChgTemp
  MaxFastChgTemp
  PmicFlashWriteEnable
  PreChgTime
  ProchargeThreshold
  TempBatMin
```

**OneTimeProgramming**（22）
```
  OtpReadChExtProtection
  OtpReadChFastFeedback
  OtpReadChOt45Trim
  OtpReadChOt50Trim
  OtpReadChOtTh
  OtpReadChOvTh
  OtpReadChOverrideChAutodetect
  OtpReadChPpmSet
  OtpReadChUvTh
  OtpReadEfuseTrimParity
  OtpReadEfuseTrimParity2
  OtpReadPcbI2CSel
  OtpReadTChTestmode
  OtpWriteChExtProtection
  OtpWriteChFastFeedback
  OtpWriteChOtTh
  OtpWriteChOvTh
  OtpWriteChOverrideChAutodetect
  OtpWriteChPpmSet
  OtpWriteChUvTh
  OtpWriteEfuseTrimParity2
  OtpWritePcbI2CSel
```

**QaParameters**（36）
```
  AmplFailAudio
  AmplFailCalib
  AmplFailCurrent
  AmplFailGmr
  AmplFailMic
  AmplFailMic3
  AmplFailMicdir
  AmplFailNoise
  AmplFailOther
  AmplFailPb
  AmplFailRec3
  AmplFailTc
  AmplFailTcoil
  AmplFailThd
  AmplFailVc
  AmplFailVmic
  AmplFailWl
  AmplRetested
  AmplTestMode
  AmplTestStatusLastTestPass
  AmplTestStatusRetest
  CoreTestStatusDefTestComplete
  CoreTestStatusDefTestPass
  CoreTestStatusIcRetrimmed
  CoreTestStatusTestNotDefault
  FinalTestStatusDefTestComplete
  FinalTestStatusIcRetrimmed
  FinalTestStatusInpCalOk
  FinalTestStatusTestNotDefault
  SmdTestStatusDefTestComplete
  SmdTestStatusDefTestPass
  SmdTestStatusIcRetrimmed
  SmdTestStatusLastTestPass
  SmdTestStatusMauCalOk
  SmdTestStatusRetest
  SmdTestStatusTestUnfinished
```

**NfmiBitErrorRateTest**（7）
```
  NfmiBerTestDevice
  NfmiBerTestRecNoiseGainShape
  NfmiBerTestResult
  NfmiIqCompensationSuccess
  NfmiLinkCtrlState
  NfmiTransmitterDisabled
  NfmiTrimSuccess
```

**AutomaticReceiverDetection**（3）
```
  AgpioPinForArd
  DetectedReceiverType
  ReceiverTypePreset
```

## 设备信息 / 配置

**VersionInfo**（3）
```
  ActiveFirmwareMode
  FapiRulesetType
  FelixChipRevision
```

**DeviceIdentification**（2）
```
  ConfiguredReceiverSize
  IdentifiedSystemSide
```

**BasicHwConfiguration**（16）
```
  GpioPinConfiguration
  MotionSensorAvailable
  PinnaMicInput
  PowerPushButtonPin
  RearMicInput
  ReceiverOutputMode
  RfAvailable
  RfAvailableOut
  TcoilInput
  UsedOutputStage
  UserConfigurationPin1
  UserConfigurationPin2
  UserConfigurationPin3
  UserConfigurationPin4
  UserConfigurationPin5
  UserConfigurationPin6
```

**FwSystemConfiguration**（3）
```
  ActiveFapiRuleset
  GlobalFwState
  LowLevelAccessUnlockMode
```

**ProgrammingInterface**（1）
```
  FwProgrammingMode
```

**RcuConfiguration**（1）
```
  ArcEasyFitDisable
```

**GeneralHearingInstrumentDescription**（2）
```
  HiShellType
  ShellType
```

**Detection**（17）
```
  ActiveFapiRuleset
  ArdType
  BatteryVoltage
  ConfiguredReceiverSize
  CurrentFirmwareMode
  CurrentPwmMode
  DetectedReceiverType
  FapiRulesetType
  FelixChipRevision
  FwExchangeRegion
  FwProgrammingMode
  HiShellType
  IdentifiedSystemSide
  NumberOfActivePrograms
  ReceiverTypePreset
  ShellType
  SystemSide
```

---

## 为什么不能直接用？

厂商 App 走的是 **FAPI 协议**，不是直接写 GATT 特征：

```
WSA.Foundation.FapiAccessLayer.dll        业务层（278 个 Feature）
FapiProtocol.Core.dll                     帧编解码、会话、分块发送
SHS.SAT.CommFW.FapiFramework.CommHiAnalyzerProvider.dll
    ├─ CertificateProvider                证书
    ├─ DiffieHellmanCalculation           密钥交换
    ├─ EcdsaCalculation                   签名
    └─ HmacCalculation                    完整性校验
BouncyCastle.Crypto / bc-fips             密码学实现
```

也就是**双向认证 + 加密通道**。想直接发 FAPI 帧，得把这一整套重写，
还要拿到客户端证书、复现认证握手 —— 工作量是「周」级别，且不一定成功。

## 那能做什么？

BLE 层能直通的只有我们已经摸到的那些特征（见能力矩阵）：

| 想做 | 走哪 | 现状 |
|---|---|---|
| 播放时压低麦克风 | `1454E9D6` 写 `00 01` | ✅ 已实现 |
| 通话时留 50% | 同上，写 `08 01` | ✅ 已实现 |
| 安静时恢复 60% | 同上，写 `09 01` | ✅ 已实现 |
| **切聆听程序** | ？`7BE94A55` / `A28B6BE1` 待验证 | ⏳ 用「对比」测 |
| **主音量** | ？`8B820C6D` 待验证 | ⏳ 用「对比」测 |

## 下一步怎么验

1. 打开 VibeGo 助手 → 实验室 → 矩阵 → **全量读取**
2. 实验室 → 对比 → **① 记基线**
3. 打开厂商 App，**切一次程序**（或拖一次主音量）
4. 回 VibeGo → 对比 → **② 找差异**

差异里出现的特征，就是那个功能的 BLE 入口。

- 如果 `7BE94A55` 或 `A28B6BE1` 变了 → 能写，做成「播放自动切程序」
- 如果 `8B820C6D` 变了 → 能写，做成「音量联动」
- 如果一条都没变 → 说明确实走 FAPI，只能作罢
