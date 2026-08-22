import Foundation

/// The "Muslim-majority countries" filter ARCHITECTURE.md §12 calls for —
/// countries where credible demographic estimates (e.g. Pew Research
/// Center's Global Religious Landscape / Future of World Religions
/// studies) put the Muslim population share above 50%. ISO 3166-1 alpha-2
/// codes, matching GeoNames' own `country code` column.
///
/// This is a v1 starting set, not a claim of completeness — §12 already
/// documents the dataset as an expandable subset. Extending coverage to
/// more countries later means adding codes here and re-running the
/// importer, not an architecture change.
let muslimMajorityCountryCodes: Set<String> = [
    "AF", // Afghanistan
    "AL", // Albania
    "AZ", // Azerbaijan
    "BH", // Bahrain
    "BD", // Bangladesh
    "BA", // Bosnia and Herzegovina
    "BN", // Brunei
    "BF", // Burkina Faso
    "TD", // Chad
    "KM", // Comoros
    "DJ", // Djibouti
    "EG", // Egypt
    "GM", // Gambia
    "GN", // Guinea
    "ID", // Indonesia
    "IR", // Iran
    "IQ", // Iraq
    "JO", // Jordan
    "KZ", // Kazakhstan
    "XK", // Kosovo
    "KW", // Kuwait
    "KG", // Kyrgyzstan
    "LB", // Lebanon
    "LY", // Libya
    "MY", // Malaysia
    "MV", // Maldives
    "ML", // Mali
    "MR", // Mauritania
    "MA", // Morocco
    "NE", // Niger
    "NG", // Nigeria
    "OM", // Oman
    "PK", // Pakistan
    "PS", // Palestine
    "QA", // Qatar
    "SA", // Saudi Arabia
    "SN", // Senegal
    "SL", // Sierra Leone
    "SO", // Somalia
    "SD", // Sudan
    "SY", // Syria
    "TJ", // Tajikistan
    "TN", // Tunisia
    "TR", // Turkey
    "TM", // Turkmenistan
    "AE", // United Arab Emirates
    "UZ", // Uzbekistan
    "EH", // Western Sahara
    "YE", // Yemen
]
