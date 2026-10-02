import SwiftUI
import UIKit

/// Export surface for `AppLog`.
///
/// The log exists to answer "what did the service actually send?", so the file
/// is a plain UTF-8 text file the user can attach anywhere, and every entry is
/// redacted before it reaches this view.
struct DiagnosticsLogView: View {
    @State private var entries: [AppLog.Entry] = []
    @State private var exportURL: URL?
    @State private var isRecordingEnabled = true

    var body: some View {
        List {
            Section {
                LabeledContent("已记录", value: "\(entries.count) 条")

                if let exportURL {
                    ShareLink(item: exportURL) {
                        Label("导出日志", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("diagnostics-export-share")
                } else {
                    Button {
                        Task { await prepareExport() }
                    } label: {
                        Label("导出日志", systemImage: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)
                    .accessibilityIdentifier("diagnostics-export-button")
                }

                Button(role: .destructive) {
                    Task {
                        await AppLog.shared.clear()
                        await reload()
                    }
                } label: {
                    Label("清空日志", systemImage: "trash")
                }
                .disabled(entries.isEmpty)
                .accessibilityIdentifier("diagnostics-clear-button")
            } header: {
                Text("诊断")
            } footer: {
                Text(
                    isRecordingEnabled
                        ? "只保存在本机内存，退出应用即清空。导出的内容已自动去掉 BDUSS、STOKEN、tbs 等凭据。"
                        : "记录已关闭，不会再有新内容。可在「设置 → 诊断」里重新开启；已记录的内容仍可导出或清空。"
                )
                .accessibilityIdentifier("diagnostics-recording-footer")
            }

            Section("最近记录") {
                if entries.isEmpty {
                    Text(
                        isRecordingEnabled
                            ? "暂无记录。回到首页或进吧刷新一次，再回来查看。"
                            : "记录已关闭，所以这里是空的。"
                    )
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("diagnostics-empty")
                } else {
                    ForEach(entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                            HStack(spacing: TiebaPureTheme.Spacing.xs) {
                                Text(entry.level.rawValue)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(levelColor(entry.level))
                                Text(entry.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }
                            Text(entry.message)
                                .font(.system(.footnote, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, TiebaPureTheme.Spacing.xxs)
                    }
                }
            }
        }
        .navigationTitle("诊断日志")
        .task { await reload() }
    }

    private func levelColor(_ level: AppLog.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func reload() async {
        isRecordingEnabled = AppLog.isEnabled
        entries = await AppLog.shared.recent(200)
    }

    private func prepareExport() async {
        let text = await AppLog.shared.exportText(deviceSummary: deviceSummary())
        let url = Self.temporaryFileURL()
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            await reload()
        } catch {
            // A failed export is itself worth recording; there is nowhere else to
            // show it and the in-app list stays usable.
            await AppLog.shared.recordError("诊断日志", "导出失败", error: error)
        }
    }

    private func deviceSummary() -> String {
        let device = UIDevice.current
        return "\(device.systemName) \(device.systemVersion) / \(device.model) / \(device.name)"
    }

    static func temporaryFileURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "TiebaPure-diagnostics-\(formatter.string(from: Date())).log"
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
    }
}