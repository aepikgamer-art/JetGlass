<h3 align="center">
<a href="https://altdirect.app/?url=https://raw.githubusercontent.com/aepikgamer-art/JetGlass/main/altstore-source.json"><img src="https://altdirect.app/assets/png/AltSource_Blue.png" target="_blank" width="200"></a>
&nbsp;
<a href="https://github.com/aepikgamer-art/JetGlass/releases/latest/download/JetGlass.ipa"><img src="https://altdirect.app/assets/png/Download_Blue.png" target="_blank" width="200"></a>
</h3>

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
  - JetAPI base URL, photo/flight counts, map refresh interval, airline labels, haptics, clear image cache, **AltDirect source link**, direct IPA download, source links, about & credits.

## Install

- **AltDirect (recommended):** tap the *Add AltSource* badge above, or open
  `https://altdirect.app/?url=https://raw.githubusercontent.com/aepikgamer-art/JetGlass/main/altstore-source.json`
  — it gives one-tap **Open in AltStore / SideStore / StikStore / Feather / TrollApps** buttons that add the JetGlass source. AltStore will then install and refresh JetGlass like any source app. (Unsigned app — it still gets sideloaded with your own Apple ID.)

- **Direct download:** tap the *Download .ipa* badge above, or grab [`JetGlass.ipa`](https://github.com/aepikgamer-art/JetGlass/releases/latest/download/JetGlass.ipa) from the [latest release](https://github.com/aepikgamer-art/JetGlass/releases/latest), then sideload with AltStore / SideStore / Sideloadly, or re-sign it yourself:

```bash
codesign -f -s "Apple Development: ..." --entitlements JetGlass.entitlements Payload/JetGlass.app
zip -r JetGlass-signed.ipa Payload
```

## Building the IPA

GitHub Actions builds an **unsigned IPA** on every push to `main` and **publishes a GitHub Release with the IPA on every `v*` tag**.

- Runs on the **`macos-26`** runner with **Xcode 26** — required so the iOS 26 **Liquid Glass** APIs (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`) compile. The workflow fails fast if it ever lands on an Xcode older than 26.

Local build (needs Xcode 26 + [XcodeGen]):

```bash
xcodegen generate
xcodebuild -scheme JetGlass -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Tech

- SwiftUI + **Apple Maps (MapKit)**, iOS 26 Liquid Glass (`glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`)
- [jetapi.dev] — aircraft data from JetPhotos + FlightRadar24
- FlightRadar24 public zone feed for live traffic
- [AltDirect] for AltStore source distribution
- XcodeGen project generation, no `.xcodeproj` checked in

[jetapi.dev]: https://www.jetapi.dev
[JetPhotos]: https://www.jetphotos.com
[FlightRadar24]: https://www.flightradar24.com
[XcodeGen]: https://github.com/yonaskolb/XcodeGen
[AltDirect]: https://altdirect.app
