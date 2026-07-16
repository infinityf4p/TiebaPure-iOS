import SwiftUI

struct FollowedUsersView: View {
    @EnvironmentObject private var environment: AppEnvironment

    let account: Account

    @State private var users: [UserSummary] = []
    @State private var nextPage = 1
    @State private var totalCount = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var requestGeneration = 0
    @State private var loadTask: Task<FollowedUsersPage, Error>?

    var body: some View {
        Group {
            if isLoading, didLoad == false {
                ReaderStateView.loading("正在加载关注用户")
            } else if let errorMessage, users.isEmpty {
                ReaderStateScrollView(refresh: { await reload() }) {
                    ReaderStateView.error(message: errorMessage) {
                        Task { await reload() }
                    }
                }
            } else if users.isEmpty {
                ReaderStateScrollView(refresh: { await reload() }) {
                    ReaderStateView.empty(
                        title: "还没有关注用户",
                        message: "在用户主页点击关注后，会显示在这里。"
                    )
                }
            } else {
                List {
                    ForEach(Array(users.enumerated()), id: \.offset) { index, user in
                        NavigationLink {
                            UserProfileView(account: account, user: user)
                        } label: {
                            FollowedUserRow(user: user)
                        }
                        .accessibilityIdentifier("followed-user-row-\(user.id)")
                        .onAppear {
                            guard PaginationPrefetchPolicy.shouldLoadMore(
                                currentIndex: index,
                                totalCount: users.count
                            ) else { return }
                            Task { await loadMore() }
                        }
                    }

                    if isLoading, didLoad {
                        HStack {
                            Spacer()
                            ProgressView()
                                .accessibilityLabel("正在加载更多关注用户")
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }

                    if let errorMessage {
                        InlineLoadErrorView(message: errorMessage) {
                            Task { await loadMore() }
                        }
                        .listRowSeparator(.hidden)
                    } else if hasMore == false, totalCount > 0 {
                        Text("已显示 \(users.count) 位关注用户")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowSeparator(.hidden)
                            .accessibilityLabel("已显示\(users.count)位关注用户")
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await reload()
                }
            }
        }
        .navigationTitle("关注的用户")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard didLoad == false else { return }
            await reload()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
            requestGeneration += 1
            isLoading = false
        }
        .accessibilityIdentifier("followed-users-screen")
        .fullScreenInteractiveNavigationPop()
    }

    private func reload() async {
        loadTask?.cancel()
        requestGeneration += 1
        isLoading = false
        nextPage = 1
        hasMore = true
        errorMessage = nil
        await loadMore(generation: requestGeneration, replacing: true)
    }

    private func loadMore() async {
        await loadMore(generation: requestGeneration, replacing: false)
    }

    private func loadMore(generation: Int, replacing: Bool) async {
        guard isLoading == false, hasMore || replacing else { return }
        let requestedPage = replacing ? 1 : nextPage
        isLoading = true
        errorMessage = nil

        do {
            let task = Task {
                try await environment.api.followedUsers(account: account, page: requestedPage)
            }
            loadTask = task
            let page = try await task.value
            guard generation == requestGeneration else { return }
            if replacing {
                users = deduplicated(page.users)
            } else {
                users = deduplicated(users + page.users)
            }
            totalCount = page.totalCount
            hasMore = page.hasMore
            nextPage = max(page.currentPage, requestedPage) + 1
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

    private func deduplicated(_ candidates: [UserSummary]) -> [UserSummary] {
        var seen = Set<String>()
        return candidates.filter { user in
            let key: String
            if user.id != 0 {
                key = "id:\(user.id)"
            } else if user.portrait.isEmpty == false {
                key = "portrait:\(user.portrait)"
            } else {
                key = "name:\(user.name)|\(user.displayName)"
            }
            return seen.insert(key).inserted
        }
    }
}

private struct FollowedUserRow: View {
    let user: UserSummary

    var body: some View {
        HStack(spacing: TiebaPureTheme.Spacing.sm) {
            AvatarView(
                url: user.portraitURL,
                title: user.displayNameResolved,
                size: TiebaPureTheme.AvatarSize.medium
            )

            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                Text(user.displayNameResolved)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if secondaryName.isEmpty == false {
                    Text(secondaryName)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: TiebaPureTheme.Spacing.sm)
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .padding(.vertical, TiebaPureTheme.Spacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("打开用户主页")
    }

    private var secondaryName: String {
        let trimmedName = user.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedName.isEmpty == false, trimmedName != user.displayNameResolved else { return "" }
        return "@\(trimmedName)"
    }

    private var accessibilityText: String {
        secondaryName.isEmpty ? user.displayNameResolved : "\(user.displayNameResolved)，\(secondaryName)"
    }
}
