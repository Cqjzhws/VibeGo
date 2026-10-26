#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
VibeGo 助手 0.6.0 打包器

在 0.4.7 的基础上：
  · 去掉两个空壳标签页（快捷 / 看护）
  · 新增「麦克风」联动控制页
  · 新增「深度探测」能力矩阵页（复用同一条 BLE 连接，不额外扫描）
  · 内置 HearingLink（GATT 写入 / 断线重连 / 右耳锁定）+ 全局音频与通话探测
"""
import os, sys, shutil, subprocess, zipfile, plistlib

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "src")
SDK = os.environ.get("IPHONEOS_SDK") or r"C:/Users/Administrator/WorkBuddy/2026-10-20-01-45-41/sdk/iPhoneOS16.5.sdk"
OLD_IPA = os.environ.get("VIBEGO_BASE_IPA") or r"C:/Users/Administrator/Documents/xwechat_files/www_531818_com_6bde/msg/file/2026-10/VibeGo 助手_0.4.7.ipa"
import platform

# macOS 上用 xcrun clang（最稳，自动处理 iOS SDK/stub/framework）
# 其他平台 fallback 到 zig cc
def _cc():
    if platform.system() == "Darwin":
        return ["xcrun", "--sdk", "iphoneos", "clang"]
    import sys as _sys
    return [_sys.executable, "-m", "ziglang", "cc"]

CC = _cc()

APP = "VibeGo"
DISPLAY = "VibeGo 助手"
VERSION = "0.7.0"
BUILD_NO = "20"
TARGET = "aarch64-apple-ios15.0"
OUT_IPA = os.path.join(ROOT, "VibeGo助手-0.7.0.ipa")

BASE_CFLAGS = [
    "-target", TARGET,
    "-fobjc-arc", "-fobjc-exceptions", "-ObjC", "-O2",
    "-fno-sanitize=undefined",
    "-DHL_STANDALONE_APP=1",
    "-I", SRC, "-I", os.path.join(SRC, "Core"), "-I", os.path.join(SRC, "UI"),
    "-Wno-deprecated-declarations", "-Wno-nullability-completeness",
    "-Wno-unused-variable", "-Wno-unused-function",
    "-Wno-unused-but-set-variable", "-Wno-format",
]

# macOS xcrun 会自动设置 sysroot/framework 搜索路径；非 macOS 手动加
if platform.system() != "Darwin":
    BASE_CFLAGS += [
        "-isysroot", SDK,
        "-isystem", os.path.join(SDK, "usr", "include"),
        "-F", os.path.join(SDK, "System", "Library", "Frameworks"),
    ]

FRAMEWORKS = ["UIKit", "CoreGraphics", "QuartzCore", "CoreBluetooth",
              "Accessibility", "Security", "UserNotifications",
              "AVFoundation", "CoreTelephony", "MediaPlayer", "Foundation",
              "CallKit"]
LDFLAGS = ["-Wl,-headerpad,0x4000"]


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        print(r.stdout[-6000:])
        print(r.stderr[-6000:])
        raise SystemExit("FAILED: %s" % " ".join(cmd[:6]))
    if r.stderr.strip():
        for line in r.stderr.strip().splitlines():
            if "error" in line or "warning" in line:
                print("  ", line)
    return r


def sources():
    out = []
    for root, _, files in os.walk(SRC):
        for fn in sorted(files):
            if fn.endswith(".m"):
                out.append(os.path.join(root, fn))
    return out


def main():
    build = os.path.join(ROOT, "build")
    if os.path.exists(build):
        shutil.rmtree(build)
    app_dir = os.path.join(build, "Payload", "VibeGo.app")
    os.makedirs(app_dir)

    srcs = sources()
    print("[1/4] 编译 %d 个源文件" % len(srcs))
    exe = os.path.join(app_dir, APP)
    cmd = CC + BASE_CFLAGS + LDFLAGS
    if platform.system() != "Darwin":
        cmd += ["-L", os.path.join(SDK, "usr", "lib")]
    cmd += srcs + ["-o", exe]
    for f in FRAMEWORKS:
        cmd += ["-framework", f]
    if platform.system() != "Darwin":
        cmd += ["-l", "objc", "-l", "dispatch", "-l", "System", "-l", "dl"]
    run(cmd)
    os.chmod(exe, 0o755)
    print("      二进制 %.1f KB" % (os.path.getsize(exe) / 1024.0))

    print("[2/4] 组装 App 包")
    with open(os.path.join(SRC, "Info.plist"), "rb") as f:
        info = plistlib.load(f)
    info["CFBundleShortVersionString"] = VERSION
    info["CFBundleVersion"] = BUILD_NO
    info["CFBundleDisplayName"] = DISPLAY
    info["CFBundleName"] = DISPLAY
    info["MinimumOSVersion"] = "15.0"
    info["NSBluetoothAlwaysUsageDescription"] = (
        "用于连接 Vibe Go 助听器：读取电池/状态信息，并联动调节麦克风音量档位"
        "（播放声音时压低、安静时恢复、通话时按通话档位）。全部在本机完成。")
    modes = info.get("UIBackgroundModes", [])
    for m in ("bluetooth-central", "audio"):
        if m not in modes:
            modes.append(m)
    info["UIBackgroundModes"] = modes
    info["UIFileSharingEnabled"] = True
    info["LSSupportsOpeningDocumentsInPlace"] = True
    with open(os.path.join(app_dir, "Info.plist"), "wb") as f:
        plistlib.dump(info, f)

    # 图标：优先用本地 icons/（自给自足），没有才回落到 0.4.7 的 IPA
    icon_dir = os.path.join(ROOT, "icons")
    got = 0
    if os.path.isdir(icon_dir):
        for fn in sorted(os.listdir(icon_dir)):
            if fn.lower().endswith(".png"):
                shutil.copy2(os.path.join(icon_dir, fn), os.path.join(app_dir, fn))
                print("      图标", fn, "(本地)")
                got += 1
    if got == 0 and os.path.exists(OLD_IPA):
        with zipfile.ZipFile(OLD_IPA) as z:
            for n in z.namelist():
                if n.startswith("Payload/VibeGo.app/") and n.lower().endswith(".png"):
                    with open(os.path.join(app_dir, os.path.basename(n)), "wb") as f:
                        f.write(z.read(n))
                    print("      图标", os.path.basename(n), "(自 0.4.7)")
    if got == 0 and not os.path.exists(OLD_IPA):
        print("      ⚠ 没有图标（icons/ 为空且找不到 0.4.7），App 会显示白图标")

    print("[3/4] 打包")
    if os.path.exists(OUT_IPA):
        os.remove(OUT_IPA)
    with zipfile.ZipFile(OUT_IPA, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(os.path.join(build, "Payload")):
            for fn in files:
                p = os.path.join(root, fn)
                z.write(p, os.path.relpath(p, build))
    print("      %s (%.1f KB)" % (OUT_IPA, os.path.getsize(OUT_IPA) / 1024.0))

    print("[4/4] 自校验")
    import lief
    b = lief.MachO.parse(exe).at(0)
    assert b.header.cpu_type == lief.MachO.Header.CPU_TYPE.ARM64
    data = open(exe, "rb").read()
    for bad in (b"ubsan", b"__dyld_get_image_header_containing_address"):
        assert bad not in data, "混进了 %r" % bad
    with zipfile.ZipFile(OUT_IPA) as z:
        names = z.namelist()
        i2 = plistlib.loads(z.read("Payload/VibeGo.app/Info.plist"))
    assert "Payload/VibeGo.app/VibeGo" in names
    assert i2["CFBundleIdentifier"] == "com.vibego.assist"
    assert "bluetooth-central" in i2["UIBackgroundModes"]
    print("      OK：arm64 / %s / 后台模式 / 无 ubsan（%d 字节）"
          % (i2["CFBundleShortVersionString"], len(data)))


if __name__ == "__main__":
    main()
