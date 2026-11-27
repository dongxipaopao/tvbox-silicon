import Foundation
import Testing
@testable import TVCore

@Suite struct PictureWaitBudgetTests {
    @Test func drawnFrameRevealsAtOnce() {
        var budget = PictureWaitBudget()
        #expect(budget.tick(playing: true, waiting: false, frameDrawn: true, trustedWithoutFrames: false) == .reveal)
    }

    @Test func sixSecondsOfSoundWithNoFrameFails() {
        var budget = PictureWaitBudget()
        var outcome = PictureWaitBudget.Outcome.waiting
        for _ in 0..<PictureWaitBudget.playTicks { outcome = budget.tick(playing: true, waiting: false, frameDrawn: false, trustedWithoutFrames: false) }
        #expect(outcome == .failNoDrawnFrame)
    }

    @Test func trustedHEVCListingRevealsWhenThePlayBudgetTrips() {
        var budget = PictureWaitBudget()
        var outcome = PictureWaitBudget.Outcome.waiting
        for _ in 0..<PictureWaitBudget.playTicks { outcome = budget.tick(playing: true, waiting: false, frameDrawn: false, trustedWithoutFrames: true) }
        #expect(outcome == .reveal)
    }

    @Test func twentySecondsOfBufferingFails() {
        var budget = PictureWaitBudget()
        var outcome = PictureWaitBudget.Outcome.waiting
        for _ in 0..<PictureWaitBudget.stallTicks { outcome = budget.tick(playing: false, waiting: true, frameDrawn: false, trustedWithoutFrames: false) }
        #expect(outcome == .failStalled)
    }

    @Test func pausesSpendNeitherBudget() {
        var budget = PictureWaitBudget()
        for _ in 0..<200 { #expect(budget.tick(playing: false, waiting: false, frameDrawn: false, trustedWithoutFrames: false) == .waiting) }
        // A pause in the middle of playing keeps the budget where it was, so playback can pick it up again.
        for _ in 0..<12 { _ = budget.tick(playing: true, waiting: false, frameDrawn: false, trustedWithoutFrames: false) }
        for _ in 0..<50 { #expect(budget.tick(playing: false, waiting: false, frameDrawn: false, trustedWithoutFrames: false) == .waiting) }
        var outcome = PictureWaitBudget.Outcome.waiting
        for _ in 0..<12 { outcome = budget.tick(playing: true, waiting: false, frameDrawn: false, trustedWithoutFrames: false) }
        #expect(outcome == .failNoDrawnFrame)
    }

    @Test func aDrawnFrameAfterStallsStillReveals() {
        var budget = PictureWaitBudget()
        for _ in 0..<40 { _ = budget.tick(playing: false, waiting: true, frameDrawn: false, trustedWithoutFrames: false) }
        #expect(budget.tick(playing: true, waiting: false, frameDrawn: true, trustedWithoutFrames: false) == .reveal)
    }

    @Test func mixedStallAndPlayStayUnderBudget() {
        var budget = PictureWaitBudget()
        // 10s of buffering then 4s of play: neither budget trips, and no frame means no reveal.
        for _ in 0..<40 { #expect(budget.tick(playing: false, waiting: true, frameDrawn: false, trustedWithoutFrames: false) == .waiting) }
        for _ in 0..<16 { #expect(budget.tick(playing: true, waiting: false, frameDrawn: false, trustedWithoutFrames: false) == .waiting) }
    }
}
