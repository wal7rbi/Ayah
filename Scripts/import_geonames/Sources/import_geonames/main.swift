import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("import_geonames: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

struct Options {
    var tsvPath: String
    var outDir: String
    var sourceURL: String
    var sourceDate: String
    var minPopulation: Int
    var arabicNamesPath: String?
}

func parseOptions() -> Options {
    var raw: [String: String] = [:]
    var args = CommandLine.arguments.dropFirst().makeIterator()
    while let key = args.next() {
        guard key.hasPrefix("--"), let value = args.next() else {
            fail("bad argument '\(key)' — expected --flag value pairs")
        }
        raw[String(key.dropFirst(2))] = value
    }
    func require(_ name: String) -> String {
        guard let v = raw[name] else { fail("missing required --\(name)") }
        return v
    }
    return Options(
        tsvPath: require("tsv"),
        outDir: require("out-dir"),
        sourceURL: require("source-url"),
        sourceDate: require("source-date"),
        minPopulation: raw["min-population"].flatMap(Int.init) ?? 15000,
        arabicNamesPath: raw["arabic-names"]
    )
}

// GeoNames' tab-separated "cities1000" export columns — see
// https://download.geonames.org/export/dump/readme.txt. Field 7 is the
// feature code ("PPLC" = capital of a political entity); field 14 is
// population.
let geonamesColumnCount = 19
let colGeonameID = 0
let colName = 1
let colLatitude = 4
let colLongitude = 5
let colFeatureCode = 7
let colCountryCode = 8
let colPopulation = 14
let colTimezone = 17

let options = parseOptions()

guard let content = try? String(contentsOfFile: options.tsvPath, encoding: .utf8) else {
    fail("could not read TSV at \(options.tsvPath)")
}

let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
guard !lines.isEmpty else { fail("TSV is empty") }

let arabicNames = ArabicNames.load(path: options.arabicNamesPath)

var cities: [CityRecord] = []
var seenIDs = Set<Int>()

for (lineIndex, line) in lines.enumerated() {
    let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
    guard fields.count == geonamesColumnCount else {
        fail("line \(lineIndex + 1) has \(fields.count) fields, expected \(geonamesColumnCount)")
    }

    let countryCode = fields[colCountryCode]
    guard muslimMajorityCountryCodes.contains(countryCode) else { continue }

    guard let population = Int(fields[colPopulation]) else {
        fail("line \(lineIndex + 1): non-numeric population '\(fields[colPopulation])'")
    }
    let isCapital = fields[colFeatureCode] == "PPLC"
    guard population >= options.minPopulation || isCapital else { continue }

    guard let geonameID = Int(fields[colGeonameID]) else {
        fail("line \(lineIndex + 1): non-numeric geonameid '\(fields[colGeonameID])'")
    }
    guard let latitude = Double(fields[colLatitude]), let longitude = Double(fields[colLongitude]) else {
        fail("line \(lineIndex + 1): non-numeric coordinates")
    }
    guard (-90...90).contains(latitude), (-180...180).contains(longitude) else {
        fail("line \(lineIndex + 1): coordinates out of range (\(latitude), \(longitude))")
    }
    let name = fields[colName]
    let timezone = fields[colTimezone]
    guard !name.isEmpty, !timezone.isEmpty else {
        fail("line \(lineIndex + 1) (geonameid \(geonameID)) has an empty name or timezone")
    }
    guard seenIDs.insert(geonameID).inserted else {
        fail("duplicate geonameid \(geonameID) at line \(lineIndex + 1)")
    }

    cities.append(CityRecord(
        geonameID: geonameID,
        name: name,
        nameArabic: arabicNames[geonameID],
        countryCode: countryCode,
        latitude: latitude,
        longitude: longitude,
        timezone: timezone,
        population: population
    ))
}

guard !cities.isEmpty else { fail("no cities matched the country/population filter") }
let arabicNameCount = cities.filter { $0.nameArabic != nil }.count

try? FileManager.default.createDirectory(atPath: options.outDir, withIntermediateDirectories: true)

let dbPath = (options.outDir as NSString).appendingPathComponent("cities_filtered.sqlite")
let isoFormatter = ISO8601DateFormatter()
let generatedAt = isoFormatter.string(from: Date())

do {
    try writeCitiesDatabase(
        path: dbPath,
        cities: cities,
        meta: [
            ("source_url", options.sourceURL),
            ("source_date", options.sourceDate),
            ("min_population", String(options.minPopulation)),
            ("country_count", String(muslimMajorityCountryCodes.count)),
            ("arabic_name_count", String(arabicNameCount)),
            ("generated_at", generatedAt),
        ]
    )
} catch {
    fail("failed writing database: \(error)")
}

let countryList = muslimMajorityCountryCodes.sorted().joined(separator: ", ")
let sourceMD = """
# GeoNames city dataset source

- **Upstream**: GeoNames `cities1000` dump (cities with population ≥ 1000,
  plus all admin-division seats and national capitals regardless of
  population)
- **Downloaded from**: \(options.sourceURL)
- **Export date**: \(options.sourceDate)
- **License**: CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/) —
  attribution required, redistribution explicitly permitted. Attribution:
  "This app includes data from GeoNames (https://www.geonames.org),
  licensed under CC BY 4.0."
- **Imported**: \(generatedAt)
- **Filter**: country code in the "Muslim-majority countries" v1 set
  (\(muslimMajorityCountryCodes.count) countries — see
  `Scripts/import_geonames/Sources/import_geonames/MuslimMajorityCountries.swift`
  for the list and its criterion) AND (population ≥ \(options.minPopulation)
  OR the city is a national capital), so the bundled dataset stays a
  "tens to low hundreds of KB" city-picker list (ARCHITECTURE.md §12)
  rather than every populated place GeoNames knows about.
- **Row count**: \(cities.count) cities
- **Countries included**: \(countryList)
- **Arabic names**: \(arabicNameCount) of \(cities.count) cities (\(Int(100.0 * Double(arabicNameCount) / Double(cities.count)))%) have a `name_arabic` populated from GeoNames' `alternateNamesV2` dump (`isolanguage == "ar"`, historic entries excluded, GeoNames' own `isPreferredName` flag preferred, then the shortest non-colloquial candidate — see `Scripts/import_geonames/Sources/import_geonames/ArabicNames.swift` for the exact selection logic and a documented caveat about occasional Dari/Pashto mistagging for Afghan cities). The remainder have `name_arabic = NULL` and fall back to `name` (GeoNames' primary field, not consistently Arabic-script — e.g. transliterated Latin "Riyadh" for Saudi cities that lack a tagged Arabic alternate).

Generated by `Scripts/import_geonames`. Do not hand-edit
`cities_filtered.sqlite` — re-run the importer against (re-)downloaded
GeoNames exports instead.
"""
try? sourceMD.write(
    toFile: (options.outDir as NSString).appendingPathComponent("SOURCE.md"),
    atomically: true, encoding: .utf8
)

print("Wrote \(cities.count) cities (\(arabicNameCount) with an Arabic name) to \(dbPath)")
