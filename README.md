# BatteryMonitor (Unsigned IPA build)

A minimal SwiftUI iOS app that shows:
- Thermal state (4 levels)
- Low Power Mode
- Charging state
- Estimated %/hr and ETA (full/dead) based on recent battery samples
- Optional Picture-in-Picture overlay for wide, low-height PiP

## Notes
- Estimates require a few minutes of data to stabilize.
- PiP requires enabling the iOS capability/background mode: **Audio, AirPlay, and Picture in Picture**.
  This repo includes the code; you may need to toggle the capability in Xcode once if your Xcode version requires it.

## GitHub Actions (unsigned IPA)
This repo includes a workflow that:
1) Builds the app for `iphoneos` **without code signing**
2) Packages the `.app` into an `.ipa` (zip with `Payload/App.app`)
3) Uploads the unsigned `.ipa` as an Actions artifact

The produced IPA is not installable until you sign it.
