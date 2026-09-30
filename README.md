# CrashAnalyzer

RootHide-compatible iOS 15–17 analytics log viewer for Settings.

## Features

- Automatically scans Apple analytics `.ips` logs.
- Classifies crash, memory/Jetsam, restart/panic, resource/watchdog, and unknown reports.
- Shows process, timestamp, exception, faulting thread, injected images, and local diagnosis.
- Keeps AI analysis optional; no log is uploaded by the local parser.

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

AI integration is intentionally not enabled in this first implementation. Any future network analysis must be explicitly opted in and redact device identifiers first.
