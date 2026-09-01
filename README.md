# Ayah

A lightweight, privacy-first, fully offline native macOS app that displays
Quran verses from the MacBook notch area, helps memorize selected verses,
and calculates Islamic prayer times entirely offline with in-notch prayer
alerts while the app is running.

**Status: 1.0.1 release candidate.** Ayah is available as an open-source,
unnotarized macOS app. The release policy does not use an Apple Developer
account, Developer ID, or notarization; review the installation steps below
before downloading.

## Priorities

In order: correctness of Quran data, privacy and security, very low
CPU/memory/battery usage, a native macOS experience, a simple maintainable
architecture, and open-source friendliness.

## What Ayah is

- A menu-bar-style app whose primary surface is the MacBook's notch area
  (with a standard menu-bar popover fallback on Macs without a notch)
- Periodic, unobtrusive display of Quran verses, with configurable
  frequency and how many consecutive verses appear at once (default 2)
- A persistent **Last Shown** card in the menu-bar popover, with replay for
  the most recent verse or prayer alert
- Selectable memorization sets (single ayah, ayah ranges, or full surahs)
  that appear more frequently than general verses, at a configurable ratio
- Fully offline Islamic prayer time calculation (Umm al-Qura by default,
  other configured methods available) with optional in-notch alerts
- Arabic/RTL Quran rendering with the bundled KFGQPC Uthmanic Hafs font
- An in-app **حول التطبيق** window crediting the KFGQPC Quran text/font,
  Adhan Swift, and GeoNames without implying affiliation or endorsement

## What Ayah deliberately is not

- No backend, no user accounts, no cloud sync, no login
- No analytics, telemetry, or crash reporting of any kind
- No advertisements or tracking
- No network calls during normal use — enforced at the OS level by
  omitting the App Sandbox network entitlement, not just promised in
  policy (see `PRIVACY.md`)
- No Electron, Chromium, or WebView — native Swift/SwiftUI/AppKit only

## Requirements

Apple Silicon Mac with macOS 13 (Ventura) or later. Version 1.0.1 does not
include an Intel `x86_64` binary.

## Installing the unnotarized release

Ayah 1.0.1 is distributed directly as
`Ayah-1.0.1-macOS-arm64.dmg`. It is ad-hoc signed to preserve bundle
integrity, but it has no Apple Developer ID signature and is not notarized.
macOS will therefore block its first launch as an unidentified-developer
app. After attempting to open Ayah, use **System Settings > Privacy &
Security > Open Anyway** for this app. Do not disable Gatekeeper globally.

[![Download Ayah for macOS](docs/assets/download-macos.svg)](https://github.com/wal7rbi/Ayah/releases/latest/download/Ayah-1.0.1-macOS-arm64.dmg)

The button downloads the current DMG from Ayah's public GitHub Release.

Download the accompanying `.sha256` file and verify the DMG before opening:

```sh
shasum -a 256 -c Ayah-1.0.1-macOS-arm64.dmg.sha256
```

Complete Arabic and English installation instructions remain available in
[`docs/release/INSTALL.txt`](docs/release/INSTALL.txt). The mounted DMG keeps
the standard uncluttered layout: drag **Ayah** to **Applications**. License and
source acknowledgements are bundled inside the app and can be opened from
**حول التطبيق**.

## Documentation

- **`ARCHITECTURE.md`** — full technical design: notch UI approach, data
  model, module boundaries, prayer-calculation details, scheduling
  strategy, and the phased build plan
- **`PRIVACY.md`** — exactly what's stored locally and how offline
  operation is architecturally enforced
- **`SECURITY.md`** — sandbox/entitlement posture and how to report a
  vulnerability
- **`THIRD_PARTY_LICENSES.md`** — every third-party dependency and
  bundled data resource, including a transparent, non-buried explanation
  of the Quran text/font licensing situation
- **`CONTRIBUTING.md`** — ground rules, especially around the Quran data
  pipeline
- **`docs/release/`** — the stable-release checklist, bilingual
  installation instructions, and published GitHub release notes

## License

Ayah's source code is MIT-licensed — see `LICENSE`. The bundled Quran
text, Quran font, and location data have their own licensing terms (one
of them with a documented, deliberately accepted risk rather than a clean
license) — see `THIRD_PARTY_LICENSES.md` before assuming anything in this
repository is uniformly licensed.
