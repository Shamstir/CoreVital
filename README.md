# SubZero — macOS Menu Bar Agent

A lightweight, native macOS menu bar app that reads Apple Silicon / Intel hardware sensors (CPU/GPU temperature, fan RPM, battery health, power draw, memory, disk, network) and streams live telemetry to Firebase Firestore so the companion Android app can display it in real-time.

Built with **Swift 5.9 + SwiftUI + AppKit**, IOKit/SMC/IOReport private frameworks, and the Firebase iOS SDK.

---

## Architecture

```
SubZero (main app — menu bar UI, Firebase writer, fan curve UI)
├── SubZeroHelper (privileged LaunchDaemon — SMC writes for fan control)
└── SubZeroShared (XPC protocol + SMCWriter shared between both targets)
```

| Component | Role |
|---|---|
| `SensorKit/` | Reads CPU/GPU temps, fan RPMs, power draw via IOReport & SMC |
| `FanControl/` | Fan curve management; sends write commands to the Helper via XPC |
| `Storage/FirebaseManager.swift` | Pushes sensor snapshots to Firestore every ~3 s |
| `App/MenuBar/` | NSStatusItem menu bar UI |

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Xcode | ≥ 15.0 | Mac App Store |
| macOS | ≥ 13.0 Ventura | — |
| XcodeGen | latest | `brew install xcodegen` |
| Firebase iOS SDK | pulled automatically via SPM | — |

---

## Setup

### 1 — Clone the repo

```bash
git clone https://github.com/Shamstir/CoreVital.git
cd CoreVital
```

### 2 — Add your Firebase credentials

This file is **not** committed (see `.gitignore`). You must supply your own:

1. Go to your [Firebase Console](https://console.firebase.google.com/) → Project settings → Your apps.
2. Download `GoogleService-Info.plist` for the **macOS / Apple** app registered under bundle ID `com.subzero.app`.
3. Place it at:

```
CoreVital/SubZero/GoogleService-Info.plist
```

### 3 — Generate the Xcode project

```bash
xcodegen generate
```

This reads `project.yml` and produces `SubZero.xcodeproj`.

### 4 — Resolve Swift Package dependencies

Xcode will resolve them automatically on first open. Alternatively:

```bash
xcodebuild -resolvePackageDependencies -project SubZero.xcodeproj
```

---

## Build & Run

### Debug build (run in Xcode)

```bash
open SubZero.xcodeproj
```

Select the **SubZero** scheme → **My Mac** → ▶ Run.

### Release build from terminal

```bash
xcodebuild \
  -project SubZero.xcodeproj \
  -scheme SubZero \
  -configuration Release \
  -derivedDataPath build/ \
  clean build
```

The `.app` bundle will be at:

```
build/Build/Products/Release/SubZero.app
```

### Run without code signing (development)

The project sets `CODE_SIGN_IDENTITY = "-"` (ad-hoc) by default, so you can build and run locally without a paid developer account. If Gatekeeper blocks the app:

```bash
xattr -d com.apple.quarantine build/Build/Products/Release/SubZero.app
```

---

## Fan Control (Privileged Helper)

Fan speed writes require a **privileged LaunchDaemon** (`com.subzero.helper`). The build phase embeds the helper inside the app bundle automatically. On first launch SubZero will prompt for admin credentials to install the helper.

On Intel Macs, SMC fan writes are supported. On Apple Silicon, fan control is read-only (Apple does not expose public SMC write keys for M-series fans).

---

## Firestore Data Structure

The agent writes to:

```
devices/{deviceId}/telemetry (live document, overwritten every ~3 s)
```

Fields match the schema expected by the companion Android app (`subZero`).

---

## Running the Tests

```bash
xcodebuild test \
  -project SubZero.xcodeproj \
  -scheme SubZeroTests \
  -destination 'platform=macOS'
```

---

## Companion App

The Android companion app that displays this telemetry lives at:
👉 [github.com/Shamstir/subzero](https://github.com/Shamstir/subzero)

---

## License

MIT
