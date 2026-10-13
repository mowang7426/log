# CrashAnalyzer

## 1.4.0 体验版

- 兼容 Preferences 的 IPSLog 体验列表：入口和详情均为 `PSListController`/`PSSpecifier`，不把普通 `UITableViewController` 交给 `detail`。列表顶部可见“搜索”“按时间/按进程”按钮；搜索覆盖进程、Bundle ID、文件名、时间、异常、Jetsam/Panic/watchdog 字段。
- 每条日志保留 Preferences 原生详情导航，同时提供“选择删除”和“删除此条日志”；顶部批量删除会二次确认，删除只针对扫描时确认的普通文件，不碰 AI/case/plugin evidence。
- 详情首屏保留本地分析、AI/case/evidence/workbench/source 入口，并显示解析状态及 Jetsam 所有受害进程、真实 pageSize、Panic 原文摘要、watchdog termination 字段。
- 保留增量扫描、AI、案例与插件证据。所有新增实现已加入 Makefile；`CAReportDate` 由 CALogExperience.m 提供并随 bundle 编译，避免运行时 undefined symbol。
- 原文使用等宽 UITextView，后台最多读取 4 MiB；支持选择复制和查找；复制标明预览范围；完整分享显式隐私确认、独立临时目录及完成清理。
- 单 JSON（compact/pretty/BOM）及双段 JSON 解析；正文失败显式标记部分成功，不计作完整解析。分类只读取结构字段，进程名不再等于崩溃，EXC_RESOURCE/watchdog 优先资源类。
- Jetsam 展示所有含 reason 的终止进程和真实 pageSize；缺失页大小不换算。Panic/watchdog 展示原字段，不推断硬件或根因。
- 保留增量扫描、AI、案例与插件证据。未实施 Keychain 迁移、统一 AI 缓存计划、legacy 文本全格式及 lastExceptionBacktrace 证据扩展。
- 原文查看上限不是索引扫描的内存上限：扫描仍解析完整日志，大文件性能需真机测量。删除固定路径而非 inode；同一路径被替换仍存在竞争窗口。不保证权限不可达日志可读。
- CI/Foundation 回归与 UIKit 包构建不是实际设备安装/视觉/性能验证。未安装插件，未删除用户日志。

## UI CHANGELOG · 1.4.0-card

- 崩溃详情仍由 `CAReportDetailController : PSListController` 提供；新增 Preferences 原生 `PSTableCell` 卡片，避免把普通 `UITableViewController` 作为 detail。
- 首屏卡片展示真实进程/Bundle ID/PID/版本/时间、异常信号/地址/代码、触发线程和函数；动态库按故障帧实际引用、其他线程引用、仅加载未归因分层，不把出现等同根因。
- 卡片使用系统语义颜色、圆角、Dynamic Type 和自适应行高；AI、case、workbench、原文、复制及 Jetsam/Panic/watchdog 专项入口保持不变。CI 仅做编译/回归，视觉和性能仍需真机验证。


- Reorganized Settings around recent logs, local explanations, prominent AI configuration/history, learning/cases, and one advanced-tools entry. Crash details lead with plain-language evidence and a prominent AI action; source, technical details, and workbench remain available. Existing preflight, explicit cost confirmation, cancellation, history, privacy controls, case matching, and source viewing are retained.
- UI-only change: evidence remains real-data-only; possible causes remain unconfirmed. Existing async navigation/scan and scan engine are unchanged.


- Plugin evidence separates actual fault-thread references, auxiliary other-thread references, loaded-only images (no attribution evidence), and malformed/missing evidence. Counts are distinct incident reports, never a caused-crash count.
- Plugin details retain actual process/exception/thread/frame/symbol evidence and original report/source links. No fields are synthesized.
- Local plugin validation records five observation states, the actual entered test date, optional app/plugin versions and notes. No recurrence is not a confirmed cause; this tool does not change tweaks.
- Home/plugin/report rows wrap with Dynamic Type and system colors; complete paths can be copied.
- Existing asynchronous scan/navigation is retained. A 15-second metadata check while Settings runs, activation/entry refresh and the explicit refresh reuse unchanged reports, parse added/changed files, and remove deleted files. iOS suspension pauses checks; last scan and counts are shown.
- Foundation regression tests include strict ARC/MRC plugin evidence and MRC incremental directory scans, in addition to existing case/human/workbench tests.

Plugin candidates are deliberately restricted to known MobileSubstrate DynamicLibraries and TweakInject paths (including rootless/RootHide prefixes). Other libraries are not inferred to be tweaks merely because they are under a jailbreak root. If the original IPS file is moved/deleted, the captured analysis remains visible but its source-view link may no longer be readable.

No real-device installation/visual test is implied by CI builds. Navigation performance profiling/overhaul is intentionally excluded.


RootHide-compatible iOS 15–17 analytics log viewer for Settings.

## Features

- Automatically scans Apple analytics `.ips` logs; recent reports and categories lead the simplified Settings flow.
- Classifies crash, memory/Jetsam, restart/panic, resource/watchdog, and unknown reports.
- Crash details lead with a plain-language local explanation, evidence, confidence boundaries, next steps, and a prominent per-log AI action. Advanced evidence, source view, workbench, and scan diagnostics remain available.
- AI configuration/history and local learning/cases remain available. Network analysis requires explicit user confirmation; local parsing does not upload logs.

## Build locally

### Option A: GitHub Actions (recommended)

This repository includes `.github/workflows/build.yml`, using the proven RootHide Theos setup flow (macOS 14 + RootHide Theos + iPhoneOS 16.5 SDK). Push to `main`, or open **Actions → Build CrashAnalyzer → Run workflow**.

It produces two arm64e packages for your RootHide setup:

- `CrashAnalyzer-arm64e-rootless.deb`
- `CrashAnalyzer-arm64e-roothide.deb`

Download them from the workflow's **Artifacts** section. For Relaxin RootHide, try the RootHide-scheme package first. The workflow validates that the PreferenceBundle and PreferenceLoader entry are present in each package.

### Option B: Build with Theos on macOS/Linux

Install Theos and an iOS SDK first. The repository does **not** include Apple's SDK because it cannot be redistributed. Then run:

```sh
export THEOS=$HOME/theos
# install the iOS 15+ SDK in $THEOS/sdks, then:
git clone https://github.com/mowang7426/log.git
cd log
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless ARCHS="arm64"
make clean
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless ARCHS="arm64e"
ls -lh packages/*.deb
```

For a local Theos setup, see the official Theos documentation: https://theos.dev/docs/

The `Makefile` defaults to both architectures, but separate commands produce clearly named single-architecture packages. The package scheme is **rootless**, intended for modern rootless/RootHide environments.

## Installation

Copy the matching `.deb` to the phone and install it with Sileo/Zebra, or use SSH:

```sh
dpkg -i /path/to/CrashAnalyzer_*.deb
sbreload
```

The package installs the PreferenceLoader entry and the Settings preference bundle. The first device test should confirm which analytics directories are readable under the particular RootHide/Relaxin setup.

## Privacy

Local parsing never sends data. Optional AI requests are available only through explicit preflight and user confirmation. The privacy setting controls whether full `.ips` source is included; otherwise the request uses structured report information. Review the preflight payload and model/provider terms before sending.
