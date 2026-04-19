import Foundation

/// Derives a cleaner search string from a ROM filename (similar in spirit to Playnite’s name cleanup before metadata lookup).
enum RomTitleNormalizer {
    static func searchQuery(fromFileNameStem stem: String) -> String {
        var s = stem
        let patterns = [#"\([^)]*\)"#, #"\[[^\]]*\]"#]
        for p in patterns {
            while let r = s.range(of: p, options: .regularExpression) {
                s.removeSubrange(r)
            }
        }
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
