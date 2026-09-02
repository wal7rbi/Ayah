# Privacy

Ayah is designed so that privacy is a property of its architecture, not a
promise in a policy document. This page explains exactly what the app
stores, what it never does, and how that's technically enforced rather than
merely stated.

## What Ayah stores locally

Everything Ayah stores lives only on your Mac, in your user account, and is
never transmitted anywhere:

- **App preferences** — verse display interval, verses shown per display,
  memorization weighting, prayer location source, selected city, prayer
  calculation method, Asr calculation method, and the prayer-alert toggle
  and reminder lead time. Stored via `UserDefaults` under a single key.
- **Current-location coordinates and time zone**, if you explicitly opt into "استخدام
  الموقع الحالي" (use current location) as your prayer-time input instead
  of picking a city — see "Location" below. The last-fetched coordinates,
  the time they were fetched, and the Mac's IANA time-zone identifier at
  that moment are cached via `UserDefaults` so the app doesn't need to ask
  again on every launch or reinterpret an old fix after travel.
- **Memorization sets** — the surah/ayah ranges you've chosen to memorize,
  their enabled/disabled state, and repetition mode. Stored in a small local
  SQLite database in Ayah's sandbox container.
- **Last shown item** — one record for the latest verse batch or prayer
  alert, including its original display time. Verse content is persisted as
  Quran ayah IDs only (plus the prayer key/timing fields when applicable),
  then read again from the verified bundled Quran database for display. Ayah
  keeps no full display history. Stored via a separate `UserDefaults` key.
- **The Quran text itself** — bundled read-only inside the app; never
  modified, never uploaded, never synced.

Ayah does not create a user account, does not require sign-in, and has no
concept of a user identity beyond "whoever is logged into this Mac."
The cached coordinates and memorization database are not independently
encrypted. App Sandbox limits Ayah's own access, but it is not a defense
against an attacker or process already operating as the same macOS user;
that local-device threat remains a documented hardening opportunity.

## What Ayah never does

- No backend server, no cloud database, no cloud sync
- No user accounts or login
- No analytics or telemetry of any kind
- No external crash-reporting service
- No advertisements
- No tracking, fingerprinting, or usage monitoring
- No remote configuration
- No API calls during normal use — the app has no reason to ever reach the
  network, and prayer times and Quran verses are calculated/read entirely
  offline
- No transmission or synchronization of the last-shown record

## How this is enforced, not just promised

Most privacy claims from an app are a policy: a statement of intent that
you have to trust. Ayah's core network claim is instead an architectural
guarantee, enforced by macOS itself:

Ayah adopts the **App Sandbox** and deliberately **omits the
`com.apple.security.network.client` entitlement**. This is not a
review-time-only checkbox — it is enforced at the kernel level by macOS's
sandbox daemon (`sandboxd`). Without that entitlement, the sandboxed Ayah
process is technically incapable of opening an outbound network connection,
regardless of what the code tries to do. If a future contributor
accidentally introduced networking code, the OS itself would block it.

Ayah's only third-party code dependency (Adhan Swift, used for offline
prayer time calculation) has zero dependencies of its own and performs no
networking. There is no analytics SDK, no crash-reporting SDK, and no
advertising SDK anywhere in the dependency graph, by design — see
`THIRD_PARTY_LICENSES.md` for the full, deliberately short list of what's
actually bundled.

## Location

By default, Ayah does not request macOS Location Services access. Prayer
time calculation normally uses a city you select manually from a small
bundled offline database — no location permission is needed for this path
at all.

Ayah also offers an explicit, opt-in "استخدام الموقع الحالي" (use current
location) convenience as an alternative to picking a city. Location access
is requested only the moment you tap that control — never automatically,
never on app launch, and never on a recurring timer — and only a one-shot
fix is taken (`CLLocationManager.requestLocation()`, not a continuous
subscription). The resulting coordinates are cached locally (see "What
Ayah stores locally" above) and reused until you tap again to refresh.

One honest caveat to the "fully offline" claim lives entirely in this
opt-in path: Macs have no GPS chip, so resolving your location goes
through macOS's own `locationd`, typically using nearby Wi-Fi access
points — this can involve network traffic *outside* Ayah's sandboxed
process, initiated by the OS on Ayah's behalf, even though Ayah's own
entitlements still never include `network.client` and Ayah itself never
opens a connection. The in-app control that triggers this carries the same
disclosure as caption text at the point you'd tap it, so it's never
surfaced only here. If you'd rather avoid this entirely, the city picker
requires no location permission and no such traffic.

## Notifications

Prayer-time reminders are not OS notifications at all — they render as an
in-app popup in the notch (or, on a Mac without one, a floating bar in the
same place), the same UI element that shows Quran verses, timed and drawn
entirely by Ayah's own process while it's running. Ayah
does not use macOS's `UserNotifications` framework for this, requests no
notification permission, and there is no push notification service — no
third party is ever involved, because nothing leaves the app to be
delivered.

## Questions

If anything in this document is unclear, or you find behavior that
contradicts it, please open an issue — a privacy claim that doesn't match
the code is a bug, not a matter of opinion.
