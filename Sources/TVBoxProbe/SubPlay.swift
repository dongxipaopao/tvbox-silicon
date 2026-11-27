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
        await subPlayConfig(config, query: query, tag: tag, siteFilter: siteFilter)
    }

    /// `--spy-play <file> <query> <label>`: a lone spider file (a Python base.spider class or a CatVod
    /// JavaScript spider), added the way a viewer's own imported file source is, then run through the
    /// same search-to-play probe as --sub-play. The file never enters the log: only its spider's
    /// self-given name and key print.
    @MainActor static func spyPlay(file: String, query: String, label: String) async throws {
        setvbuf(stdout, nil, _IONBF, 0)
        let tag = "spy[\(label)]"
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: file))
            let origin = try ImportedFiles.add(URL(fileURLWithPath: file))
            guard let config = Subscription.singleSpider(data, origin: origin) else {
                print("\(tag) file is not a recognized lone spider (Python base.spider or CatVod JS)")
                return
            }
            let site = config.sites[0]
            print("\(tag) single-spider name=\(site.name) key=\(site.key) runtime=\(site.runtime == .python ? "python" : "javascript")")
            await subPlayConfig(config, query: query, tag: tag, siteFilter: nil)
        } catch {
            let snapshot = await Diagnostics.shared.snapshot()
            for entry in snapshot.entries.suffix(30) {
                print("diag[\(entry.level.rawValue)] \(entry.category): \(String(entry.message.prefix(300)))")
            }
            throw error
        }
    }

    @MainActor private static func subPlayConfig(_ config: Subscription, query: String, tag: String, siteFilter: String?) async {
        print("\(tag) subscription sites=\(config.sites.count) query-length=\(query.count)")
        let wanted = SourceTitleMatch.Wanted(names: [query], year: nil)
        actor Collect { var list: [SourceTitleMatch.Candidate] = []; func add(_ more: [SourceTitleMatch.Candidate]) { list.append(contentsOf: more) } }
        let collect = Collect()
        let t0 = ContinuousClock.now
        await GlobalSearch.search(sites: config.sites, origin: config.origin, jarURL: config.spiderURL, query: query) { result in
            await collect.add(SourceTitleMatch.candidates(result.page?.videos ?? [], site: result.site, wanted: wanted))
        }
        let candidates = await collect.list
        let searchSeconds = spSeconds(t0.duration(to: .now))
        var seen = Set<String>(), picked: [SourceTitleMatch.Candidate] = []
        for candidate in candidates where !seen.contains(candidate.site.key) {
            if let siteFilter, !siteFilter.isEmpty, !candidate.site.key.contains(siteFilter), !candidate.site.name.contains(siteFilter) { continue }
            seen.insert(candidate.site.key)
            picked.append(candidate)
            if picked.count == 3 { break }
        }
        print("\(tag) site-filter=\(siteFilter?.isEmpty == false ? siteFilter! : "<none>") candidates=\(candidates.count) search=\(spF(searchSeconds))s")
        print("\(tag) matched-sites=\(picked.map { $0.site.key }.joined(separator: ","))")
        for (index, candidate) in picked.enumerated() {
            let t = "\(tag) play#\(index + 1) site=\(candidate.site.key)"
            let client = CatalogClient(site: candidate.site, origin: config.origin, jarURL: config.spiderURL)
            do {
                let t1 = ContinuousClock.now
                let video = try await spLimited(30) { try await client.detail(candidate.video.id) }
                let detail = spSeconds(t1.duration(to: .now))
                print("\(t) title=\(video.name) year=\(video.year ?? "-") category=\(video.category ?? "-") remarks=\(video.remarks) episodes=\(video.episodes.count)")
                guard let episode = video.episodes.first else { print("\(t) episodes=0"); continue }
                let t2 = ContinuousClock.now
                let plan = try await spLimited(30) { try await client.preparePlayback(episode) }
                let prepare = spSeconds(t2.duration(to: .now))
                let t3 = ContinuousClock.now
                let channel = try await spLimited(30) { try await client.resolvePlayback(plan, choice: plan.choices[0]) }
                let resolve = spSeconds(t3.duration(to: .now))
                print("\(t) resolved detail=\(spF(detail))s prepare=\(spF(prepare))s resolve=\(spF(resolve))s streaming=\(channel.url.scheme == CENCStreams.scheme) raw-proxy=\(plan.choices[0].address.contains("/proxy?")) host=\(channel.url.host ?? "-") header-keys=\(channel.headers.keys.sorted().joined(separator: ","))")

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
                if channel.url.path.lowercased().contains(".m3u8") {
                    print("\(t) hls \(await segmentProbe(channel))")
                }

                var options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": channel.headers]
                if let agent = channel.headers.first(where: { $0.key.lowercased() == "user-agent" })?.value, !agent.isEmpty { options[AVURLAssetHTTPUserAgentKey] = agent }
                let asset = CENCStreams.asset(for: channel.url) ?? AVURLAsset(url: channel.url, options: options)
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

    /// HLS layer probe (#B55): reads the manifest (and the first variant when it lists one) with the
    /// source's headers, then fetches the first segment with and without them. A CDN that refuses
    /// headerless segment requests shows as a status split. Statuses and content types only, never URLs.
    private static func segmentProbe(_ channel: Channel) async -> String {
        func fetch(_ url: URL, headers: [String: String], range: Bool) async throws -> (Data, HTTPURLResponse?) {
            var request = URLRequest(url: url, timeoutInterval: 20)
            for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
            if range { request.setValue("bytes=0-65535", forHTTPHeaderField: "Range") }
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, response as? HTTPURLResponse)
        }
        func status(_ url: URL, _ withHeaders: Bool) async -> String {
            do {
                let (_, http) = try await fetch(url, headers: withHeaders ? channel.headers : [:], range: true)
                return "http=\(http?.statusCode ?? 0) type=\(http?.value(forHTTPHeaderField: "Content-Type") ?? "-")"
            } catch { return "error=\(type(of: error))" }
        }
        func firstEntry(_ manifest: String, base: URL) -> URL? {
            manifest.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty && !$0.hasPrefix("#") }
                .flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
        }
        do {
            let (data, http) = try await fetch(channel.url, headers: channel.headers, range: false)
            guard (200..<300).contains(http?.statusCode ?? 0), let text = String(data: data, encoding: .utf8) else {
                return "manifest http=\(http?.statusCode ?? 0)"
            }
            guard let first = firstEntry(text, base: channel.url) else { return "manifest no-entry-listed" }
            var segment = first
            if first.absoluteString.lowercased().contains(".m3u8") {
                let (data2, _) = try await fetch(first, headers: channel.headers, range: false)
                guard let text2 = String(data: data2, encoding: .utf8), let next = firstEntry(text2, base: first) else { return "variant no-segment-listed" }
                segment = next
            }
            let withHeaders = await status(segment, true)
            let withoutHeaders = await status(segment, false)
            return "segment with-headers: \(withHeaders) | without-headers: \(withoutHeaders)"
        } catch { return "manifest error=\(type(of: error))" }
    }
}
