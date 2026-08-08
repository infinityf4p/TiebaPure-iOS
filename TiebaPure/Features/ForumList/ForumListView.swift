import SwiftUI

struct ForumListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let account: Account
    @ObservedObject private var blocklistStore = BlocklistStore.shared
    @State private var forums: [Forum] = []
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var requestGeneration = 0
    @State private var loadTask: Task<[Forum], Error>?
    @State private var selectedForum: ForumHubRoute?

    private var visibleForums: [Forum] {
        ForumListPresentationPolicy.visibleForums(
            forums,
            searchText: searchText,
            blocklist: BlocklistSnapshot(entries: blocklistStore.entries)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if didLoad {
                followedForumSearchField
            }

            Group {
                if isLoading && didLoad == false {
                    ReaderStateView.loading("正在加载贴吧")
                } else if let errorMessage, forums.isEmpty {
                    ReaderStateScrollView(refresh: { await reload() }) {
                        ReaderStateView.error(message: errorMessage) {
                            Task { await reload() }
                        }
                    }
                } else if visibleForums.isEmpty {
                    ReaderStateScrollView(refresh: { await reload() }) {
                        ReaderStateView.empty(
                            title: emptyState.title,
                            message: emptyState.message
                        )
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleForums) { forum in
                                Button {
                                    openForum(forum)
                                } label: {
                                    ForumRow(forum: forum)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("进入\(forum.displayName)")
                                .accessibilityIdentifier("followed-forum-row")
                            }

                            if let errorMessage {
                                InlineLoadErrorView(message: errorMessage) {
                                    Task { await reload() }
                                }
                            }
                        }
                        .readableWidth()
                    }
                    .accessibilityIdentifier("followed-forum-list")
                    .shortPullRefresh(
                        isEnabled: didLoad && isLoading == false,
                        surface: .grouped,
                        accessibilityIdentifier: "forum-list-refresh-animation"
                    ) {
                        await reload()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .navigationTitle("关注的吧")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestinationCompat(isPresented: selectedForumIsActive) {
            if let selectedForum {
                ForumThreadsView(account: account, forum: selectedForum.forum)
                    .interactiveNavigationPopStateSync {
                        self.selectedForum = nil
                    }
            }
        }
        .task {
            guard didLoad == false else { return }
            await reload()
        }
        .onReceive(environment.accountStore.accountDidChange) { current in
            guard current?.sessionIdentity != account.sessionIdentity else { return }
            loadTask?.cancel()
            requestGeneration += 1
            forums = []
            selectedForum = nil
            dismiss()
        }
        .onReceive(environment.socialRelationshipState.forumFollowDidChange) { change in
            applyForumFollowChange(change)
        }
        .onChange(of: blocklistStore.entries) { _ in
            guard let selectedForum,
                  ForumListPresentationPolicy.shouldKeep(
                    selectedForum.forum,
                    blocklist: BlocklistSnapshot(entries: blocklistStore.entries)
                  ) == false else { return }
            self.selectedForum = nil
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    SettingsView(account: account)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
        }
        .onDisappear {
            loadTask?.cancel()
            requestGeneration += 1
            isLoading = false
        }
        .fullScreenInteractiveNavigationPop()
    }

    private var followedForumSearchField: some View {
        HStack(spacing: TiebaPureTheme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("搜索贴吧", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityIdentifier("followed-forum-search-field")

            if searchText.isEmpty == false {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .minTouchTarget()
                .accessibilityLabel("清除搜索")
            }
        }
        .frame(minHeight: 44)
        .padding(.leading, TiebaPureTheme.Spacing.sm)
        .padding(.trailing, searchText.isEmpty ? TiebaPureTheme.Spacing.sm : 0)
        .background(
            TiebaPureTheme.ColorToken.readerSecondarySurface,
            in: RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.card)
        )
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.vertical, TiebaPureTheme.Spacing.xs)
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
    }

    private var selectedForumIsActive: Binding<Bool> {
        Binding(
            get: { selectedForum != nil },
            set: { isActive in
                if isActive == false {
                    selectedForum = nil
                }
            }
        )
    }

    private var emptyState: ForumListEmptyState {
        ForumListPresentationPolicy.emptyState(
            hasStoredForums: forums.isEmpty == false,
            hasSearchText: searchText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
        )
    }

    private func openForum(_ forum: Forum) {
        guard ForumListTapPolicy.destination(for: .rowBackground) == .forum else { return }
        RecentForumStore.shared.save(forum)
        selectedForum = ForumHubRoute(forum: forum)
    }

    private func reload() async {
        loadTask?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        let requestedSession = account.sessionIdentity
        isLoading = true
        errorMessage = nil

        do {
            let task = Task { try await environment.api.followedForums(account: account) }
            loadTask = task
            let loaded = try await task.value
            guard generation == requestGeneration,
                  requestedSession == account.sessionIdentity else { return }
            forums = environment.socialRelationshipState.reconciledFollowedForums(
                accountID: account.id,
                loaded: loaded
            )
            environment.socialRelationshipState.seedFollowedForums(
                accountID: account.id,
                forums: forums
            )
        } catch is CancellationError {
            guard generation == requestGeneration,
                  requestedSession == account.sessionIdentity else { return }
            loadTask = nil
            isLoading = false
            return
        } catch {
            guard generation == requestGeneration,
                  requestedSession == account.sessionIdentity else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration,
              requestedSession == account.sessionIdentity else { return }
        loadTask = nil
        isLoading = false
        didLoad = true
    }

    private func applyForumFollowChange(_ change: ForumFollowChange) {
        guard change.accountID == account.id else { return }
        if change.isFollowed {
            if let index = forums.firstIndex(where: {
                SocialRelationshipState.sameForum($0, change.forum)
            }) {
                forums[index] = change.forum
            } else {
                forums.insert(change.forum, at: 0)
            }
        } else {
            forums.removeAll { SocialRelationshipState.sameForum($0, change.forum) }
        }
        didLoad = true
        errorMessage = nil
    }
}

struct ForumListEmptyState: Equatable {
    let title: String
    let message: String?
}

enum ForumListPresentationPolicy {
    static func visibleForums(
        _ forums: [Forum],
        searchText: String,
        blocklist: BlocklistSnapshot
    ) -> [Forum] {
        let filtered = forums.filter { shouldKeep($0, blocklist: blocklist) }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return filtered }
        return filtered.filter { forum in
            forum.displayName.localizedCaseInsensitiveContains(query)
                || forum.name.localizedCaseInsensitiveContains(query)
        }
    }

    static func shouldKeep(
        _ forum: Forum,
        blocklist: BlocklistSnapshot
    ) -> Bool {
        blocklist.blocksForum(
            id: forum.id,
            names: [forum.name, forum.displayName]
        ) == false
    }

    static func emptyState(
        hasStoredForums: Bool,
        hasSearchText: Bool
    ) -> ForumListEmptyState {
        if hasSearchText {
            return ForumListEmptyState(title: "没有匹配结果", message: nil)
        }
        if hasStoredForums {
            return ForumListEmptyState(
                title: "没有可显示的关注贴吧",
                message: "已按你的屏蔽设置隐藏相关贴吧。"
            )
        }
        return ForumListEmptyState(
            title: "暂无关注贴吧",
            message: "下拉即可刷新关注贴吧。"
        )
    }
}

enum ForumListRowTapTarget: CaseIterable {
    case avatar
    case title
    case subtitle
    case rowBackground
    case accessory
}

enum ForumListTapDestination: Equatable {
    case forum
}

enum ForumListTapPolicy {
    static func destination(for _: ForumListRowTapTarget) -> ForumListTapDestination {
        .forum
    }
}

private struct ForumRow: View {
    let forum: Forum

    var body: some View {
        ReaderCard {
            HStack(spacing: TiebaPureTheme.Spacing.sm) {
                AvatarView(url: forum.avatarURL, title: forum.displayName)

                VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                    Text(forum.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    MetadataLine(metadata, systemImage: "text.bubble")
                }

                Spacer(minLength: TiebaPureTheme.Spacing.sm)

                Image(systemName: "chevron.right")
                    .font(.system(size: TiebaPureTheme.IconSize.inline, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .minTouchTarget()
        }
        .accessibilityLabel("\(forum.displayName)，贴吧")
    }

    private var metadata: [String] {
        [
            forum.threadCount > 0 ? "\(forum.threadCount)个帖子" : "",
            forum.memberCount > 0 ? "\(forum.memberCount)位吧友" : ""
        ]
    }
}
