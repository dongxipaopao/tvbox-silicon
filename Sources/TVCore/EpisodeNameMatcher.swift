import Foundation

/// Reads an episode number out of a title, and folds names to one comparable form (Traditional to Simplified, no case,
/// width, marks or punctuation). Resume-on-the-same-episode and the Douban catalog match names with it.
public enum EpisodeNameMatcher {
    public static func episodeNumber(_ name: String) -> Int? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for pattern in [#"^(?:第\s*)?([0-9]{1,4})\s*(?:[集话話回]|$)"#,
                        #"^ep(?:isode)?\.?\s*([0-9]{1,4})(?:\D|$)"#] {
            if let expression = try? NSRegularExpression(pattern: pattern),
               let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
               let range = Range(match.range(at: 1), in: value), let number = Int(value[range]), number > 0 { return number }
        }
        let expression = try! NSRegularExpression(pattern: #"^第([零〇一二两三四五六七八九十百]+)[集话話回]"#)
        guard let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        let digits: [Character: Int] = ["零":0,"〇":0,"一":1,"二":2,"两":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]
        var total = 0, digit = 0
        for char in value[range] {
            if let number = digits[char] { digit = number }
            else { total += max(1, digit) * (char == "百" ? 100 : 10); digit = 0 }
        }
        let number = total + digit
        return number > 0 ? number : nil
    }

    public static func normalized(_ text: String) -> String {
        let simplified = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
        return String(simplified.folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
