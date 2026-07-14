import SwiftUI

enum ReaderDateText {
    static func string(from date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let elapsed = max(now.timeIntervalSince(date), 0)
        if elapsed < 60 {
            return "刚刚"
        }
        if elapsed < 3_600 {
            return "\(Int(elapsed / 60))分钟前"
        }
        if calendar.isDate(date, inSameDayAs: now) {
            return formatted(date, pattern: "HH:mm", calendar: calendar)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(formatted(date, pattern: "HH:mm", calendar: calendar))"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return formatted(date, pattern: "MM-dd HH:mm", calendar: calendar)
        }
        return formatted(date, pattern: "yyyy-MM-dd", calendar: calendar)
    }

    static func threadMetadataString(
        from date: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let elapsed = max(now.timeIntervalSince(date), 0)
        if elapsed < 3_600 || calendar.isDate(date, inSameDayAs: now) {
            return string(from: date, now: now, calendar: calendar)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 \(formatted(date, pattern: "HH:mm", calendar: calendar))"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return formatted(date, pattern: "MM-dd", calendar: calendar)
        }
        return formatted(date, pattern: "yyyy-MM-dd", calendar: calendar)
    }

    private static func formatted(_ date: Date, pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

struct MetadataLine: View {
    let items: [String]
    let systemImage: String?

    init(_ items: [String], systemImage: String? = nil) {
        self.items = items.filter { $0.isEmpty == false }
        self.systemImage = systemImage
    }

    var body: some View {
        Group {
            if items.isEmpty == false {
                HStack(spacing: TiebaPureTheme.Spacing.xxs) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: TiebaPureTheme.IconSize.inline))
                            .accessibilityHidden(true)
                    }

                    Text(items.joined(separator: " · "))
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct InteractionStatsView: View {
    var comments: Int?
    var likes: Int?
    var font: Font = .subheadline

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: TiebaPureTheme.Spacing.md) {
            if let comments {
                stat(systemImage: "bubble.right", value: comments, label: "评论")
                    .frame(maxWidth: .infinity)
            }
            if let likes {
                stat(systemImage: "hand.thumbsup", value: likes, label: "点赞")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(font)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private func stat(systemImage: String, value: Int, label: String) -> some View {
        HStack(spacing: TiebaPureTheme.Spacing.xxs) {
            Image(systemName: systemImage)
                .font(.system(size: TiebaPureTheme.IconSize.inline))
                .accessibilityHidden(true)
            Text(countText(value))
                .monospacedDigit()
        }
        .accessibilityLabel("\(label)\(value)")
    }

    private func countText(_ value: Int) -> String {
        guard value >= 10_000 else { return "\(value)" }
        let integerPart = value / 10_000
        let decimalPart = value % 10_000 / 1_000
        if decimalPart == 0 {
            return "\(integerPart)万"
        }
        return "\(integerPart).\(decimalPart)万"
    }
}

enum InteractionStatsLayout {
    enum Item {
        case comments
        case likes
    }

    static func xPosition(for item: Item, in width: CGFloat) -> CGFloat {
        switch item {
        case .comments:
            return width / 3
        case .likes:
            return width * 2 / 3
        }
    }
}

struct CompactLikeCountView: View {
    var count: Int

    var body: some View {
        HStack(spacing: TiebaPureTheme.Spacing.xxs) {
            Image(systemName: "hand.thumbsup")
                .font(.system(size: TiebaPureTheme.IconSize.inline, weight: .medium))
                .accessibilityHidden(true)
            Text(countText(count))
                .font(.subheadline)
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .accessibilityLabel("点赞\(count)")
    }

    private func countText(_ value: Int) -> String {
        guard value >= 10_000 else { return "\(value)" }
        let integerPart = value / 10_000
        let decimalPart = value % 10_000 / 1_000
        if decimalPart == 0 {
            return "\(integerPart)万"
        }
        return "\(integerPart).\(decimalPart)万"
    }
}
