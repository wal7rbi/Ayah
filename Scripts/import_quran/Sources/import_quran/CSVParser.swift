import Foundation

/// Minimal RFC 4180 CSV parser: handles quoted fields, embedded commas,
/// escaped quotes (""), and embedded newlines inside quoted fields.
enum CSVParser {
    static func parse(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false

        let scalars = Array(content.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < scalars.count, scalars[i + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        i += 2
                    } else {
                        inQuotes = false
                        i += 1
                    }
                } else {
                    field.unicodeScalars.append(c)
                    i += 1
                }
                continue
            }

            switch c {
            case "\"":
                inQuotes = true
                i += 1
            case ",":
                row.append(field)
                field = ""
                i += 1
            case "\r":
                i += 1
            case "\n":
                row.append(field)
                field = ""
                rows.append(row)
                row = []
                i += 1
            default:
                field.unicodeScalars.append(c)
                i += 1
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
