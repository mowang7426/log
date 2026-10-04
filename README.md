# CrashAnalyzer

## 1.3.1 · Build 16

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
