# CrashAnalyzer

RootHide-compatible iOS 15–17 analytics log viewer for Settings.

## Features

- Automatically scans Apple analytics `.ips` logs.
- Classifies crash, memory/Jetsam, restart/panic, resource/watchdog, and unknown reports.
- Shows process, timestamp, exception, faulting thread, injected images, and local diagnosis.
- Keeps AI analysis optional; no log is uploaded by the local parser.

## Build

This project uses Theos. Set `THEOS` to your Theos checkout and run:

```sh
make package FINALPACKAGE=1
```

The default `ARCHS` is `arm64 arm64e`. The package is rootless-friendly and installs a PreferenceBundle under `/Library/PreferenceBundles`.

## Privacy

AI integration is intentionally not enabled in this first implementation. Any future network analysis must be explicitly opted in and redact device identifiers first.
