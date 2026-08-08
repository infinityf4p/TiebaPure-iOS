import Combine
import Foundation

/// Bookkeeping for the daily check-in: whether it runs on its own, and the day
/// it last completed for a given account. The day is stored per account so
/// switching accounts does not inherit another account's "already done today".
@MainActor
final class ForumSignSettingsStore: ObservableObject {
    nonisolated static let automaticKey = "dev.infinityf4p.tiebapure.forum-sign.automatic-enabled"
    nonisolated static let lastRunDayKeyPrefix = "dev.infinityf4p.tiebapure.forum-sign.last-run-day."

    @Published private(set) var automaticSignEnabled: Bool

    private let defaults: UserDefaults
    private let automaticKey: String
    private let lastRunDayKeyPrefix: String
    private let calendar: Calendar
    private let now: () -> Date

    init(
        defaults: UserDefaults = .standard,
        automaticKey: String = ForumSignSettingsStore.automaticKey,
        lastRunDayKeyPrefix: String = ForumSignSettingsStore.lastRunDayKeyPrefix,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.defaults = defaults
        self.automaticKey = automaticKey
        self.lastRunDayKeyPrefix = lastRunDayKeyPrefix
        self.calendar = calendar
        self.now = now
        automaticSignEnabled = defaults.bool(forKey: automaticKey)
    }

    func setAutomaticSignEnabled(_ isEnabled: Bool) {
        guard automaticSignEnabled != isEnabled else { return }
        if isEnabled {
            defaults.set(true, forKey: automaticKey)
        } else {
            defaults.removeObject(forKey: automaticKey)
        }
        automaticSignEnabled = isEnabled
    }

    func hasRunToday(accountID: String) -> Bool {
        guard accountID.isEmpty == false else { return false }
        let stored = defaults.string(forKey: lastRunDayKey(accountID: accountID))
        return stored == ForumSignDayStamp.text(for: now(), calendar: calendar)
    }

    func markRunCompleted(accountID: String) {
        guard accountID.isEmpty == false else { return }
        defaults.set(
            ForumSignDayStamp.text(for: now(), calendar: calendar),
            forKey: lastRunDayKey(accountID: accountID)
        )
    }

    func clearRunHistory(accountID: String) {
        guard accountID.isEmpty == false else { return }
        defaults.removeObject(forKey: lastRunDayKey(accountID: accountID))
    }

    private func lastRunDayKey(accountID: String) -> String {
        "\(lastRunDayKeyPrefix)\(accountID)"
    }
}

enum ForumSignDayStamp {
    /// A local calendar day, because Baidu's check-in window follows the
    /// user's own day rather than a fixed UTC boundary.
    static func text(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

struct ForumSignRunSummary: Equatable, Sendable {
    var signedCount: Int
    var alreadySignedCount: Int
    var failedForumNames: [String]

    var attemptedCount: Int {
        signedCount + alreadySignedCount + failedForumNames.count
    }

    var isEmpty: Bool { attemptedCount == 0 }

    static let empty = ForumSignRunSummary(
        signedCount: 0,
        alreadySignedCount: 0,
        failedForumNames: []
    )
}

enum ForumSignSummaryText {
    static func message(for summary: ForumSignRunSummary) -> String {
        guard summary.isEmpty == false else {
            return "没有可签到的贴吧。"
        }
        var parts: [String] = []
        if summary.signedCount > 0 {
            parts.append("成功签到 \(summary.signedCount) 个吧")
        }
        if summary.alreadySignedCount > 0 {
            parts.append("\(summary.alreadySignedCount) 个今天已签过")
        }
        if summary.failedForumNames.isEmpty == false {
            let names = summary.failedForumNames.prefix(3).joined(separator: "、")
            let suffix = summary.failedForumNames.count > 3 ? " 等" : ""
            parts.append("\(summary.failedForumNames.count) 个失败（\(names)\(suffix)）")
        }
        return parts.joined(separator: "，") + "。"
    }
}
