    /// Preserve the regex normalizer's run replacement for ASCII inputs.
    /// Unicode classification continues through the pinned ICU expression.
    private static func normalized(_ source: String, using regex: NSRegularExpression) -> String {
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
