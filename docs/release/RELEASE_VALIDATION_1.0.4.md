# Ayah 1.0.4 release validation

- Version: 1.0.4, build 5; Apple Silicon; macOS 13 or newer.
- Publication authorization: the maintainer requested preparation and publication with “do it” after being told the remaining packaging and hardware checks. This authorizes publication; it is not represented as evidence that manual tests passed.
- Automated package/app regression suites, Quran/GeoNames integrity, release architecture, signature, entitlements, sealed resources, and shipping-automation exclusion: passed in the release-candidate run.
- Long idle and repeated popover resource checks: their results are recorded in the accompanying packaging report; this document does not predeclare their result.
- Physical clamshell/external-monitor transitions, a fresh quarantined download on a clean macOS profile, VoiceOver review, and the real launch-at-login approval flow: **not verified in this release session**. Display transitions and Reduce Motion have automated regression coverage; that does not certify hardware behavior.
- The full packaging report records each automated result and preserves MANUAL statuses for checks requiring additional hardware or operator observation.
- Signature is ad-hoc with hardened runtime. No Apple Developer ID or Apple notarization is used.

The packaging option is now named `--publication-approved` to distinguish authorization from test coverage. The older spelling remains an alias. This reflects the distinction already documented for 1.0.2: a publication decision must not turn unchecked manual items into asserted passes.
