# ✈️ JetGlass

A liquid-glass iOS app for plane spotters. Built with SwiftUI for **iOS 26** (Liquid Glass design).

## Features

- **Live Map tab**
  - Live aircraft from FlightRadar24's public zone feed, refreshed as you pan.
  - Toggle to **show airline labels above** each plane (mapped from the flight's ICAO airline code).
  - **Search an airport by ICAO code** (e.g. `KCOS`, `KSLX`, `KDEN`, `EGLL`) to jump to it.
- **Photos tab**
  - Search a **registration** (e.g. `N142UW`) or **any query** (e.g. `A350`, `Lufthansa-748`).
  - Pulls photos + metadata from [JetPhotos] via [jetapi.dev], and flight history from [FlightRadar24] via the same API.
  - Tap a photo for the full-screen view, then **download it to your photo library** or share it.
- **Settings tab**
  - JetAPI base URL, photo/flight counts, map refresh interval, airline labels, haptics, clear image cache, about & credits.

## Building the IPA

GitHub Actions builds an **unsigned IPA** on every push to `main` (also manually via *Run workflow*).

1. Go to the **Actions** tab → **Build IPA** → grab the `JetGlass-ipa` artifact.
2. The IPA is unsigned: sideload it with AltStore / SideStore / Sideloadly, or re-sign it with your own certificate:

```bash
codesign -f -s "Apple Development: ..." --entitlements JetGlass.entitlements Payload/JetGlass.app
zip -r JetGlass-signed.ipa Payload
```

Local build (needs Xcode 26 + [XcodeGen]):

```bash
xcodegen generate
xcodebuild -scheme JetGlass -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Tech

- SwiftUI + MapKit, iOS 26 Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`)
- [jetapi.dev] — aircraft data from JetPhotos + FlightRadar24
- FlightRadar24 public zone feed for live traffic
- XcodeGen project generation, no `.xcodeproj` checked in

[jetapi.dev]: https://www.jetapi.dev
[JetPhotos]: https://www.jetphotos.com
[FlightRadar24]: https://www.flightradar24.com
[XcodeGen]: https://github.com/yonaskolb/XcodeGen
