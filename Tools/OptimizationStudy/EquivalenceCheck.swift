// SPDX-License-Identifier: Apache-2.0
import Foundation
private enum DatePatterns {
    static let compiled: Result<[String: NSRegularExpression], Error> = Result {
        let sources: [String: String] = [
            "day": #"\b(sun|mon|tue|wed|thu|fri|sat)[^-/0-9\s]*"#,
            "time": #"((?<![0-9])[0-9]+\s*(?:(?::\s*[0-9]+(?:\s*:\s*[0-9]+(?:[,.][0-9]*)?)?|h(?:\s*[0-9]+m?(?:\s*[0-9]+s?)?)?)(?:\s*[ap](?:m\b|\.m\.))?|[ap](?:m\b|\.m\.)))(?:\s*((?:gmt|utc?)?[-+][0-9]+(?:[,.:][0-9]+(?::[0-9]+)?)?|(?-i:[[:alpha:].\s]+)(?:standard|daylight)\stime\b|(?-i:[[:alpha:]]+)(?:\sdst)?\b))?"#,
            "eu": #"('?(?<![0-9])[0-9]+)[^-0-9\s]*\s*(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[^-0-9\s']*(?:\s*(?:\b(c(?:e|\.e\.)|b(?:ce|\.c\.e\.)|a(?:d|\.d\.)|b(?:c|\.c\.))(?!(?<!\.)[a-z]))?\s*('?-?[0-9]+(?:(?:st|nd|rd|th)\b)?))?"#,
            "us": #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[^-0-9\s']*\s*('?[0-9]+)[^-0-9\s']*(?:\s*+,?\s*+(c(?:e|\.e\.)|b(?:ce|\.c\.e\.)|a(?:d|\.d\.)|b(?:c|\.c\.))?\s*('?-?[0-9]+))?"#,
            "iso": #"('?[-+]?(?<![0-9])[0-9]+)-([0-9]+)-('?-?[0-9]+)"#,
            "iso21": #"\b([0-9]{2}|[0-9]{4})?-?w([0-9]{2})(?:-?([0-9]))?\b"#,
            "iso22": #"-w-([0-9])\b"#,
            "iso23": #"--([0-9]{2})?-([0-9]{2})\b"#,
            "iso24": #"--([0-9]{2})([0-9]{2})?\b"#,
            "iso25Guard": #"[,.]([0-9]{2}|[0-9]{4})-[0-9]{3}\b"#,
            "iso25": #"\b([0-9]{2}|[0-9]{4})-([0-9]{3})\b"#,
            "iso26Guard": #"[0-9]-[0-9]{3}\b"#,
            "iso26": #"\b-([0-9]{3})\b"#,
            "jis": #"\b([mtshr])([0-9]+)\.([0-9]+)\.([0-9]+)"#,
            "vms11": #"('?-?(?<![0-9])[0-9]+)-(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[^-/.]*-('?-?[0-9]+)"#,
            "vms12": #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[^-/.]*-('?-?[0-9]+)(?:-('?-?[0-9]+))?"#,
            "sla": #"('?-?(?<![0-9])[0-9]+)/\s*('?[0-9]+)(?:[^0-9]\s*('?-?[0-9]+))?"#,
            "dot": #"('?-?(?<![0-9])[0-9]+)\.\s*('?[0-9]+)\.\s*('?-?[0-9]+)"#,
            "year": #"'([0-9]+)\b"#,
            "mon": #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\S*"#,
            "mday": #"((?<![0-9])[0-9]+)(st|nd|rd|th)\b"#,
            "ddd": #"([-+]?)((?<![0-9])[0-9]{2,14})(?:\s*t?\s*([0-9]{2,6})?(?:[,.]([0-9]*))?)?(?:\s*(z\b|[-+][0-9]{1,4}\b|\[[-+]?[0-9][^\]]*\]))?"#,
            "bc": #"\b(bc\b|bce\b|b\.c\.|b\.c\.e\.)"#,
            "frag": #"\A\s*([0-9]{1,2})\s*\z"#,
            "timeFields": #"\A([0-9]+)h?(?:\s*:?\s*([0-9]+)m?(?:\s*:?\s*([0-9]+)(?:[,.]([0-9]+))?s?)?)?(?:\s*([ap])(?:m\b|\.m\.))?"#,
            "normalize": #"[^-+',./:@[:alnum:]\[\]]+"#,
        ]
        return try sources.mapValues { try NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }
}

    /// Preserve the regex normalizer's run replacement for ASCII inputs.
    /// Unicode classification continues through the pinned ICU expression.
private func normalized(_ source: String, using regex: NSRegularExpression) -> String {
        var bytes = [UInt8]()
        bytes.reserveCapacity(source.utf8.count)
        var replacing = false
        var changed = false
        for byte in source.utf8 {
            guard byte < 128 else {
                return regex.stringByReplacingMatches(in: source,
                    range: NSRange(source.startIndex..., in: source), withTemplate: " ")
            }
            switch byte {
            case 48...57, 65...90, 97...122, 45, 43, 39, 44, 46, 47, 58, 64, 91, 93:
                bytes.append(byte)
                replacing = false
            default:
                if !replacing { bytes.append(32) }
                replacing = true
                changed = true
            }
        }
        return changed ? String(decoding: bytes, as: UTF8.self) : source
    }


@main struct EquivalenceCheck {
 static func main() throws {
  let patterns = try DatePatterns.compiled.get(), regex = patterns["normalize"]!
  var inputs = [String]()
  for a in 0..<128 { inputs.append(String(UnicodeScalar(a)!)) }
  for a in 0..<128 { for b in 0..<128 { inputs.append(String(UnicodeScalar(a)!) + String(UnicodeScalar(b)!)) } }
  let unicode = ["é", "e\u{301}", "😀", "中", "١", "𝟙", "\u{a0}", "\u{2028}", "\u{200d}", "\0", "\r\n"]
  let dates = ["2024-02-03T04:05:06.123456789+05:30", "Sat, 03 Feb 2024 04:05:06 +0530", "not a date", "", "[-+',./:@]", String(repeating: "! ", count: 64), String(repeating: "a", count: 129)]
  for u in unicode { for d in dates { inputs += [u+d, d+u, u+d+u, d+u+d] } }
  var state: UInt64 = 0x4c6971756964
  for _ in 0..<1024 {
   var value = ""
   for _ in 0..<32 { state = state &* 6364136223846793005 &+ 1442695040888963407
    if state & 7 == 0 { value += unicode[Int((state >> 8) % UInt64(unicode.count))] }
    else { value.unicodeScalars.append(UnicodeScalar(Int((state >> 8) % 128))!) }
   }
   inputs.append(value)
  }
  var matches = 0, checksum: UInt64 = 14695981039346656037
  for source in inputs {
   let oldRange = NSRange(source.startIndex..., in: source), newRange = NSRange(location: 0, length: source.utf16.count)
   guard oldRange == newRange else { fatalError("Range mismatch") }
   let reference = regex.stringByReplacingMatches(in: source, range: oldRange, withTemplate: " ")
   guard normalized(source, using: regex).utf8.elementsEqual(reference.utf8) else { fatalError("Normalization mismatch: \(source.debugDescription)") }
   for byte in reference.utf8 { checksum = (checksum ^ UInt64(byte)) &* 1099511628211 }
   for name in patterns.keys.sorted() {
    let expression = patterns[name]!, a = expression.firstMatch(in: source, range: oldRange), b = expression.firstMatch(in: source, range: newRange)
    guard (a == nil) == (b == nil), a?.numberOfRanges == b?.numberOfRanges else { fatalError("Match mismatch") }
    if let a, let b { for i in 0..<a.numberOfRanges { guard a.range(at: i) == b.range(at: i) else { fatalError("Capture mismatch") } } }
    matches += 1
   }
  }
  let result: [String: Any] = ["status": "passed", "inputs": inputs.count, "patterns": patterns.count, "matchingChecks": matches, "normalizationFNV1a": String(checksum, radix: 16)]
  let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]);try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]));print(String(decoding: data, as: UTF8.self))
 }
}
