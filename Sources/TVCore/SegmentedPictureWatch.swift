import Foundation

/// How long an HLS stream that plays sound with no drawn frame is left alone before it is repackaged, in half-second
/// checks. A 4K HEVC stream can start its sound seconds before its first frame (the picture is often there a moment
/// later), so the wait matches the six seconds `PictureWaitBudget` gives a listed HEVC picture. Pure state, so tests
/// drive it without a player.
public struct SegmentedPictureWatch {
    public enum Outcome: Equatable, Sendable {
        /// Nothing decided: keep watching.
        case waiting
        /// Frames are drawn, or the picture is one that plays as it is: stop watching.
        case accepted
        /// Sound has played the whole wait with no drawn frame.
        case repackage
    }

    /// 12 x 500ms = 6s of playback with no drawn frame.
    public static let playChecks = 12

    public private(set) var played = 0

    public init() {}

    /// One check. `playing` follows the player's time control; a pause or a stall starts the count again.
    /// `frameDrawn` is the frame-rate signal. `playsAsListed` is a listed picture that isn't HEVC (it plays, as before #585).
    public mutating func check(playing: Bool, frameDrawn: Bool, playsAsListed: Bool) -> Outcome {
        if frameDrawn || playsAsListed { return .accepted }
        guard playing else { played = 0; return .waiting }
        played += 1
        return played >= Self.playChecks ? .repackage : .waiting
    }
}
