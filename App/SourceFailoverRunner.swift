import Foundation
import TVCore

/// The hooks the title page offers for switching source: set by the page that plays an episode, used by it when the
/// episode can't be resolved and by the player (`Store.failoverFromPlayer`) when the stream never plays.
struct AlternateHooks {
    let videoID: String
    var alternatives: (() -> [AlternateSource])?
    var failCurrent: (() -> Void)?
    var markFailed: ((String) -> Void)?
    var adopt: ((String) -> Void)?
    /// The viewer asked to try everything again: clear every failed mark.
    var resetFailed: (() -> Void)?
}

/// What a stand-in source resolved for an episode.
struct AlternateResolution: Sendable {
    let sourceID: String
    let channel: Channel
    let detail: Video
    let episode: Episode
    let client: CatalogClient
}

enum SourceFailoverRunner {
    /// Seconds each other source gets, and how many are tried at most: a switch that takes a minute is no switch.
    static let attemptSeconds = 20
    static let maxSources = 2

    /// Tries the title's other sources for the same episode, in `SourceFailover.order`. Stops when `token` is no longer
    /// the store's (the viewer started something else), so an old attempt never takes over the player. Every source
    /// tried is marked failed, so it is not tried again.
    @MainActor
    static func run(hooks: AlternateHooks, current: Episode, currentCount: Int, token: UUID, store: Store) async -> AlternateResolution? {
        hooks.failCurrent?()
        guard let alternatives = hooks.alternatives?() else { return nil }
        for alternate in alternatives.prefix(maxSources) {
            guard store.failoverToken == token, !Task.isCancelled else { return nil }
            let applied = store.subscription.map { alternate.client.applying($0) } ?? alternate.client
            let found = await resolve(alternate, applied: applied, currentName: current.name, currentCount: currentCount)
            guard store.failoverToken == token, !Task.isCancelled else { return nil }
            if let found {
                Diagnostics.shared.record(.info, "catalog", "source failover to \(alternate.client.site.key) episode \(found.episode.name)")
                return found
            }
            hooks.markFailed?(alternate.id)
            Diagnostics.shared.record(.warning, "catalog", "source failover: \(alternate.client.site.key) had no playable matching episode")
        }
        return nil
    }

    private static func resolve(_ alternate: AlternateSource, applied: CatalogClient, currentName: String,
                                currentCount: Int) async -> AlternateResolution? {
        await withTaskGroup(of: AlternateResolution?.self) { group in
            group.addTask {
                do {
                    let detail = try await alternate.client.detail(alternate.video.id)
                    let flag = detail.episodes.first?.flag
                    let list = detail.episodes.filter { $0.flag == flag }
                    guard let place = SourceFailover.place(current: currentName, currentCount: currentCount, other: list.map(\.name)) else { return nil }
                    let episode = list[place]
                    let plan = try await applied.preparePlayback(episode)
                    guard let choice = plan.choices.first else { return nil }
                    let channel = try await applied.resolvePlayback(plan, choice: choice)
                    return AlternateResolution(sourceID: alternate.id, channel: channel, detail: detail, episode: episode, client: applied)
                } catch { return nil }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(attemptSeconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
