import SwiftUI
import TVCore

struct FavoritesView: View {
    @Environment(Store.self) private var store
    /// The kind the chips show alone; empty shows every kind.
    @AppStorage("favoritesFilter") private var filterKind = ""
    /// The chosen kind while there are favorites of it; else everything, so the page is never empty.
    private var filter: FavoriteKind? {
        FavoriteKind(rawValue: filterKind).flatMap { favoriteKinds.contains($0) ? $0 : nil }
    }
    /// Live channels are not part of this app; any saved earlier stay in the data but are not listed.
    private var favoriteKinds: [FavoriteKind] { store.favorites.kinds.filter { $0 != .live } }
    private func shows(_ kind: FavoriteKind) -> Bool {
        (filter == nil || filter == kind) && !store.favorites.items(kind).isEmpty
    }
    var body: some View {
        Group {
            if favoriteKinds.isEmpty {
                EmptyPage(symbol: AppSection.favorites.icon, title: L10n.text("No Favorites Yet"),
                          message: L10n.text("Save a video, an episode, a song, or a cloud file with the heart."),
                          action: AppSection.discover.title, actionSymbol: AppSection.discover.icon, perform: { store.section = .discover })
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                        if let error = store.favorites.persistenceError {
                            StatusNotice(text: L10n.text("Unable to save favorites: %@", error))
                        }
                        if favoriteKinds.count > 1 { filterBar }
                                        if shows(.video) { filmSection }
                        if shows(.episode) { episodeSection }
                        if shows(.music) { musicSection }
                        if shows(.cloud) { cloudSection }
                    }
                    .pageContainer()
                }
            }
        }
        .screenBackdrop()
        .tabTitle(L10n.text("Favorites"))
    }

    /// One chip per kind that has favorites, with the sections' own names.
    private var filterBar: some View {
        ChipRow {
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Chip(title: L10n.text("All"), selected: filter == nil) { filterKind = "" }
                    ForEach(favoriteKinds, id: \.self) { kind in
                        Chip(title: title(kind), selected: filter == kind) { filterKind = kind.rawValue }
                            .accessibilityIdentifier("favorites.filter.\(kind.rawValue)")
                    }
                }
            }.padding(.vertical, 4)
        }
        .tvFocusSection()
    }

    private func title(_ kind: FavoriteKind) -> String {
        switch kind {
        case .live: L10n.text("Live TV")
        case .video: L10n.text("Films")
        case .episode: L10n.text("Saved Episodes")
        case .music: L10n.text("Liked Songs")
        case .cloud: L10n.text("Cloud Files")
        }
    }

    private var filmSection: some View {
        VStack(alignment: .leading, spacing: Layout.headerSpacing) {
            SectionHeader(title: L10n.text("Films"))
            LazyVGrid(columns: Layout.posterColumns, spacing: Layout.gridRowSpacing) {
                ForEach(store.favorites.items(.video)) { item in
                    if case .video(let video) = item { FavoriteFilmCard(video: video) }
                }
            }
        }
        .tvFocusSection()
    }

    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: Layout.headerSpacing) {
            SectionHeader(title: L10n.text("Saved Episodes"))
            LazyVGrid(columns: Layout.posterColumns, spacing: Layout.gridRowSpacing) {
                ForEach(store.favorites.items(.episode)) { item in
                    if case .episode(let episode) = item { FavoriteEpisodeCard(episode: episode) }
                }
            }
        }
        .tvFocusSection()
    }

    private var musicSection: some View {
        VStack(alignment: .leading, spacing: Layout.headerSpacing) {
            SectionHeader(title: L10n.text("Liked Songs"))
            LazyVStack(alignment: .leading, spacing: MusicLayout.rowSpacing) {
                ForEach(store.favorites.items(.music)) { item in
                    if case .music(let track) = item {
                        HStack(spacing: 10) {
                            MusicTrackRow(track: track, showsFavoriteMark: false) { store.music.play(track) }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            // The row's own menu has Unlike, which is how the remote removes it.
                            #if !os(tvOS)
                            FavoriteHeartButton(item: .music(track), name: track.title)
                                .fixedSize()
                            #endif
                        }
                    }
                }
            }
        }
        .tvFocusSection()
    }

    private var cloudSection: some View {
        VStack(alignment: .leading, spacing: Layout.headerSpacing) {
            SectionHeader(title: L10n.text("Cloud Files"))
            LazyVStack(alignment: .leading, spacing: Layout.cardSpacing) {
                ForEach(store.favorites.items(.cloud)) { item in
                    if case .cloud(let file) = item { FavoriteCloudRow(file: file) }
                }
            }
        }
        .tvFocusSection()
    }
}

/// Opens a saved film on its detail page, or reports that the source is gone.
struct FavoriteVideoOpener<Label: View>: View {
    @Environment(Store.self) private var store
    @Environment(\.stripDrag) private var drag
    private let video: FavoriteVideo
    private let label: Label

    init(video: FavoriteVideo, @ViewBuilder label: () -> Label) {
        self.video = video
        self.label = label()
    }

    var body: some View {
        if let listing = video.listingVideo(), let client = store.catalogClient(for: video) {
            RouteLink { VideoDetailView(video: listing, client: client) } label: { label }
                .buttonStyle(IgnoreStripDragCardStyle(drag: drag))
        } else {
            Button {
                if drag?.active != true { store.reportMissingFavoriteSource() }
            } label: { label }
            .cardButton()
        }
    }
}

/// NavigationLink activates on mouse-up; ignore that click while the home strip is dragging.
private struct IgnoreStripDragCardStyle: PrimitiveButtonStyle {
    var drag: StripDrag?
    func makeBody(configuration: Configuration) -> some View {
        Button {
            if drag?.active != true { configuration.trigger() }
        } label: {
            configuration.label
        }
        .cardButton()
    }
}

/// A saved film. The heart is a sibling of the poster button, so it does not open the title.
private struct FavoriteFilmCard: View {
    let video: FavoriteVideo
    @State private var hovering = false
    private var heartRevealed: Bool {
        #if os(macOS)
        hovering
        #else
        true
        #endif
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            FavoriteVideoOpener(video: video) {
                if let listing = video.listingVideo() {
                    PosterCard(video: listing)
                } else {
                    Text(video.videoName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                }
            }
            .favoriteMenu(.video(video), name: video.videoName)
            #if !os(tvOS)
            FavoriteHeartButton(item: .video(video), name: video.videoName, onArtwork: true, revealed: heartRevealed)
                .fixedSize()
                .padding(8)
            #endif
        }
        #if os(macOS)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.15), value: hovering)
        #endif
    }
}

/// A saved episode. Playing it does not remove the film favorite, and the heart removes only this episode.
private struct FavoriteEpisodeCard: View {
    @Environment(Store.self) private var store
    let episode: FavoriteEpisode
    @State private var hovering = false
    private var heartRevealed: Bool {
        #if os(macOS)
        hovering
        #else
        true
        #endif
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button { store.play(episode) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    if let listing = episode.video.listingVideo() {
                        PosterCard(video: listing)
                    } else {
                        Text(episode.video.videoName).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    }
                    Text(episode.episodeName).font(.caption).foregroundStyle(.secondary).lineLimit(1).cardCaption()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardButton()
            .favoriteMenu(.episode(episode), name: episode.video.videoName)
            #if !os(tvOS)
            FavoriteHeartButton(item: .episode(episode), name: episode.video.videoName, onArtwork: true, revealed: heartRevealed)
                .fixedSize()
                .padding(8)
            #endif
        }
        .overlay(alignment: .topTrailing) { if hovering { detailsLink.padding(8).transition(.opacity) } }
        #if !os(tvOS)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.15), value: hovering)
        #endif
    }

    /// The title's page, where a click on the card only plays the episode. A pointer shows it, as on history cards.
    @ViewBuilder private var detailsLink: some View {
        if let listing = episode.video.listingVideo(), let client = store.catalogClient(for: episode.video) {
            RouteLink { VideoDetailView(video: listing, client: client) } label: {
                Image(systemName: "info").font(.system(size: 11, weight: .bold)).foregroundStyle(.white).artworkBadge()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("Show Details")).help(L10n.text("Show Details"))
        }
    }
}

/// A saved cloud file, using the same panel as a channel card and the file row's label.
private struct FavoriteCloudRow: View {
    @Environment(Store.self) private var store
    let file: FavoriteCloudFile

    var body: some View {
        let cloud = CloudFile(id: file.fileID, name: file.fileName, isFolder: false, size: file.size)
        let driveName = CloudFiles.drive(key: file.driveKey)?.name ?? file.driveKey
        HStack(spacing: 10) {
            Button { store.play(file) } label: {
                FileRowLabel(symbol: cloud.symbol, tint: cloud.tint, title: file.fileName, subtitle: driveName)
            }
            .glassRow()
            .favoriteMenu(.cloud(file), name: file.fileName)
            #if !os(tvOS)
            FavoriteHeartButton(item: .cloud(file), name: file.fileName)
                .fixedSize()
            #endif
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentPanel()
    }
}
