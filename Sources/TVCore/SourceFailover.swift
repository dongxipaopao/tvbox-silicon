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

    /// The other source's episode at the same place is the same episode only when its list is about as long. A list
    /// that is much shorter or longer is another cut or season, and playing its episode would be the wrong one.
    public static func listsLineUp(index: Int, currentCount: Int, otherCount: Int) -> Bool {
        guard index >= 0, index < otherCount, currentCount > 0 else { return false }
        if currentCount == 1 || otherCount == 1 { return currentCount == otherCount }
        return abs(currentCount - otherCount) <= 2
    }
}
