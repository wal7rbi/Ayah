# Ayah

A lightweight, privacy-first, fully offline native macOS app that displays
Quran verses from the MacBook notch area, helps memorize selected verses,
and calculates Islamic prayer times entirely offline with local
notifications.

**Status: design phase.** Architecture, licensing, and technology
decisions are finalized (see `ARCHITECTURE.md`); no application code
exists yet. The project is being built in small, reviewable stages rather
than all at once — see "Phased build order" in `ARCHITECTURE.md` for what
comes next.

## Priorities

In order: correctness of Quran data, privacy and security, very low
CPU/memory/battery usage, a native macOS experience, a simple maintainable
architecture, and open-source friendliness.

## What Ayah is

- A menu-bar-style app whose primary surface is the MacBook's notch area
  (with a standard menu-bar popover fallback on Macs without a notch)
- Periodic, unobtrusive display of Quran verses, with configurable
  frequency and how many consecutive verses appear at once (default 2)
- Selectable memorization sets (single ayah, ayah ranges, or full surahs)
  that appear more frequently than general verses, at a configurable ratio
- Fully offline Islamic prayer time calculation (Umm al-Qura by default,
  other methods available) with local macOS notifications before prayer
- Three reading themes (white, beige/Mushaf-style, black) with proper
  Arabic/RTL typography

## What Ayah deliberately is not

- No backend, no user accounts, no cloud sync, no login
- No analytics, telemetry, or crash reporting of any kind
- No advertisements or tracking
- No network calls during normal use — enforced at the OS level by
  omitting the App Sandbox network entitlement, not just promised in
  policy (see `PRIVACY.md`)
- No Electron, Chromium, or WebView — native Swift/SwiftUI/AppKit only

## Requirements

macOS 13 (Ventura) or later. Apple Silicon is the primary target.

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

## License

Ayah's source code is MIT-licensed — see `LICENSE`. The bundled Quran
text, Quran font, and location data have their own licensing terms (one
of them with a documented, deliberately accepted risk rather than a clean
license) — see `THIRD_PARTY_LICENSES.md` before assuming anything in this
repository is uniformly licensed.
