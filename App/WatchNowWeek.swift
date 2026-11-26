import SwiftUI
import TVCore

/// A glance at the last seven days of Watch Now: how many titles were watched and on which days.
/// It counts the playback history only; nothing leaves the device.
struct WatchNowWeekCard: View {
    let entries: [PlaybackHistoryEntry]

    private var days: [(label: String, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let count = entries.filter { $0.updatedAt >= day && $0.updatedAt < next }.count
            let symbols = calendar.veryShortWeekdaySymbols
            return (symbols[calendar.component(.weekday, from: day) - 1], count)
        }
    }

    var body: some View {
        let week = days
        let total = week.reduce(0) { $0 + $1.count }
        let peak = max(1, week.map(\.count).max() ?? 1)
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.text("This Week")).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Text("\(total)").font(.system(size: 40, weight: .semibold, design: .rounded)).foregroundStyle(Brand.accent)
                Text(L10n.text("%lld titles", total)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(day.count == 0 ? Color.secondary.opacity(0.18) : Brand.accent.opacity(0.35 + 0.65 * Double(day.count) / Double(peak)))
                            .frame(width: 14, height: 8 + 52 * CGFloat(day.count) / CGFloat(peak))
                        Text(day.label).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, DiscoverLayout.gutter)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("home.weekCard")
    }
}
