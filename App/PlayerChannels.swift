#if !os(tvOS)
import SwiftUI
import TVCore

/// The player's channel list (#1010): the list the live channel was picked from, to switch channels without leaving the
/// player, and the channel's lines (#679) when it has several. `label` is the button's face in its row's style.
struct PlayerChannelsButton<Label: View>: View {
    let channel: Channel
    let session: PlaybackSession
    @Binding var isPresented: Bool
    @ViewBuilder let label: () -> Label
    @Environment(Store.self) private var store

    var body: some View {
        if PlayerChannelsSheet.offered(for: channel, session: session, in: store) {
            Button(action: { isPresented = true }, label: label)
                .help(L10n.text("Channel List"))
                .accessibilityLabel(L10n.text("Channel List"))
                .accessibilityIdentifier("player.channels")
        }
    }
}

extension View {
    /// The channel list, on a view that stays while the player's controls come and go, as the episodes sheet is.
    func playerChannelsSheet(isPresented: Binding<Bool>, channel: Channel, session: PlaybackSession) -> some View {
        modifier(PlayerSheetPresentation(isPresented: isPresented) { PlayerChannelsSheet(channel: channel, session: session).playerSheet() })
    }
}

/// The channels a group at a time, the playing one marked and scrolled to, with the lines above them. Half the screen
/// on a phone, so the picture stays in view.
struct PlayerChannelsSheet: View {
    let channel: Channel
    let session: PlaybackSession
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    static let symbol = "list.bullet.rectangle"

    /// A channel picked from a list of several, or one of several lines.
    @MainActor static func offered(for channel: Channel, session: PlaybackSession, in store: Store) -> Bool {
        session.lines.count > 1
    }

    /// The channel playing now.
    private var playing: Channel { store.playing ?? channel }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.text("Lines"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(L10n.text("Done")) { dismiss() } }
                }
        }
        .environment(\.glassControls, true)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 520, idealWidth: 620, minHeight: 460, idealHeight: 560)
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            SourceStrip(items: session.lines.indices.map { .init(id: "\($0)", name: L10n.text("Line %@", "\($0 + 1)")) },
                        selection: "\(session.line)") { id in
                if let index = Int(id) { session.choose(line: index) }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent).scrollClipDisabled()
            .padding(.horizontal, -16)
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
#endif
