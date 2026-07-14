import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let account: Account

    @State private var confirmsLogout = false
    @State private var isLoggingOut = false
    @State private var logoutErrorMessage: String?

    var body: some View {
        Form {
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

private struct SettingsLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(.primary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(TiebaPureTheme.ColorToken.primaryAccent)
        }
    }
}
