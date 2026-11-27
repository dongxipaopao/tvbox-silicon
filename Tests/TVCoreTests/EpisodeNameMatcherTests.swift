import Testing
@testable import TVCore

@Test func episodeNameMatcherUnderstandsEpisodeNumbersWithoutGuessingSpecialsOrQuality() {
    for (name, expected) in [("1",1), ("第01集",1), ("第十二话",12), ("第两百零一集",201), ("EP. 02",2), ("Episode 3 - title",3)] {
        #expect(EpisodeNameMatcher.episodeNumber(name) == expected)
    }
    for name in ["1080P", "OVA1", "SP1", "S02E01", "正片", "0", "未知"] {
        #expect(EpisodeNameMatcher.episodeNumber(name) == nil)
    }
}

@Test func episodeNameMatcherFoldsTraditionalAndPunctuation() {
    #expect(EpisodeNameMatcher.normalized("葬送的芙莉蓮") == EpisodeNameMatcher.normalized("葬送的芙莉莲"))
}
