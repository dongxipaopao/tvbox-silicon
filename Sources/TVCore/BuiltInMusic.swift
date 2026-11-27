import Foundation

/// The music channels the app ships with: the listing and script the viewer asked to have built in
/// (https://bright-harbor.pages.dev/v1/tvbox.json, music scope only). The script is bundled and runs as
/// `assets://music/builtin-music.js`, so the channels work before any subscription is added and never need the
/// network for the script itself; the audio still streams from the channels' services, which needs the network.
/// A subscription the viewer enables supplies its own listing instead. The bundled copy is frozen: channel fixes
/// ride app updates, and no newer remote script runs on its own.
public enum BuiltInMusic {
    /// Where relative addresses inside the bundled listing and script resolve.
    public static let origin = URL(string: "https://bright-harbor.pages.dev/v1/")!

    nonisolated(unsafe) private static var cached: CloudMusic.Listing??
    private static let lock = NSLock()

    /// The bundled `yingxiaMusic` listing.
    public static var listing: CloudMusic.Listing? {
        lock.withLock {
            if let cached { return cached }
            let value = ScriptAssets.bundled("assets://music/builtin-music.json")
                .flatMap { try? JSONDecoder().decode([String: JSONValue].self, from: Data($0.utf8)) }
                .flatMap { CloudMusic.Listing(json: .object($0)) }
            cached = .some(value)
            return value
        }
    }
}
