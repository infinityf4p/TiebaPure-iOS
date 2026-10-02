import Foundation

/// Whether the app keeps a diagnostic log at all.
///
/// The log exists to be handed back when a screen shows the wrong thing, so it
/// is on until the user says otherwise. Turning it off has to stop the record
/// rather than hide it, and the flag is read straight from `UserDefaults` so a
/// call site can ask before building a message that would only be thrown away.
struct DiagnosticLogSettings {
    static let loggingKey = "dev.infinityf4p.tiebapure.diagnostics.logging-enabled"

    private let defaults: UserDefaults
    private let loggingKey: String

    init(
        defaults: UserDefaults = .standard,
        loggingKey: String = DiagnosticLogSettings.loggingKey
    ) {
        self.defaults = defaults
        self.loggingKey = loggingKey
    }

    /// Unset means on: a fresh install has to be able to record without being
    /// asked first, or the first report of a broken screen arrives with no
    /// evidence at all.
    var isEnabled: Bool {
        guard defaults.object(forKey: loggingKey) != nil else { return true }
        return defaults.bool(forKey: loggingKey)
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: loggingKey)
    }
}

/// A bounded, in-memory diagnostic log the user can export from Settings.
///
/// The app talks to undocumented Tieba endpoints whose response shapes are only
/// known from observation. When a screen silently shows nothing there is no way
/// to tell an authentication failure from a wrong field name, so the network
/// layer records what it actually received and the user can hand the file back.
///
/// Everything here is best-effort: recording must never throw and never block a
/// network call, the buffer is capped so a long session cannot grow without
/// bound, and the whole log can be switched off from Settings.
actor AppLog {
    static let shared = AppLog()

    /// Readable without awaiting the actor: a caller that would have to build an
    /// expensive message first can skip the work instead of discarding it.
    static var isEnabled: Bool { DiagnosticLogSettings().isEnabled }

    enum Level: String, Sendable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    struct Entry: Identifiable, Sendable, Equatable {
        let id: Int64
        let date: Date
        let level: Level
        let category: String
        let message: String
    }

    /// Roughly a long browsing session; older entries fall off the end.
    private static let capacity = 800

    private var entries: [Entry] = []
    private var nextID: Int64 = 1

    func record(
        _ level: Level = .info,
        _ category: String,
        _ message: String
    ) {
        // The switch is checked here rather than at each call site: a disabled
        // log must record nothing at all, and the entry never exists to be
        // exported or counted.
        guard Self.isEnabled else { return }
        entries.append(
            Entry(
                id: nextID,
                date: Date(),
                level: level,
                category: category,
                message: DiagnosticRedaction.redact(message)
            )
        )
        nextID += 1
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    func recordError(
        _ category: String,
        _ message: String,
        error: Error
    ) {
        record(.error, category, "\(message): \(error)")
    }

    func recent(_ limit: Int = 100) -> [Entry] {
        Array(entries.suffix(max(limit, 0)))
    }

    func count() -> Int {
        entries.count
    }

    func clear() {
        entries.removeAll()
    }

    /// The exported file. Includes a small header so a log that arrives without
    /// its conversation still identifies the app build and device.
    func exportText(deviceSummary: String) -> String {
        var lines: [String] = []
        lines.append("TiebaPure 诊断日志")
        lines.append("导出时间：\(Self.timestamp(Date()))")
        lines.append("设备：\(DiagnosticRedaction.redact(deviceSummary))")
        lines.append("条目数：\(entries.count)")
        lines.append("")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"

        for entry in entries {
            lines.append(
                "\(formatter.string(from: entry.date)) [\(entry.level.rawValue)] \(entry.category): \(entry.message)"
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        return formatter.string(from: date)
    }
}

/// Keeps credentials out of an export that leaves the device.
///
/// The network layer never writes a secret on purpose, but raw response bodies
/// and cookie echoes can carry `BDUSS`, `STOKEN` or `tbs` anyway, so every
/// message is scrubbed on the way in rather than trusting each call site.
enum DiagnosticRedaction {
    static let placeholder = "<已脱敏>"

    /// Field names whose values are credentials or session tokens.
    private static let secretKeys = [
        "BDUSS", "STOKEN", "tbs", "sign", "cuid", "CUID", "baiduid", "BAIDUID",
        "sekey", "token", "cookie", "Cookie", "session", "Session"
    ]

    private static let secretKeyPattern = secretKeys
        .map { NSRegularExpression.escapedPattern(for: $0) }
        .joined(separator: "|")

    private static let jsonSecretPattern = try? NSRegularExpression(
        pattern: "\"(\(secretKeyPattern))\"\\s*:\\s*\"[^\"]*\"",
        options: [.caseInsensitive]
    )

    private static let cookieSecretPattern = try? NSRegularExpression(
        pattern: "\\b(\(secretKeyPattern))\\s*=\\s*[^;\\s\"']+",
        options: [.caseInsensitive]
    )

    /// Long opaque blobs — cookie jars, signed protobuf envelopes, base64 media
    /// markers — carry no diagnostic value once their length is known.
    private static let longBlobPattern = try? NSRegularExpression(
        pattern: "[A-Za-z0-9_\\-]{40,}"
    )

    static func redact(_ text: String) -> String {
        let withoutJSONSecrets = substitute(jsonSecretPattern, in: text) { match, source in
            "\"\(captured(in: match, in: source))\":\"\(placeholder)\""
        }
        let withoutCookieSecrets = substitute(cookieSecretPattern, in: withoutJSONSecrets) { match, source in
            "\(captured(in: match, in: source))=\(placeholder)"
        }
        return substitute(longBlobPattern, in: withoutCookieSecrets) { match, _ in
            // `match.range(in:)` does not survive the Swift import of
            // NSTextCheckingResult, whose `range` property shadows that method,
            // so the length has to come off the property.
            "\(placeholder)(\(match.range.length) chars)"
        }
    }

    /// Replaces every match with the name captured by group 1, keeping the rest
    /// of the token so a redacted log still reads like a cookie header.
    private static func substitute(
        _ pattern: NSRegularExpression?,
        in text: String,
        with replacement: (NSTextCheckingResult, String) -> String
    ) -> String {
        var result = text
        guard let pattern else { return result }

        // Regex ranges are UTF-16 offsets, so matches are collected first and
        // applied back to front: replacing a later match cannot shift an earlier
        // match's offsets.
        let matches = pattern.matches(
            in: result,
            range: NSRange(result.startIndex..<result.endIndex, in: result)
        )
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: replacement(match, result))
        }
        return result
    }

    private static func captured(in match: NSTextCheckingResult, in text: String) -> String {
        guard match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return "" }
        return String(text[range])
    }
}

/// Summarises a JSON payload as a type/field skeleton.
///
/// The interesting question when a decode fails is usually "what is this
/// endpoint actually called?", not "what are the values", so scalar values are
/// reported only for the numeric and boolean leaves that make an error code
/// readable, and object/array keys are reported in full.
enum DiagnosticJSON {
    /// The key list is the payload: a nested-vs-flat mismatch hides exactly in
    /// the keys a six-entry cap truncated away, and a guide row carries well
    /// under forty fields, so the cap now only guards against a pathological
    /// response instead of steering what is visible.
    private static let maxEntriesPerObject = 40

    static func skeleton(_ data: Data) -> String {
        let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return describe(object, depth: 0)
    }

    static func describe(_ value: Any?, depth: Int) -> String {
        // A guide row nests four levels deep (root → data → array → row), so the
        // limit has to clear that or every scalar leaf prints as an ellipsis.
        guard depth < 6 else { return "…"}
        switch value {
        case let dictionary as [String: Any]:
            let keys = dictionary.keys.sorted()
            guard keys.isEmpty == false else { return "{}"}
            let body = keys
                .prefix(maxEntriesPerObject)
                .map { "\($0): \(describe(dictionary[$0], depth: depth + 1))" }
                .joined(separator: ", ")
            let rest = keys.count > maxEntriesPerObject
                ? ", …\(keys.count - maxEntriesPerObject) more"
                : ""
            return "{\(body)\(rest)}"
        case let array as [Any]:
            guard let first = array.first else { return "[]"}
            return "[\(array.count) × \(describe(first, depth: depth + 1))]"
        case let number as NSNumber:
            // JSONSerialization bridges true/false to NSNumber too, and a
            // check-in flag is only readable as a bool if it is not printed as
            // 0/1 next to a level count.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return "Bool(\(number.boolValue))"
            }
            return "Num(\(number.stringValue))"
        case is NSNull:
            return "null"
        case let string as String:
            return string.isEmpty ? "String(empty)" : "String(\(string.count))"
        default:
            return "\(type(of: value))"
        }
    }
}