# ✈️ JetGlass

A liquid-glass iOS app for plane spotters. Built with SwiftUI for **iOS 26** (Liquid Glass design), on **Apple Maps (MapKit)**.

## Features

- **Live Map tab** — Apple Maps foundation (MapKit / MKMapView)
  - Live aircraft from FlightRadar24's public zone feed, refreshed as you pan.
  - Toggle to **show airline labels above** each plane (mapped from the flight's ICAO airline code).
  - **Search an airport by ICAO code** (e.g. `KCOS`, `KSLX`, `KDEN`, `EGLL`) to jump to it.
- **Photos tab**
  - Search a **registration** (e.g. `N142UW`) or **any query** (e.g. `A350`).
  - Pulls photos + metadata from [JetPhotos] via [jetapi.dev], and flight history from [FlightRadar24] via the same API.
  - Tap a photo for the full-screen view, then **download it to your photo library**, share it, or open the **Source** page on JetPhotos.
- **Settings tab**
  - JetAPI base URL, photo/flight counts, map refresh interval, airline labels, haptics, clear image cache, **AltStore Direct install link**, source links, about & credits.

## Install

- **AltStore Direct (recommended):** with AltStore installed, open the *Install with AltStore (Direct)* link in the app's Settings tab, or paste this in Safari:

  ```
  altstore://install?url=https%3A%2F%2Fnightly.link%2Faepikgamer-art%2FJetGlass%2Fworkflows%2FBuild%2520IPA%2Fmain%2FJetGlass-ipa.zip
  ```

  It points at the latest IPA built by GitHub Actions via [nightly.link] (direct artifact download, no GitHub login needed).

- **Manual:** Actions tab → **Build IPA** → download the `JetGlass-ipa` artifact → sideload with AltStore / SideStore / Sideloadly, or re-sign it yourself:

```bash
codesign -f -s "Apple Development: ..." --entitlements JetGlass.entitlements Payload/JetGlass.app
zip -r JetGlass-signed.ipa Payload
```

## Building the IPA

GitHub Actions builds an **unsigned IPA** on every push to `main` (also manually via *Run workflow*).

- Runs on the **`macos-26`** runner with **Xcode 26** — required so the iOS 26 **Liquid Glass** APIs (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`) compile. The workflow fails fast if it ever lands on an Xcode older than 26.

1. Go to the **Actions** tab → **Build IPA** → grab the `JetGlass-ipa` artifact.
2. Sideload or re-sign as above.

Local build (needs Xcode 26 + [XcodeGen]):

```bash
xcodegen generate
xcodebuild -scheme JetGlass -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Tech

- SwiftUI + **Apple Maps (MapKit)**, iOS 26 Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`)
- [jetapi.dev] — aircraft data from JetPhotos + FlightRadar24
- FlightRadar24 public zone feed for live traffic
- XcodeGen project generation, no `.xcodeproj` checked in

[jetapi.dev]: https://www.jetapi.dev
[JetPhotos]: https://www.jetphotos.com
[FlightRadar24]: https://www.flightradar24.com
[XcodeGen]: https://github.com/yonaskolb/XcodeGen
[nightly.link]: https://nightly.link
