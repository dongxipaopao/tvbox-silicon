import SwiftUI
import TVCore

/// A channel or line's round logo: its picture over a gradient with its first letter.
struct ChannelLogo: View {
    let channel: Channel
    var size: CGFloat = 50
    private static let palette: [[Color]] = [
        [Brand.cyan, Color(red: 0.05, green: 0.36, blue: 0.75)], [Brand.indigo, Color(red: 0.20, green: 0.22, blue: 0.62)],
        [Brand.teal, Color(red: 0.04, green: 0.42, blue: 0.55)], [Color(red: 0.62, green: 0.50, blue: 1.0), Color(red: 0.32, green: 0.18, blue: 0.62)],
        [Color(red: 0.45, green: 0.66, blue: 0.95), Color(red: 0.16, green: 0.30, blue: 0.55)],
    ]
    private var colors: [Color] {
        Self.palette[channel.name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % Self.palette.count]
    }
    var body: some View {
        #if os(tvOS)
        let size: CGFloat = 72
        #endif
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(String(channel.name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
                .font(.system(size: size * 0.4, weight: .bold, design: .rounded)).foregroundStyle(.white)
            if let logo = channel.logo {
                AsyncImage(url: logo) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit().padding(size * 0.12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.95))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}
