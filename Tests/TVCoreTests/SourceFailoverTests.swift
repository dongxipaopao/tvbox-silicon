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

@Test func episodeNumbersAreParsed() {
    #expect(SourceFailover.number(of: "第12集") == 12)
    #expect(SourceFailover.number(of: "第十二集") == 12)
    #expect(SourceFailover.number(of: "第二十集") == 20)
    #expect(SourceFailover.number(of: "EP05") == 5)
    #expect(SourceFailover.number(of: "05") == 5)
    #expect(SourceFailover.number(of: "1080P") == nil)
    #expect(SourceFailover.number(of: "HD国语") == nil)
}

@Test func extrasAreNeverMatched() {
    #expect(SourceFailover.isExtra("第3集预告"))
    #expect(SourceFailover.isExtra("特别篇"))
    #expect(SourceFailover.isExtra("SP1"))
    #expect(!SourceFailover.isExtra("第3集"))
    #expect(SourceFailover.place(current: "第3集预告", currentCount: 10, other: ["第1集", "第2集", "第3集"]) == nil)
}

@Test func matchPicksTheSameNumberNotTheSameIndex() {
    // The other source starts with a trailer: index 2 there is episode 2, not episode 3.
    let other = ["预告", "第1集", "第2集", "第3集", "第4集"]
    #expect(SourceFailover.place(current: "第3集", currentCount: 4, other: other) == 3)
}

@Test func matchRefusesWhenItIsNotSure() {
    // Missing episode, a duplicate number, or a name without a number: no automatic switch.
    #expect(SourceFailover.place(current: "第5集", currentCount: 6, other: ["第1集", "第2集", "第3集"]) == nil)
    #expect(SourceFailover.place(current: "第2集", currentCount: 3, other: ["第1集", "第2集", "第2集 加长版"]) == nil)
    #expect(SourceFailover.place(current: "正片", currentCount: 5, other: ["第1集", "第2集"]) == nil)
}

@Test func filmMatchesOnlyAFilm() {
    #expect(SourceFailover.place(current: "正片", currentCount: 1, other: ["HD"]) == 0)
    #expect(SourceFailover.place(current: "正片", currentCount: 1, other: ["HD", "预告"]) == nil)
    #expect(SourceFailover.place(current: "正片", currentCount: 1, other: ["预告"]) == nil)
}
