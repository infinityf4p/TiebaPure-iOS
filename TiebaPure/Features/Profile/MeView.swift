import SwiftUI

struct MeView: View {
    let account: Account?

    @ObservedObject private var browsingHistoryStore = BrowsingHistoryStore.shared
    @ObservedObject private var localThreadLibraryStore = LocalThreadLibraryStore.shared
    @State private var showsLogin = false
    @State private var showsFollowedForums = false
    @State private var showsOwnProfile = false

    var body: some View {
        NavigationStack {
            Form {
                if let account {
                    Section("账号") {
                        Button {
                            showsOwnProfile = true
                        } label: {
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

                                    Text("UID \(account.uid)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: TiebaPureTheme.Spacing.sm)

                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, TiebaPureTheme.Spacing.xs)
                        .accessibilityLabel("查看\(account.displayName)的用户主页")
                        .accessibilityHint("打开自己的用户主页")
                        .accessibilityIdentifier("me-user-profile-button")

                        NavigationLink {
                            FollowedUsersView(account: account)
                        } label: {
                            Label("关注的用户", systemImage: "person.2")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .accessibilityHint("查看当前账号关注的用户")
                        .accessibilityIdentifier("followed-users-entry")

                        Button {
                            showsFollowedForums = true
                        } label: {
                            Label("我的关注吧", systemImage: "star")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("我的关注吧")
                        .accessibilityHint("打开已关注的贴吧列表")
                    }
                } else {
                    Section("账号") {
                        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
                            Label("未登录也可以浏览公开帖子", systemImage: "book")
                                .font(.body)

                            Button {
                                showsLogin = true
                            } label: {
                                Label("手机号验证码登录", systemImage: "iphone.gen2")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .accessibilityHint("打开百度移动登录页，使用手机号和验证码登录。")
                        }
                        .padding(.vertical, TiebaPureTheme.Spacing.xs)
                    }
                }

                Section("浏览") {
                    NavigationLink {
                        ThreadFavoritesView(account: account)
                    } label: {
                        HStack(spacing: TiebaPureTheme.Spacing.sm) {
                            Label("帖子收藏", systemImage: "star")
                            Spacer(minLength: TiebaPureTheme.Spacing.sm)
                            if localThreadLibraryStore.favorites.isEmpty == false {
                                Text("\(localThreadLibraryStore.favorites.count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(threadFavoritesAccessibilityLabel)
                    .accessibilityHint("查看本机收藏的帖子")
                    .accessibilityIdentifier("thread-favorites-entry")

                    NavigationLink {
                        BrowsingHistoryView(account: account)
                    } label: {
                        HStack(spacing: TiebaPureTheme.Spacing.sm) {
                            Label("浏览历史", systemImage: "clock.arrow.circlepath")
                            Spacer(minLength: TiebaPureTheme.Spacing.sm)
                            if browsingHistoryStore.items.isEmpty == false {
                                Text("\(browsingHistoryStore.items.count)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityLabel(browsingHistoryAccessibilityLabel)
                    .accessibilityHint("查看本机保存的帖子浏览记录")
                    .accessibilityIdentifier("browsing-history-entry")
                }

                Section("应用") {
                    NavigationLink {
                        SettingsView(account: account)
                    } label: {
                        Label("设置", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityHint("调整显示模式和其他应用设置")
                    .accessibilityIdentifier("app-settings-entry")

                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("关于 TiebaPure", systemImage: "info.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityHint("查看来源、许可证和源码链接")
                }
            }
            .navigationTitle("我的")
            .navigationDestination(isPresented: $showsFollowedForums) {
                if let account {
                    ForumListView(account: account)
                }
            }
            .navigationDestination(isPresented: $showsOwnProfile) {
                if let account {
                    UserProfileView(account: account, user: userSummary(for: account))
                }
            }
            .sheet(isPresented: $showsLogin) {
                NavigationStack {
                    LoginView()
                        .navigationTitle("手机号验证码登录")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("关闭") {
                                    showsLogin = false
                                }
                            }
                        }
                }
            }
            .onChange(of: account?.id) { newValue in
                if newValue != nil {
                    showsLogin = false
                } else {
                    showsFollowedForums = false
                    showsOwnProfile = false
                }
            }
        }
        .toolbar(.visible, for: .tabBar)
    }

    private var threadFavoritesAccessibilityLabel: String {
        guard localThreadLibraryStore.favorites.isEmpty == false else { return "帖子收藏" }
        return "帖子收藏，共 \(localThreadLibraryStore.favorites.count) 条"
    }

    private var browsingHistoryAccessibilityLabel: String {
        guard browsingHistoryStore.items.isEmpty == false else { return "浏览历史" }
        return "浏览历史，共 \(browsingHistoryStore.items.count) 条"
    }

    private func userSummary(for account: Account) -> UserSummary {
        UserSummary(
            id: Int64(account.uid) ?? 0,
            name: account.name,
            displayName: account.displayName,
            portrait: account.portrait
        )
    }
}
