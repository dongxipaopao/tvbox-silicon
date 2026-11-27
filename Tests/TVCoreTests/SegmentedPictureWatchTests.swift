import Foundation
import Testing
@testable import TVCore

/// When an HLS stream that plays sound with no drawn frame is repackaged (#585). The old rule repackaged after four
/// half-second checks of sound (2s); a 4K HEVC stream whose first frame came later lost it to the repackage.
@Suite struct SegmentedPictureWatchTests {
    /// The checks that were enough to repackage before: four while playing.
    private static let oldChecks = 4

    private func checks(_ watch: inout SegmentedPictureWatch, _ count: Int, playing: Bool = true, frameDrawn: Bool = false, playsAsListed: Bool = false) -> SegmentedPictureWatch.Outcome {
        var outcome = SegmentedPictureWatch.Outcome.waiting
        for _ in 0..<count { outcome = watch.check(playing: playing, frameDrawn: frameDrawn, playsAsListed: playsAsListed) }
        return outcome
    }

    /// The old rule's trigger point is now only a wait.
    @Test func theOldTwoSecondTriggerOnlyWaits() {
        #expect(SegmentedPictureWatch.playChecks > Self.oldChecks)
        var watch = SegmentedPictureWatch()
        #expect(checks(&watch, Self.oldChecks) == .waiting)
    }

    /// The regression: a first frame after the old trigger (3s) and before the new one. The old rule had already
    /// repackaged by then (check 4); now the frame is accepted and nothing is replaced.
    @Test func aFirstFrameAfterTheOldTriggerIsAcceptedNotRepackaged() {
        var watch = SegmentedPictureWatch()
        var outcomes: [SegmentedPictureWatch.Outcome] = []
        for _ in 0..<6 { outcomes.append(watch.check(playing: true, frameDrawn: false, playsAsListed: false)) }
        #expect(!outcomes.contains(.repackage))
        #expect(watch.check(playing: true, frameDrawn: true, playsAsListed: false) == .accepted)
    }

    @Test func theLastCheckBeforeTheLimitStillWaits() {
        var watch = SegmentedPictureWatch()
        #expect(checks(&watch, SegmentedPictureWatch.playChecks - 1) == .waiting)
        // A frame on the very last check wins over the repackage.
        #expect(watch.check(playing: true, frameDrawn: true, playsAsListed: false) == .accepted)
    }

    @Test func neverAFrameRepackagesAtTheLimit() {
        var watch = SegmentedPictureWatch()
        #expect(checks(&watch, SegmentedPictureWatch.playChecks - 1) == .waiting)
        #expect(checks(&watch, 1) == .repackage)
    }

    /// No video track listed at all is not a wait without end: it counts like sound with no frame.
    @Test func anEmptyTrackListIsBounded() {
        var watch = SegmentedPictureWatch()
        #expect(checks(&watch, SegmentedPictureWatch.playChecks, playsAsListed: false) == .repackage)
    }

    @Test func aListedNonHEVCPictureIsAcceptedAtOnce() {
        var watch = SegmentedPictureWatch()
        #expect(watch.check(playing: true, frameDrawn: false, playsAsListed: true) == .accepted)
    }

    /// A pause or a stall starts the count again, so it can't add up to a repackage across stops.
    @Test func aStallStartsTheCountAgain() {
        var watch = SegmentedPictureWatch()
        #expect(checks(&watch, SegmentedPictureWatch.playChecks - 1) == .waiting)
        #expect(checks(&watch, 5, playing: false) == .waiting)
        #expect(watch.played == 0)
        #expect(checks(&watch, SegmentedPictureWatch.playChecks - 1) == .waiting)
        #expect(checks(&watch, 1) == .repackage)
    }

    /// Each playback owns its watch (it lives in that playback's task), so a new item starts from zero.
    @Test func aNewPlaybackStartsFromZero() {
        var first = SegmentedPictureWatch()
        _ = checks(&first, SegmentedPictureWatch.playChecks - 1)
        let second = SegmentedPictureWatch()
        #expect(second.played == 0)
    }
}
