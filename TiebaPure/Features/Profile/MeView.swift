import SwiftUI

struct MeView: View {
    let account: Account?

    @ObservedObject private var browsingHistoryStore = BrowsingHistoryStore.shared
    @ObservedObject private var localThreadLibraryStore = LocalThreadLibraryStore.shared
    @ObservedObject private var blocklistStore = BlocklistStore.shared
    @State private var showsLogin = false
    @State private var showsMessages = false
    @State private var showsFollowedForums = false
    @State private var showsOwnProfile = false
    @State private var showsBrowsingHistory = false
    @State private var showsFollowedUsers = false
    @State private var showsThreadFavorites = false
    @State private var showsSettings = false
    @State private var showsAbout = false

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

                        Button {
                            showsMessages = true
                        } label: {
                            Label("消息", systemImage: "bell")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("消息")
                        .accessibilityHint("查看回复我的和@我的消息")
                        .accessibilityIdentifier("me-messages-entry")

                        Button {
                            showsFollowedUsers = true
                        } label: {
                            Label("关注的用户", systemImage: "person.2")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("查看当前账号关注的用户")
                        .accessibilityIdentifier("followed-users-entry")

                        Button {
                            showsFollowedForums = true
                        } label: {
                            Label("关注的吧", systemImage: "star")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关注的吧")
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
                    Button {
                        showsThreadFavorites = true
                    } label: {
                        HStack(spacing: TiebaPureTheme.Spacing.sm) {
                            Label("帖子收藏", systemImage: "star")
                            Spacer(minLength: TiebaPureTheme.Spacing.sm)
                            if visibleFavoriteCount > 0 {
                                Text("\(visibleFavoriteCount)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(threadFavoritesAccessibilityLabel)
                    .accessibilityHint("查看本机收藏的帖子")
                    .accessibilityIdentifier("thread-favorites-entry")

                    Button {
                        showsBrowsingHistory = true
                    } label: {
                        HStack(spacing: TiebaPureTheme.Spacing.sm) {
                            Label("浏览历史", systemImage: "clock.arrow.circlepath")
                            Spacer(minLength: TiebaPureTheme.Spacing.sm)
                            if visibleHistoryCount > 0 {
                                Text("\(visibleHistoryCount)")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(browsingHistoryAccessibilityLabel)
                    .accessibilityHint("查看本机保存的帖子浏览记录")
                    .accessibilityIdentifier("browsing-history-entry")
                }

                Section("应用") {
                    Button {
                        showsSettings = true
                    } label: {
                        Label("设置", systemImage: "gearshape")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("调整显示模式和其他应用设置")
                    .accessibilityIdentifier("app-settings-entry")

                    Button {
                        showsAbout = true
                    } label: {
                        Label("关于 TiebaPure", systemImage: "info.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("查看来源、许可证和源码链接")
                }
            }
            .hidesBottomTabBarScrollEdgeEffect()
            .navigationTitle("我的")
            .interactiveNavigationPopRevealSource()
            .navigationDestination(isPresented: $showsBrowsingHistory) {
                BrowsingHistoryView(account: account)
                    .interactiveNavigationPopStateSync {
                        showsBrowsingHistory = false
                    }
            }
            .navigationDestination(isPresented: $showsThreadFavorites) {
                ThreadFavoritesView(account: account)
                    .interactiveNavigationPopStateSync {
                        showsThreadFavorites = false
                    }
            }
            .navigationDestination(isPresented: $showsSettings) {
                SettingsView(account: account)
                    .interactiveNavigationPopStateSync {
                        showsSettings = false
                    }
            }
            .navigationDestination(isPresented: $showsAbout) {
                AboutView()
                    .interactiveNavigationPopStateSync {
                        showsAbout = false
                    }
            }
            .navigationDestination(isPresented: $showsMessages) {
                if let account {
                    MessagesView(account: account)
                        .interactiveNavigationPopStateSync {
                            showsMessages = false
                        }
                }
            }
            .navigationDestination(isPresented: $showsFollowedForums) {
                if let account {
                    ForumListView(account: account)
                        .interactiveNavigationPopStateSync {
                            showsFollowedForums = false
                        }
                }
            }
            .navigationDestination(isPresented: $showsFollowedUsers) {
                if let account {
                    FollowedUsersView(account: account)
                        .interactiveNavigationPopStateSync {
                            showsFollowedUsers = false
                        }
                }
            }
            .navigationDestination(isPresented: $showsOwnProfile) {
                if let account {
                    UserProfileView(account: account, user: userSummary(for: account))
                        .interactiveNavigationPopStateSync {
                            showsOwnProfile = false
                        }
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
                    showsMessages = false
                    showsFollowedForums = false
                    showsOwnProfile = false
                    showsBrowsingHistory = false
                    showsFollowedUsers = false
                    showsThreadFavorites = false
                    showsSettings = false
                    showsAbout = false
                }
            }
        }
        .toolbar(.visible, for: .tabBar)
    }

    private var threadFavoritesAccessibilityLabel: String {
        guard visibleFavoriteCount > 0 else { return "帖子收藏" }
        return "帖子收藏，共 \(visibleFavoriteCount) 条"
    }

    private var browsingHistoryAccessibilityLabel: String {
        guard visibleHistoryCount > 0 else { return "浏览历史" }
        return "浏览历史，共 \(visibleHistoryCount) 条"
    }

    private var currentBlocklist: BlocklistSnapshot {
        BlocklistSnapshot(entries: blocklistStore.entries)
    }

    private var visibleFavoriteCount: Int {
        ThreadFavoritesListPolicy.visibleFavorites(
            localThreadLibraryStore.favorites,
            blocklist: currentBlocklist
        ).count
    }

    private var visibleHistoryCount: Int {
        BrowsingHistoryListPolicy.visibleEntries(
            browsingHistoryStore.items,
            blocklist: currentBlocklist
        ).count
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
