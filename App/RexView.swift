#if !os(tvOS)
import SwiftUI
import TVCore

/// What the person has imported from Rex subscriptions, and what each module can open.
@MainActor @Observable final class RexModel {
    static let shared = RexModel()
    struct Entry: Identifiable {
        let widget: RexCollection.Widget
        var problem: RexError?
        var checked = false
        var id: String { widget.url }
    }
    struct Imported: Identifiable { let address: String; let collection: RexCollection; var id: String { address } }
    private(set) var collections: [Imported] = []
    private(set) var entries: [Entry] = []
    var message: String?
    var busy = false
    private var started = false

    func start() async {
        guard !started else { return }
        started = true
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "qaRexFixture") { await add("assets://rex/fixture.json"); return }
        if let address = UserDefaults.standard.string(forKey: "qaRexCollection") { await add(address); return }
        #endif
        for address in RexStore.addresses { await load(address, remember: false) }
    }

    func add(_ address: String) async {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await load(trimmed, remember: !trimmed.hasPrefix("assets://"))
    }

    func remove(_ address: String) {
        RexStore.addresses.removeAll { $0 == address }
        collections.removeAll { $0.address == address }
        rebuild()
    }

    private func load(_ address: String, remember: Bool) async {
        busy = true; message = nil
        defer { busy = false }
        do {
            let collection = try await RexRuntime.fetchCollection(address)
            guard !collection.widgets.isEmpty else { message = L10n.text("This subscription has no modules."); return }
            collections.removeAll { $0.address == address }
            collections.append(Imported(address: address, collection: collection))
            if remember, !RexStore.addresses.contains(address) { RexStore.addresses.append(address) }
            rebuild()
            await check(collection.widgets)
        } catch {
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func rebuild() {
        let old = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        entries = collections.flatMap(\.collection.widgets).map { old[$0.url] ?? Entry(widget: $0) }
    }

    /// Opens each module once, four at a time, to tell the ones that run from the encrypted or broken ones.
    private func check(_ widgets: [RexCollection.Widget]) async {
        var start = 0
        while start < widgets.count {
            let batch = Array(widgets[start..<min(start + 4, widgets.count)])
            start += 4
            let results = await withTaskGroup(of: (String, RexError?).self) { group -> [(String, RexError?)] in
                for widget in batch { group.addTask { (widget.url, await RexRuntime.shared.probe(widget)) } }
                var all: [(String, RexError?)] = []
                for await result in group { all.append(result) }
                return all
            }
            for (url, problem) in results {
                if let index = entries.firstIndex(where: { $0.id == url }) { entries[index].problem = problem; entries[index].checked = true }
            }
        }
    }
}

/// Discover's Rex row: the modules that run, with an import button for a subscription address.
struct RexShelf: View {
    @State private var model = RexModel.shared
    @State private var importing = false
    @State private var address = ""
    #if DEBUG
    @State private var qaOpen: RexCollection.Widget?
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(L10n.text("Rex Modules")).font(.system(size: DiscoverLayout.heading, weight: .semibold))
                Spacer()
                if model.busy { ProgressView() }
                Button { importing = true } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.plain).accessibilityIdentifier("rex.import").accessibilityLabel(L10n.text("Import Rex Subscription"))
            }
            .frame(height: DiscoverLayout.headingHeight, alignment: .top).padding(.horizontal, DiscoverLayout.gutter)
            if model.entries.isEmpty {
                Text(model.message ?? L10n.text("Import a Rex subscription to browse its list modules here."))
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, DiscoverLayout.gutter)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(model.entries) { entry in card(entry) }
                    }.padding(.horizontal, DiscoverLayout.gutter)
                }
                if let message = model.message { Text(message).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, DiscoverLayout.gutter).padding(.top, 6) }
            }
        }
        .task {
            await model.start()
            #if DEBUG
            // `-qaRexOpen 1` opens the first module that runs, for screenshots.
            // The value is a module id (`-qaRexOpen fixture.html`) or 1 for the first module that runs.
            if let want = UserDefaults.standard.string(forKey: "qaRexOpen") {
                for _ in 0..<40 where !model.entries.allSatisfy(\.checked) || model.entries.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
                qaOpen = want == "1" ? model.entries.first { $0.checked && $0.problem == nil }?.widget
                    : model.entries.first { $0.widget.id == want && $0.problem == nil }?.widget
            }
            #endif
        }
        .sheet(isPresented: $importing) { importSheet }
        #if DEBUG
        .sheet(item: $qaOpen) { widget in NavigationStack { RexModuleView(widget: widget).toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { qaOpen = nil } } } } }
        #endif
    }

    @ViewBuilder private func card(_ entry: RexModel.Entry) -> some View {
        let supported = entry.checked && entry.problem == nil
        let content = VStack(alignment: .leading, spacing: 4) {
            Text(entry.widget.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text(status(entry)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(12).frame(width: 150, height: 74, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        if supported {
            RouteLink { RexModuleView(widget: entry.widget) } label: { content }
                .buttonStyle(.plain).accessibilityIdentifier("rex.module." + entry.widget.id)
        } else {
            content.opacity(0.55).accessibilityIdentifier("rex.module." + entry.widget.id)
        }
    }

    private func status(_ entry: RexModel.Entry) -> String {
        if !entry.checked { return L10n.text("Checking…") }
        if let problem = entry.problem { if case .encrypted = problem { return L10n.text("Encrypted, not supported yet") }; return L10n.text("Can't open") }
        return entry.widget.version.isEmpty ? L10n.text("Ready") : "v" + entry.widget.version
    }

    private var importSheet: some View {
        NavigationStack {
            Form {
                Section { TextField("https://…/collection.rex", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                } footer: { Text(L10n.text("Only list modules that are not encrypted run for now. The address is kept on this device.")) }
                if !model.collections.isEmpty {
                    Section {
                        ForEach(model.collections) { item in
                            Text(item.collection.title)
                        }.onDelete { offsets in for index in offsets { model.remove(model.collections[index].address) } }
                    }
                }
            }
            .navigationTitle(L10n.text("Import Rex Subscription")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L10n.text("Done")) { importing = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Import")) { let value = address; address = ""; importing = false; Task { await model.add(value) } }
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// One module's lists: a tab per list function, its options, and the titles it returns.
struct RexModuleView: View {
    let widget: RexCollection.Widget
    @State private var module: RexModule?
    @State private var selected: RexFunction?
    @State private var choices: [String: String] = [:]
    @State private var items: [RexItem] = []
    @State private var page = 1
    @State private var loading = false
    @State private var more = true
    @State private var failure: String?
    @State private var request = 0
    @State private var pending: Task<Void, Never>?
    #if DEBUG
    @State private var qaItem: RexItem?
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let module {
                    let lists = module.functions.filter(\.listsTitles)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(lists) { function in
                            Button(function.title) { select(function) }
                                .buttonStyle(.bordered).tint(function.id == selected?.id ? .accentColor : .secondary)
                                .accessibilityIdentifier("rex.function." + function.id)
                        } }
                    }
                    if let selected {
                        ForEach(selected.params.filter { $0.type == "enumeration" && !$0.options.isEmpty }, id: \.name) { param in
                            Picker(param.title, selection: Binding(get: { choices[param.name] ?? param.value }, set: { choices[param.name] = $0; reload() })) {
                                ForEach(param.options, id: \.value) { Text($0.title).tag($0.value) }
                            }.pickerStyle(.menu)
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12, alignment: .top)], spacing: 14) {
                    ForEach(items) { item in
                        RouteLink { RexItemView(widget: widget, stream: module?.functions.first(where: \.isStream), item: item) } label: { RexTile(item: item) }
                            .buttonStyle(.plain).accessibilityIdentifier("rex.item." + item.id)
                    }
                }
                if loading { ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("rex.loading") }
                if let failure { Text(failure).font(.footnote).foregroundStyle(.secondary) }
                if more, !items.isEmpty, !loading {
                    Button(L10n.text("Load More")) { Task { await fetch(next: true) } }.frame(maxWidth: .infinity)
                }
            }.padding()
        }
        .background { DiscoverCanvas(poster: nil) }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .navigationTitle(module?.title ?? widget.title)
        #if DEBUG
        .navigationDestination(item: $qaItem) { item in RexItemView(widget: widget, stream: module?.functions.first(where: \.isStream), item: item) }
        #endif
        .task {
            do {
                let loaded = try await RexRuntime.shared.module(widget)
                module = loaded
                if let first = loaded.functions.first(where: \.listsTitles) { select(first) }
                #if DEBUG
                // `-qaRexItem <id>` opens that title's page once the list is in (state trigger for screenshots, not a tap).
                if let want = UserDefaults.standard.string(forKey: "qaRexItem") {
                    for _ in 0..<40 where items.isEmpty { try? await Task.sleep(for: .milliseconds(250)) }
                    qaItem = items.first { $0.id == want }
                }
                #endif
            } catch { failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
        }
    }

    private func select(_ function: RexFunction) { selected = function; choices = [:]; reload() }
    private func reload() { items = []; page = 1; more = true; failure = nil; Task { await fetch(next: false) } }

    private func fetch(next: Bool) async {
        guard let function = selected, !loading else { return }
        loading = true; defer { loading = false }
        let wanted = next ? page + 1 : 1
        do {
            let more = try await RexRuntime.shared.items(widget, function: function, overrides: choices, page: wanted)
            guard selected?.id == function.id else { return }
            let known = Set(items.map(\.id))
            let fresh = more.filter { !known.contains($0.id) }
            self.more = !fresh.isEmpty && function.params.contains { $0.type == "page" }
            items += fresh; page = wanted
            if items.isEmpty { failure = L10n.text("This list is empty.") }
        } catch { failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }
}

private struct RexTile: View {
    let item: RexItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.aspectRatio(2.0 / 3, contentMode: .fit)
                .overlay { PosterImage(url: item.poster) }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(item.title).font(.caption.weight(.medium)).lineLimit(1)
            Text(item.subtitle.isEmpty ? " " : item.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

/// A title from a Rex module: its cover and facts, and a way to search the user's own sources for it.
struct RexItemView: View {
    let widget: RexCollection.Widget
    let stream: RexFunction?
    let item: RexItem
    @Environment(Store.self) private var store
    @State private var episode = 1
    @State private var lines: [RexLine] = []
    @State private var skipped = 0
    @State private var loading = false
    @State private var asked = false
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PosterImage(url: item.poster).frame(width: qaCompact ? 60 : 220, height: qaCompact ? 90 : 330).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(item.title).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                if !item.subtitle.isEmpty { Text(item.subtitle).font(.subheadline).opacity(0.7) }
                if !item.overview.isEmpty { Text(item.overview).font(.footnote).opacity(0.7).multilineTextAlignment(.leading) }
                if let stream { playLines(stream) }
                DiscoverFindSourcesButton(title: item.title).padding(.top, 8).accessibilityIdentifier("rex.findSources")
            }.padding(40).frame(maxWidth: .infinity)
        }
        .background { DiscoverCanvas(poster: item.poster) }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .onDisappear { reset() }
        #if DEBUG
        .task { await qaDrive() }
        #endif
    }

    @ViewBuilder private func playLines(_ stream: RexFunction) -> some View {
        VStack(spacing: 10) {
            Stepper(value: $episode, in: 1...999) { Text(L10n.text("Episode %lld", episode)) }
                .onChange(of: episode) { _, _ in reset() }
            Button { start(stream) } label: { Text(L10n.text("Show Play Lines")).frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).disabled(loading).accessibilityIdentifier("rex.showLines")
            if loading { ProgressView().accessibilityIdentifier("rex.lines.loading") }
            if let failure { Text(failure).font(.footnote).opacity(0.7).multilineTextAlignment(.center) }
            else if asked, !loading, lines.isEmpty { Text(L10n.text("No play lines were returned.")).font(.footnote).opacity(0.7) }
            ForEach(lines) { line in
                Button { play(line) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name.isEmpty ? L10n.text("Play Line") : line.name).font(.subheadline.weight(.semibold))
                        if !line.detail.isEmpty { Text(line.detail).font(.caption).opacity(0.7).lineLimit(2) }
                        if line.playURL == nil { Text(L10n.text("This line is not a web address, so it cannot play.")).font(.caption).opacity(0.7) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered).disabled(line.playURL == nil)
            }
            if skipped > 0 { Text(L10n.text("%lld lines had no address and were skipped.", skipped)).font(.caption).opacity(0.7) }
        }
    }

    private var qaCompact: Bool {
        #if DEBUG
        UserDefaults.standard.bool(forKey: "qaRexLines")
        #else
        false
        #endif
    }

    #if DEBUG
    /// Screenshot hooks, state triggers and not taps: `-qaRexLines 1` asks for the lines, `-qaRexEpisodeAfter N` then moves the
    /// episode (the answer must clear), `-qaRexTap 1` then plays the first line that can play.
    private func qaDrive() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "qaRexLines"), let stream else { return }
        start(stream)
        for _ in 0..<40 where !asked { try? await Task.sleep(for: .milliseconds(250)) }
        if defaults.integer(forKey: "qaRexEpisodeAfter") > 0 {
            try? await Task.sleep(for: .seconds(2))
            episode = defaults.integer(forKey: "qaRexEpisodeAfter")
        }
        if defaults.bool(forKey: "qaRexTap"), let line = lines.first(where: { $0.playURL != nil }) { play(line) }
    }
    #endif

    /// A newer request, a changed episode or leaving the page drops the old answer: the generation number decides whether a
    /// finished request may still write, so a late answer never replaces what is on screen. Only the previous request is
    /// cancelled, never the one just started.
    private func reset() {
        request += 1
        pending?.cancel(); pending = nil
        lines = []; skipped = 0; failure = nil; asked = false; loading = false
    }

    private func start(_ stream: RexFunction) {
        request += 1
        let mine = request
        pending?.cancel()
        lines = []; skipped = 0; failure = nil; asked = false; loading = true
        var params = ["id": item.id, "link": item.id, "episode": String(episode)]
        if !item.kind.isEmpty { params["type"] = item.kind; params["mediaType"] = item.kind }
        pending = Task {
            let result: Result<RexLines, Error>
            do { result = .success(try await RexRuntime.shared.lines(widget, function: stream, params: params)) }
            catch { result = .failure(error) }
            guard mine == request else { return }
            loading = false; asked = true
            switch result {
            case .success(let answer): lines = answer.lines; skipped = answer.invalid
            case .failure(let error):
                guard !(error is CancellationError) else { return }
                failure = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func play(_ line: RexLine) {
        guard let url = line.playURL else { return }
        let name = line.name.isEmpty ? item.title : item.title + " · " + line.name
        store.playing = Channel(name: name, group: "Rex", url: url, headers: line.headers)
    }
}
#endif
