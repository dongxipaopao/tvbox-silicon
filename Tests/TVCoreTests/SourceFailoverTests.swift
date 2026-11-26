import Testing
@testable import TVCore

private func entry(_ id: String, _ site: String, season: Int = 1) -> SourceFailover.Entry {
    SourceFailover.Entry(id: id, siteKey: site, season: season)
}

@Test func failoverSkipsCurrentAndFailedAndOtherSeasons() {
    let current = entry("a1", "A")
    let all = [current, entry("a2", "A"), entry("b1", "B"), entry("c1", "C"), entry("d1", "D", season: 2)]
    #expect(SourceFailover.order(all, current: current, failed: ["c1"], limit: 5) == ["b1", "a2"])
}

@Test func failoverPrefersOtherSitesAndHonoursLimit() {
    let current = entry("a1", "A")
    let all = [current, entry("a2", "A"), entry("b1", "B"), entry("b2", "B"), entry("c1", "C")]
    #expect(SourceFailover.order(all, current: current, failed: [], limit: 2) == ["b1", "c1"])
    #expect(SourceFailover.order(all, current: current, failed: [], limit: 0).isEmpty)
}

@Test func failoverEndsWhenEverythingFailed() {
    let current = entry("a1", "A")
    let all = [current, entry("b1", "B")]
    #expect(SourceFailover.order(all, current: current, failed: ["b1"], limit: 3).isEmpty)
}

@Test func failoverEpisodeListsMustLineUp() {
    #expect(SourceFailover.listsLineUp(index: 4, currentCount: 30, otherCount: 31))
    #expect(!SourceFailover.listsLineUp(index: 4, currentCount: 30, otherCount: 12))
    #expect(!SourceFailover.listsLineUp(index: 30, currentCount: 30, otherCount: 30))
    #expect(SourceFailover.listsLineUp(index: 0, currentCount: 1, otherCount: 1))
    #expect(!SourceFailover.listsLineUp(index: 0, currentCount: 1, otherCount: 20))
}
