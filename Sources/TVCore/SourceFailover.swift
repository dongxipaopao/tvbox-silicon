import Foundation

/// Which other sources to try, and whether their episode list lines up, when the source showing can't play an episode.
/// Bounded on purpose: a source that already failed is never tried again for the title, a different site is tried
/// before another result of the same site, only the same season counts, and a try takes at most `limit` sources.
public enum SourceFailover {
    public struct Entry: Sendable, Equatable {
        public let id: String
        public let siteKey: String
        public let season: Int
        public init(id: String, siteKey: String, season: Int) {
            self.id = id; self.siteKey = siteKey; self.season = season
        }
    }

    /// The ids to try, in order: not the current one, not one that failed, the current one's season only, other sites
    /// first (each site once), then the rest, at most `limit`.
    public static func order(_ entries: [Entry], current: Entry, failed: Set<String>, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let usable = entries.filter { $0.id != current.id && !failed.contains($0.id) && $0.season == current.season }
        var picked: [String] = []
        var sites = Set<String>([current.siteKey])
        for entry in usable where sites.insert(entry.siteKey).inserted {
            picked.append(entry.id)
            if picked.count == limit { return picked }
        }
        for entry in usable where !picked.contains(entry.id) {
            picked.append(entry.id)
            if picked.count == limit { break }
        }
        return picked
    }

    private static let extras = try! NSRegularExpression(
        pattern: #"(预告|特别篇|特别|花絮|番外|彩蛋|总集篇|幕后|纪录|trailer|preview|teaser|\bOVA\b|\bSP\d*\b|\bPV\d*\b|making of)"#,
        options: [.caseInsensitive])
    private static let patterns: [NSRegularExpression] = [
        #"第\s*([0-9]{1,4}|[一二三四五六七八九十百零两]{1,5})\s*[集话話期章]"#,
        #"(?:\bep?|episode)\s*\.?\s*([0-9]{1,4})(?![0-9])"#,
        #"^\s*([0-9]{1,4})\s*$"#,
        #"^\s*([0-9]{1,4})(?![0-9pPkK])"#,
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    /// A trailer, special, extra or the like: never the episode a viewer asked for, and never a stand-in for one.
    public static func isExtra(_ name: String) -> Bool {
        extras.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) != nil
    }

    /// The episode number a name carries (第12集, 第十二集, EP12, E12, 12, 12 [HD]), nil when it carries none.
    public static func number(of name: String) -> Int? {
        let range = NSRange(name.startIndex..., in: name)
        for pattern in patterns {
            guard let match = pattern.firstMatch(in: name, range: range), let r = Range(match.range(at: 1), in: name) else { continue }
            let text = String(name[r])
            if let n = Int(text) { return n }
            return chineseNumber(text)
        }
        return nil
    }

    private static func chineseNumber(_ text: String) -> Int? {
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        var total = 0, current = 0
        for ch in text {
            if let d = digits[ch] { current = d }
            else if ch == "十" { total += (current == 0 ? 1 : current) * 10; current = 0 }
            else if ch == "百" { total += (current == 0 ? 1 : current) * 100; current = 0 }
            else { return nil }
        }
        return total + current
    }

    /// The place in `other` of the same episode as `current`, or nil when it can't be told for sure: the episode must
    /// carry a number, be no trailer or special, and be the only non-extra episode of `other` with that number (two
    /// would be two cuts or parts). A one-episode title (a film) matches a one-episode list. Nil means no automatic
    /// switch: the viewer chooses the source.
    public static func match(current: String, other: [String]) -> Int? {
        guard !isExtra(current) else { return nil }
        if let n = number(of: current) {
            let hits = other.indices.filter { !isExtra(other[$0]) && number(of: other[$0]) == n }
            return hits.count == 1 ? hits[0] : nil
        }
        return nil
    }

    /// The film case: both sides have exactly one entry and neither is an extra.
    public static func matchesSingle(current: String, other: [String], currentCount: Int) -> Int? {
        guard currentCount == 1, other.count == 1, !isExtra(current), !isExtra(other[0]) else { return nil }
        return 0
    }

    public static func place(current: String, currentCount: Int, other: [String]) -> Int? {
        match(current: current, other: other) ?? matchesSingle(current: current, other: other, currentCount: currentCount)
    }
}
