import AVFoundation
import Foundation
import TVCore

/// `--sub-play <subscription> <query> <label> [site filter]`: searches one subscription for a title the way
/// Discover does, then on the first matching sources verifies each layer of playback separately:
/// resolution (detail/prepare/resolve), media reachability (a range request with and without the resolved
/// headers), and a headless AVPlayer watched for item status, error codes, audio/video tracks, timeline
/// progress and AVPlayerLayer.isReadyForDisplay. Prints site keys, hosts, statuses and durations only —
/// never URLs, cookies or header values — so the log can stay public.
extension Probe {
    private static func spSeconds(_ d: Duration) -> Double {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
    private static func spF(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "-" }
    private struct SPTimeout: Error {}
    private static func spLimited<T: Sendable>(_ limit: Double, _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask { try await Task.sleep(for: .seconds(limit)); throw SPTimeout() }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    @MainActor static func subPlay(subscription: String, query: String, label: String, siteFilter: String?) async throws {
        setvbuf(stdout, nil, _IONBF, 0)
        // A fatal here used to lose the plugin host's own output (node/java stderr lands in Diagnostics);
        // print the recent records so a dead runtime names its cause in the workflow log.
        do {
            try await subPlayRun(subscription: subscription, query: query, label: label, siteFilter: siteFilter)
        } catch {
            let snapshot = await Diagnostics.shared.snapshot()
            for entry in snapshot.entries.suffix(30) {
                print("diag[\(entry.level.rawValue)] \(entry.category): \(String(entry.message.prefix(300)))")
            }
            throw error
        }
    }

    @MainActor private static func subPlayRun(subscription: String, query: String, label: String, siteFilter: String?) async throws {
        let tag = "subplay[\(label)]"
        let imported = try await HTTPClient().subscriptionImport(try WebAddress.resolve(subscription), fresh: true)
        guard case .subscription(let config) = imported else { print("\(tag) address is not a source subscription"); return }
        print("\(tag) subscription sites=\(config.sites.count) query-length=\(query.count)")
        let wanted = SourceTitleMatch.Wanted(names: [query], year: nil)
        actor Collect { var list: [SourceTitleMatch.Candidate] = []; func add(_ more: [SourceTitleMatch.Candidate]) { list.append(contentsOf: more) } }
        let collect = Collect()
        await GlobalSearch.search(sites: config.sites, origin: config.origin, jarURL: config.spiderURL, query: query) { result in
            await collect.add(SourceTitleMatch.candidates(result.page?.videos ?? [], site: result.site, wanted: wanted))
        }
        let candidates = await collect.list
        var seen = Set<String>(), picked: [SourceTitleMatch.Candidate] = []
        for candidate in candidates where !seen.contains(candidate.site.key) {
            if let siteFilter, !siteFilter.isEmpty, !candidate.site.key.contains(siteFilter), !candidate.site.name.contains(siteFilter) { continue }
            seen.insert(candidate.site.key)
            picked.append(candidate)
            if picked.count == 3 { break }
        }
        print("\(tag) matched-sites=\(picked.map { $0.site.key }.joined(separator: ","))")
        for (index, candidate) in picked.enumerated() {
            let t = "\(tag) play#\(index + 1) site=\(candidate.site.key)"
            let client = CatalogClient(site: candidate.site, origin: config.origin, jarURL: config.spiderURL)
            do {
                let t1 = ContinuousClock.now
                let video = try await spLimited(30) { try await client.detail(candidate.video.id) }
                let detail = spSeconds(t1.duration(to: .now))
                guard let episode = video.episodes.first else { print("\(t) episodes=0"); continue }
                let t2 = ContinuousClock.now
                let plan = try await spLimited(30) { try await client.preparePlayback(episode) }
                let prepare = spSeconds(t2.duration(to: .now))
                let t3 = ContinuousClock.now
                let channel = try await spLimited(30) { try await client.resolvePlayback(plan, choice: plan.choices[0]) }
                let resolve = spSeconds(t3.duration(to: .now))
                print("\(t) resolved detail=\(spF(detail))s prepare=\(spF(prepare))s resolve=\(spF(resolve))s streaming=\(channel.url.scheme == CENCStreams.scheme) host=\(channel.url.host ?? "-") header-keys=\(channel.headers.keys.sorted().joined(separator: ","))")

                func firstByte(_ withHeaders: Bool) async -> String {
                    var request = URLRequest(url: channel.url, timeoutInterval: 20)
                    if withHeaders { for (key, value) in channel.headers { request.setValue(value, forHTTPHeaderField: key) } }
                    request.setValue("bytes=0-65535", forHTTPHeaderField: "Range")
                    let t4 = ContinuousClock.now
                    do {
                        let (bytes, response) = try await URLSession.shared.bytes(for: request)
                        let http = response as? HTTPURLResponse
                        for try await _ in bytes { break }
                        let type = http?.value(forHTTPHeaderField: "Content-Type") ?? "-"
                        return "http=\(http?.statusCode ?? 0) type=\(type) \(spF(spSeconds(t4.duration(to: .now))))s"
                    } catch { return "error=\(type(of: error))" }
                }
                let withHeaders = await firstByte(true)
                let withoutHeaders = await firstByte(false)
                print("\(t) firstbyte with-headers: \(withHeaders) | without-headers: \(withoutHeaders)")

                let asset = CENCStreams.asset(for: channel.url) ?? AVURLAsset(url: channel.url, options: ["AVURLAssetHTTPHeaderFieldsKey": channel.headers])
                let item = AVPlayerItem(asset: asset)
                item.preferredForwardBufferDuration = CENCStreams.forwardBufferDuration
                let player = AVPlayer()
                player.replaceCurrentItem(with: item)
                player.isMuted = true
                let layer = AVPlayerLayer()
                layer.player = player
                let positionUpdates = Task {
                    while !Task.isCancelled {
                        CENCStreams.updatePosition(for: channel.url, seconds: player.currentTime().seconds)
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                let t5 = ContinuousClock.now
                player.play()
                var advanced = false, displayed = false
                for _ in 0..<100 {
                    try await Task.sleep(for: .milliseconds(200))
                    if item.status == .failed { break }
                    if !advanced, player.currentTime().seconds > 0.05 {
                        advanced = true
                        print("\(t) av timeline-advancing at=\(spF(spSeconds(t5.duration(to: .now))))s")
                    }
                    if !displayed, layer.isReadyForDisplay {
                        displayed = true
                        print("\(t) av ready-for-display at=\(spF(spSeconds(t5.duration(to: .now))))s")
                    }
                    if displayed, player.currentTime().seconds > 3 { break }
                }
                positionUpdates.cancel()
                CENCStreams.stop(channel.url)
                player.pause()
                let tracks = (try? await asset.load(.tracks)) ?? []
                let videoTracks = tracks.filter { $0.mediaType == .video }.count
                let audioTracks = tracks.filter { $0.mediaType == .audio }.count
                if item.status == .failed {
                    let nsError = (item.error ?? player.error) as NSError?
                    let underlying = nsError?.userInfo[NSUnderlyingErrorKey] as? NSError
                    print("\(t) av FAILED domain=\(nsError?.domain ?? "-") code=\(nsError?.code ?? 0) underlying=\(underlying.map { "\($0.domain)#\(($0 as NSError).code)" } ?? "-")")
                }
                print("\(t) verdict tracks-video=\(videoTracks) tracks-audio=\(audioTracks) timeline-advancing=\(advanced) ready-for-display=\(displayed) item-status=\(item.status.rawValue) size=\(item.presentationSize.width)x\(item.presentationSize.height)")
            } catch {
                print("\(t) failed=\(error is SPTimeout ? "timeout" : String(describing: type(of: error)))")
            }
        }
        if picked.isEmpty { print("\(tag) no matching source") }
    }
}
