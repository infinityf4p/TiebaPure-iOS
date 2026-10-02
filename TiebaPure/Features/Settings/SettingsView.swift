import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var appearanceStore: AppAppearanceStore
    @EnvironmentObject private var contentSubmissionSettingsStore: ContentSubmissionSettingsStore
    @EnvironmentObject private var forumSignSettingsStore: ForumSignSettingsStore
    @EnvironmentObject private var forumSignCoordinator: ForumSignCoordinator
    @Environment(\.colorScheme) private var effectiveColorScheme
    let account: Account?

    @State private var confirmsLogout = false
    @State private var isLoggingOut = false
    @State private var logoutErrorMessage: String?
    /// Mirrored into view state so the footer text follows the switch: a custom
    /// `Binding` writing straight to `UserDefaults` would leave the rest of the
    /// form showing the old value.
    @State private var isDiagnosticLogEnabled = DiagnosticLogSettings().isEnabled

    var body: some View {
        Form {
            Section {
                Picker("显示模式", selection: appearanceSelection) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Label(appearance.title, systemImage: appearance.systemImage)
                            .tag(appearance)
                            .accessibilityIdentifier("appearance-option-\(appearance.rawValue)")
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("appearance-picker")
            } header: {
                HStack(alignment: .firstTextBaseline, spacing: TiebaPureTheme.Spacing.sm) {
                    Text("显示模式")
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("appearance-section-title")

                    Spacer(minLength: TiebaPureTheme.Spacing.sm)

                    Text(effectiveAppearanceTitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                        .accessibilityLabel("当前显示为\(effectiveAppearanceTitle)")
                        .accessibilityIdentifier("appearance-effective-mode")
                }
                .frame(maxWidth: .infinity)
            } footer: {
                Text("选择后会立即应用；跟随系统会随 iPhone 的外观设置自动切换。")
            }

            Section {
                Toggle(isOn: newThreadsEnabledSelection) {
                    Label("允许发帖", systemImage: "square.and.pencil")
                }
                .accessibilityHint("开启后可通过非官方实验接口发布新主题；内容可能被隐藏或删除，账号可能受限或冻结")
                .accessibilityIdentifier("settings-new-threads-enabled-toggle")

                Toggle(isOn: repliesEnabledSelection) {
                    Label("允许回帖", systemImage: "bubble.left.and.bubble.right")
                }
                .accessibilityHint("开启后可通过非官方实验接口回复帖子、楼层和楼中楼；内容可能被隐藏或删除，账号可能受限或冻结")
                .accessibilityIdentifier("settings-replies-enabled-toggle")

                Toggle(isOn: likesEnabledSelection) {
                    Label("允许点赞", systemImage: "hand.thumbsup")
                }
                .accessibilityHint("关闭后仍会显示点赞数量，但不能点赞或取消点赞")
                .accessibilityIdentifier("settings-likes-enabled-toggle")

                NavigationLink {
                    ReadingSettingsView()
                } label: {
                    Label("阅读设置", systemImage: "textformat.size")
                }
                .accessibilityHint("调整帖子正文、回复排序和媒体加载方式")
                .accessibilityIdentifier("settings-reading-entry")

                NavigationLink {
                    SavedThreadsView(account: account)
                } label: {
                    Label("本地保存的帖子", systemImage: "internaldrive")
                }
                .accessibilityHint("查看和管理保存在这台设备上的完整帖子快照")
                .accessibilityIdentifier("settings-saved-threads-entry")

                NavigationLink {
                    BlocklistSettingsView()
                } label: {
                    Label("屏蔽设置", systemImage: "hand.raised")
                }
                .accessibilityHint("管理本机保存的关键词、用户和吧屏蔽")
                .accessibilityIdentifier("settings-blocklist-entry")
            } header: {
                Text("内容")
            } footer: {
                Text("发帖和回帖使用非官方实验接口。开启并使用后，可能触发贴吧风控，造成内容被隐藏或删除、账号功能受限；极端情况下账号可能被冻结。请确认能够承担风险后再使用。关闭点赞后仍会显示点赞数量；设置和屏蔽规则仅保存在本机。")
            }

            Section {
                Toggle(isOn: diagnosticLogSelection) {
                    Label("记录诊断日志", systemImage: "record.circle")
                }
                .accessibilityHint("关闭后完全不记录任何诊断信息，已经记录的内容不受影响")
                .accessibilityIdentifier("settings-diagnostics-logging-toggle")

                NavigationLink {
                    DiagnosticsLogView()
                } label: {
                    Label("诊断日志", systemImage: "doc.text.magnifyingglass")
                }
                .accessibilityHint("查看并导出首页推荐、热点和进吧等级的接口返回记录")
                .accessibilityIdentifier("settings-diagnostics-entry")
            } header: {
                Text("诊断")
            } footer: {
                Text(diagnosticLogFooterText)
            }

            if let account {
                Section {
                    Toggle(isOn: automaticSignSelection) {
                        Label("自动签到", systemImage: "checkmark.seal")
                    }
                    .accessibilityHint("每天第一次打开应用时，为关注的贴吧依次签到")
                    .accessibilityIdentifier("settings-automatic-sign-toggle")

                    Button {
                        startManualSign(account: account)
                    } label: {
                        HStack {
                            Label("立即签到", systemImage: "hand.tap")
                            Spacer(minLength: TiebaPureTheme.Spacing.sm)
                            if forumSignCoordinator.isRunning {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(forumSignCoordinator.isRunning)
                    .accessibilityHint("立即为关注的贴吧签到")
                    .accessibilityIdentifier("settings-sign-now-button")
                } header: {
                    Text("签到")
                } footer: {
                    Text(signFooterText)
                }

                Section("账号") {
                    HStack(spacing: TiebaPureTheme.Spacing.sm) {
                        AvatarView(
                            url: account.portraitURL,
                            title: account.displayName,
                            size: TiebaPureTheme.AvatarSize.large
                        )

                        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                            Text(account.displayName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)

                            if account.name != account.displayName {
                                Text(account.name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Text("UID \(account.uid)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, TiebaPureTheme.Spacing.xs)
                }

                Section {
                    Button(role: .destructive) {
                        confirmsLogout = true
                    } label: {
                        HStack(spacing: TiebaPureTheme.Spacing.sm) {
                            Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")

                            Spacer(minLength: TiebaPureTheme.Spacing.sm)

                            if isLoggingOut {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoggingOut)
                    .accessibilityHint("清除本机保存的百度登录状态")
                }
            }
        }
        .navigationTitle("设置")
        .confirmationDialog(
            "退出登录？",
            isPresented: $confirmsLogout,
            titleVisibility: .visible
        ) {
            Button("退出登录", role: .destructive) {
                Task { await logOut() }
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text("这会清除本机保存的百度登录状态。")
        }
        .alert(
            "退出失败",
            isPresented: Binding(
                get: { logoutErrorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        logoutErrorMessage = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            if let logoutErrorMessage {
                Text(logoutErrorMessage)
            }
        }
        .fullScreenInteractiveNavigationPop()
    }

    private var automaticSignSelection: Binding<Bool> {
        Binding(
            get: { forumSignSettingsStore.automaticSignEnabled },
            set: { forumSignSettingsStore.setAutomaticSignEnabled($0) }
        )
    }

    private var diagnosticLogSelection: Binding<Bool> {
        Binding(
            get: { isDiagnosticLogEnabled },
            set: { enabled in
                DiagnosticLogSettings().setEnabled(enabled)
                isDiagnosticLogEnabled = enabled
            }
        )
    }

    private var diagnosticLogFooterText: String {
        if isDiagnosticLogEnabled {
            return "记录接口返回和耗时，用于排查「内容不对」「等级不显示」「签到慢」这类问题。"
                + "只保存在本机内存，退出应用即清空；导出的内容已自动去掉凭据。"
        }
        return "已关闭，不再记录任何诊断信息；已经记录的内容仍可在诊断日志里查看、导出或清空。"
    }

    private var signFooterText: String {
        if let message = signStatusMessage {
            return message
        }
        return "今天已签到的贴吧会直接跳过，只对还没签的吧逐个请求；同一天只会自动执行一次。"
    }

    private var signStatusMessage: String? {
        if let error = forumSignCoordinator.lastError { return error }
        guard let summary = forumSignCoordinator.lastSummary else { return nil }
        return ForumSignSummaryText.message(for: summary)
    }

    private func startManualSign(account: Account) {
        guard forumSignCoordinator.isRunning == false else { return }
        Task { await forumSignCoordinator.signAllFollowedForums(account: account) }
    }

    private var appearanceSelection: Binding<AppAppearance> {
        Binding(
            get: { appearanceStore.selection },
            set: { appearanceStore.select($0) }
        )
    }

    private var effectiveAppearanceTitle: String {
        effectiveColorScheme == .dark ? "深色" : "浅色"
    }

    private var repliesEnabledSelection: Binding<Bool> {
        Binding(
            get: { contentSubmissionSettingsStore.repliesEnabled },
            set: { contentSubmissionSettingsStore.setRepliesEnabled($0) }
        )
    }

    private var newThreadsEnabledSelection: Binding<Bool> {
        Binding(
            get: { contentSubmissionSettingsStore.newThreadsEnabled },
            set: { contentSubmissionSettingsStore.setNewThreadsEnabled($0) }
        )
    }

    private var likesEnabledSelection: Binding<Bool> {
        Binding(
            get: { contentSubmissionSettingsStore.likesEnabled },
            set: { contentSubmissionSettingsStore.setLikesEnabled($0) }
        )
    }

    private func logOut() async {
        isLoggingOut = true
        defer { isLoggingOut = false }

        do {
            try await environment.logoutCoordinator.logOut()
        } catch {
            logoutErrorMessage = ReaderErrorMessage.message(for: error)
        }
    }
}
