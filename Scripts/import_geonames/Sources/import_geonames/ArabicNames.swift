import Foundation

/// Picks one Arabic display name per `geonameid` out of GeoNames'
/// `alternateNamesV2` dump, pre-filtered to `isolanguage == "ar"` rows
/// (see `CLAUDE.md`'s "Re-run the GeoNames import pipeline" section for
/// the exact `awk` prep command — the full dump is 19M rows worldwide,
/// only ~300K of which are Arabic-tagged, so pre-filtering keeps this
/// importer from having to scan the whole thing).
///
/// GeoNames' own column docs (`alternateNamesV2.txt` format):
/// alternateNameId, geonameid, isolanguage, alternate name,
/// isPreferredName, isShortName, isColloquial, isHistoric, from, to.
///
/// Many cities have multiple Arabic alternates (e.g. Sharjah has
/// "الشارقة", "إمارة الشارقة" [Emirate of Sharjah], and "مدينة الشارقة"
/// [City of Sharjah]) — this picks, per city: historic names excluded
/// entirely; then GeoNames' own `isPreferredName` flag if any candidate
/// has it; else the shortest remaining non-colloquial name, which in
/// practice reliably favors the plain proper name ("الشارقة") over
/// descriptive/administrative variants ("إمارة الشارقة").
///
/// **Known caveat, not silently glossed over**: GeoNames' `isolanguage`
/// tagging isn't perfectly curated — a small number of entries for
/// countries that share Arabic-derived scripts (observed for
/// Afghanistan, e.g. "گردیز" for Gardez) are tagged `ar` despite being
/// Dari/Pashto text using Perso-Arabic letters (گ) that don't exist in
/// the Arabic alphabet. Filtering these out would need per-entry
/// language expertise beyond what this importer can reasonably do —
/// accepted as a minor, low-volume imprecision inherited from the
/// upstream data, the same way §5's KFGQPC licensing gap and other
/// upstream-data caveats are documented rather than hidden.
enum ArabicNames {
    private struct Candidate {
        let name: String
        let isPreferred: Bool
        let isColloquial: Bool
    }

    /// `path` is optional — if `nil`, every city gets `nameArabic == nil`
    /// rather than the importer refusing to run. Arabic-name enrichment
    /// is a display-quality improvement, not a correctness requirement
    /// the way Quran data integrity (§8) is.
    static func load(path: String?) -> [Int: String] {
        guard let path, let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return [:]
        }

        var candidatesByID: [Int: [Candidate]] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 8, let geonameID = Int(fields[1]) else { continue }

            let name = fields[3]
            let isPreferred = fields[4] == "1"
            let isColloquial = fields[6] == "1"
            let isHistoric = fields[7] == "1"
            guard !isHistoric, !name.isEmpty else { continue }

            candidatesByID[geonameID, default: []].append(
                Candidate(name: name, isPreferred: isPreferred, isColloquial: isColloquial)
            )
        }

        var best: [Int: String] = [:]
        for (geonameID, candidates) in candidatesByID {
            let preferred = candidates.filter(\.isPreferred)
            let pool = preferred.isEmpty ? candidates : preferred
            let nonColloquial = pool.filter { !$0.isColloquial }
            let finalPool = nonColloquial.isEmpty ? pool : nonColloquial
            guard let chosen = finalPool.min(by: { $0.name.count < $1.name.count }) else { continue }
            best[geonameID] = chosen.name
        }
        return best
    }
}
