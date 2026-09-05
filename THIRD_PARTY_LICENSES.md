# Third-Party Licenses & Data Provenance

Ayah's own source code is MIT-licensed (see `LICENSE`). This file documents
every third-party dependency and bundled resource, its license, and — where
a license is unclear or absent — the risk that was explicitly evaluated and
accepted (or not) before use. Nothing here is bundled or linked against
silently; every entry below was a deliberate, documented decision.
The built app also includes a concise bilingual copy at
`Resources/ThirdParty/ACKNOWLEDGEMENTS.txt`, displayed from **حول التطبيق**;
this file remains the complete legal and provenance record.

## Code dependencies

### Adhan Swift
- **Source**: https://github.com/batoulapps/adhan-swift
- **License**: MIT
- **Used for**: offline Islamic prayer time calculation (all calculation
  methods including Umm al-Qura, and Asr shadow-length calculation via its
  `Madhab` enum).
- **Status**: Clean. Actively maintained, zero dependencies of its own,
  fully compatible with MIT and with a fully offline, sandboxed app.
  The full upstream MIT notice is bundled as
  `Resources/ThirdParty/Adhan-LICENSE.txt`.

### DynamicNotchKit — adapted UI source
- **Source**: https://github.com/MrKai77/DynamicNotchKit
- **Verified revision**: `cd0b3e52d537db115ad3a9d89601f20e0bee8d27`.
- **License**: MIT, copyright (c) 2025 Kai Azim. The complete upstream
  notice is bundled as `Resources/ThirdParty/DynamicNotchKit-LICENSE.txt`.
- **Used for**: the concave-top path in `App/UI/Notch/NotchShape.swift`,
  and the rounded floating-card presentation and slide-animation approach
  adapted for Ayah's solid-black non-notch popup. The relevant upstream
  files are `Views/NotchShape.swift`, `Views/NotchlessView.swift`, and
  `DynamicNotch/DynamicNotchStyle.swift` under `Sources/DynamicNotchKit/`.
  Ayah adapts these locally; DynamicNotchKit is not a linked framework or
  package dependency.
- **Provenance correction**: the shape was previously described in its
  source comment as ported from boring.notch, while this document claimed
  no code had been copied. Its `path(in:)` matches both boring.notch and
  the original DynamicNotchKit implementation, ignoring whitespace.
  boring.notch itself credits DynamicNotchKit. The attribution and license
  for this reused shape are now explicitly recorded against the verified
  original MIT source. This does not establish the provenance or licensing
  of unrelated code in either project.

## Bundled data resources

### Quran text — King Fahd Glorious Quran Printing Complex (KFGQPC)
- **Source**: https://qurancomplex.gov.sa/quran-dev/ (official KFGQPC
  Software Developers Platform), package `UthmanicHafs_v2-0.zip`.
- **What's bundled**: Quran text (Hafs narration, Uthmanic script,
  Madinah Mushaf-compatible), downloaded directly from the official
  platform and transformed into `quran.sqlite` by `Scripts/import_quran`.
- **License**: **None published.** Re-verified 2026-08-22 (see the Quran
  supply-chain hardening pass in `CLAUDE.md`), going further than the
  original check: the quran-dev platform page itself, KFGQPC's contact
  page, and — new this pass — the downloaded package's own `read.me` file
  plus its raw CSV/SQL/JSON/XML exports were all checked directly for any
  embedded license or terms text. None exists anywhere; the platform
  offers the data for free download with no registration requirement, but
  publishes no terms-of-use or redistribution policy for the *text*
  specifically (only a privacy policy and an unrelated printed-Mushaf
  sales policy exist as footer links). A generic "all rights reserved"
  copyright notice does not, on its own, grant redistribution rights.
- **Risk accepted**: After this gap was identified and explained, the
  project maintainer made an informed decision to proceed using this
  official KFGQPC data despite the absence of a published redistribution
  license, accepting the residual legal risk — reaffirmed 2026-08-22 after
  the deeper re-verification above produced the same conclusion. This
  mirrors common informal practice among Quran applications but is not
  textually authorized by KFGQPC.
- **Mitigation / path forward**: Contributors are encouraged to help
  pursue explicit written permission from KFGQPC via their contact page
  (https://qurancomplex.gov.sa/contact/). The Quran import pipeline
  (`Scripts/import_quran`) is deliberately designed so the text source can
  be swapped — for example to Tanzil.net, which publishes the same
  Uthmani Hafs text under an explicit, unambiguous license permitting
  verbatim redistribution with attribution — without requiring an
  architecture rewrite, in case this position needs to change in the
  future.

### KFGQPC Uthmanic Hafs font — King Fahd Glorious Quran Printing Complex
- **Source**: same official platform and package as the text above;
  `Resources/Fonts/uthmanic_hafs_v20.ttf` is the exact font file from
  inside `UthmanicHafs_v2-0.zip` — confirmed 2026-08-22 by re-downloading
  the official package fresh and comparing SHA-256 of the two files
  (`d560bbbc7a90a4f4d416d206a5ac48bd8a1ad00273d64d232f16ca54941bd041`):
  byte-for-byte identical.
- **License**: **Licensed — an End-User License Agreement is embedded
  directly in the font file's own metadata** (readable via `strings` on
  the `.ttf`; not present on the download webpage, which is why the
  earlier check of the website alone missed it). In full:

  > "ELECTRONIC END-USER LICENSE AGREEMENT. By installing this Font You
  > accept all the terms and conditions of this Agreement. Copyright (c)
  > 2010 by King Fahd Glorious Quran Printing Complex (KFGQPC), AlMadinah
  > AlMunawarrah, Kingdom of Saudi Arabia. All Rights Reserved. KFGQPC
  > retains full title and ownership of this Typeface both as artwork and
  > font software. This Agreement does not grant you any intellectual
  > property rights in the Font. Permission is hereby granted, Free of
  > Cost, to any person obtaining a copy of this Font accompanying this
  > license, the rights to Use, Copy, Distribute, subject to the following
  > conditions: 1. The Font Software cannot be Sold, Modified, Altered,
  > Translated, Reverse Engineered, Decompiled, Disassembled, Reproduced
  > or Attempted to discover the Source Code of this Font in no means. 2.
  > The Font Software is provided "AS IS"..."

  Ayah bundles this file unmodified and registers it at runtime via
  `CTFontManagerRegisterFontsForURL` — squarely within the "Use, Copy,
  Distribute" grant, and Ayah never sells, modifies, or reverse-engineers
  the font.
- **Status**: Clean, under the embedded EULA above. This corrects the
  earlier "None published / risk accepted" entry for the font, which
  reflected only a check of the download webpage and missed the license
  text embedded in the font file itself.

### Location dataset — GeoNames
- **Source**: https://www.geonames.org (data dumps at
  download.geonames.org/export/dump/)
- **License**: Creative Commons Attribution 4.0 (CC BY 4.0)
- **Used for**: the bundled offline city → coordinates → timezone lookup
  used for manual city selection in prayer time calculation.
- **Status**: Clean. Redistribution is explicitly permitted with
  attribution. Ayah bundles only a filtered subset — 4,659 cities across
  49 Muslim-majority countries, kept where population ≥ 15,000 or the
  city is a national capital — not the full world dataset. See
  `Resources/GeoNames/SOURCE.md` for the exact filter and country list.
  Attribution: "Geographic data © GeoNames.org contributors, CC BY 4.0."
  The attribution and license link are bundled as
  `Resources/ThirdParty/GeoNames-NOTICE.txt`.

## Other projects studied

- **NotchDrop** — https://github.com/Lakr233/NotchDrop — MIT license.
  Studied for windowing techniques; no identified source adaptation.
- **boring.notch** — https://github.com/TheBoredTeam/boring.notch — GPL-3.0.
  Studied for notch geometry and windowing. Ayah's earlier shape comment
  named this project as its source; the matching shape is also credited
  there to DynamicNotchKit, whose original MIT source is recorded above.
  Do not assume other boring.notch code shares that license. A broader
  exact-token comparison found no other substantial matches in Ayah's
  application/package Swift sources; this is a similarity check, not proof
  of independent authorship.
- **NotchNook** — closed source, commercial; no source code reused.

## Summary table

| Resource | License | Redistribution status |
|---|---|---|
| Adhan Swift | MIT | Clean |
| DynamicNotchKit UI adaptations | MIT | Copyright and license notice bundled |
| GeoNames location data (filtered subset) | CC BY 4.0 | Clean, attribution required |
| KFGQPC Quran text (Hafs, Uthmanic) | None published | **Risk accepted, documented** |
| KFGQPC Uthmanic Hafs font | Licensed (embedded EULA) | **Clean** |
