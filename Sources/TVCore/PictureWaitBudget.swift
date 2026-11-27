import Foundation

/// The wait-screen budget for an episode with a picture, in quarter-second ticks: a drawn frame reveals the
/// player; six seconds of play with no drawn frame (a trusted HEVC listing excepted, #585) or twenty seconds of
/// buffering without a picture fail by name. A pause spends neither budget. Pure state, so tests drive it
/// without a player.
public struct PictureWaitBudget {
    public enum Outcome: Equatable, Sendable {
        /// Nothing decided: keep watching.
        case waiting
        /// The wait is over: show the picture.
        case reveal
        /// Six seconds of sound, no drawn frame, no HEVC exception.
        case failNoDrawnFrame
        /// Twenty seconds of buffering, no picture at all.
        case failStalled
    }

    /// 24 x 250ms = 6s of playback with no drawn frame.
    public static let playTicks = 24
    /// 80 x 250ms = 20s of buffering with no picture.
    public static let stallTicks = 80

    public private(set) var played = 0
    public private(set) var stalled = 0

    public init() {}

    /// One tick of the watch. `playing`/`waiting` follow the player's time control; anything else (a pause)
    /// spends nothing. `frameDrawn` is the play-time frame-rate signal. `trustedWithoutFrames` is the HEVC
    /// exception: the caller answers it only when the play budget can trip, so its async check never runs early.
    public mutating func tick(playing: Bool, waiting: Bool, frameDrawn: Bool, trustedWithoutFrames: Bool) -> Outcome {
        if frameDrawn { return .reveal }
        if playing { played += 1 } else if waiting { stalled += 1 } else { return .waiting }
        if played >= Self.playTicks { return trustedWithoutFrames ? .reveal : .failNoDrawnFrame }
        if stalled >= Self.stallTicks { return .failStalled }
        return .waiting
    }
}
