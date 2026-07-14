import SwiftUI

struct ForumListView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let account: Account
    @State private var forums: [Forum] = []
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var requestGeneration = 0
    @State private var loadTask: Task<[Forum], Error>?
    @State private var selectedForum: ForumHubRoute?

    private var visibleForums: [Forum] {
        guard searchText.isEmpty == false else { return forums }
        return forums.filter { forum in
            forum.displayName.localizedCaseInsensitiveContains(searchText)
                || forum.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
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
                            title: searchText.isEmpty ? "暂无关注贴吧" : "没有匹配结果",
                            message: searchText.isEmpty ? "下拉即可刷新关注贴吧。" : nil
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
                    .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
                }
            }
        .navigationTitle("我的关注吧")
        .navigationDestination(isPresented: selectedForumIsActive) {
            if let selectedForum {
                ForumThreadsView(account: account, forum: selectedForum.forum)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索贴吧")
        .refreshable { await reload() }
        .task {
            guard didLoad == false else { return }
            await reload()
        }
        .onReceive(environment.accountStore.accountDidChange) { current in
            guard current?.id != account.id else { return }
            loadTask?.cancel()
            requestGeneration += 1
            forums = []
            selectedForum = nil
            dismiss()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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

    private func openForum(_ forum: Forum) {
        guard ForumListTapPolicy.destination(for: .rowBackground) == .forum else { return }
        RecentForumStore.shared.save(forum)
        selectedForum = ForumHubRoute(forum: forum)
    }

    private func reload() async {
        loadTask?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        isLoading = true
        errorMessage = nil

        do {
            let task = Task { try await environment.api.followedForums(account: account) }
            loadTask = task
            let loaded = try await task.value
            guard generation == requestGeneration else { return }
            forums = loaded
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            loadTask = nil
            isLoading = false
            return
        } catch {
            guard generation == requestGeneration else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration else { return }
        loadTask = nil
        isLoading = false
        didLoad = true
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
