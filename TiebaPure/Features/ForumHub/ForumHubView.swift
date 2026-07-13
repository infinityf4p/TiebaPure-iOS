import SwiftUI

struct ForumHubView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let account: Account?

    @ObservedObject private var recentStore = RecentForumStore.shared
    @State private var followedForums: [Forum] = []
    @State private var isLoadingFollowed = false
    @State private var didLoadFollowed = false
    @State private var followedError: String?
    @State private var forumInput = ""
    @State private var navigationPath: [ForumHubRoute] = []
    @State private var requestGeneration = 0
    @State private var loadTask: Task<[Forum], Error>?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Form {
                Section("打开贴吧") {
                    HStack(spacing: TiebaPureTheme.Spacing.sm) {
                        TextField("输入吧名", text: $forumInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { openForum(named: forumInput) }

                        Button {
                            openForum(named: forumInput)
                        } label: {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: TiebaPureTheme.IconSize.toolbar))
                        }
                        .buttonStyle(.plain)
                        .minTouchTarget()
                        .disabled(forumInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("进入贴吧")
                    }
                }

                if recentStore.items.isEmpty == false {
                    Section("最近浏览") {
                        ForEach(recentStore.items) { recent in
                            ForumHubForumButton(
                                title: recent.displayName,
                                subtitle: "最近 \(ReaderDateText.string(from: recent.updatedAt))",
                                avatarURL: recent.avatarURL
                            ) {
                                openForum(recent.forum)
                            }
                        }
                    }
                }

                Section("关注贴吧") {
                    if let account {
                        if isLoadingFollowed && didLoadFollowed == false {
                            ProgressView()
                                .accessibilityLabel("正在加载关注贴吧")
                        } else if let followedError, followedForums.isEmpty {
                            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
                                Text("加载失败")
                                    .font(.body.weight(.semibold))
                                Text(followedError)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button("重试") {
                                    Task { await loadFollowed(account: account) }
                                }
                                .buttonStyle(.bordered)
                                .minTouchTarget()
                                .accessibilityHint("重新加载关注贴吧")
                            }
                        } else if followedForums.isEmpty {
                            Text("没有关注贴吧")
                                .foregroundStyle(.secondary)
                        } else {
                            if let followedError {
                                InlineLoadErrorView(message: followedError) {
                                    Task { await loadFollowed(account: account) }
                                }
                            }
                            ForEach(followedForums) { forum in
                                ForumHubForumButton(
                                    title: forum.displayName,
                                    subtitle: forumMetadata(forum),
                                    avatarURL: forum.avatarURL
                                ) {
                                    openForum(forum)
                                }
                            }
                        }
                    } else {
                        Text("登录后显示关注的贴吧")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("进吧")
            .refreshable {
                recentStore.reload()
                if let account {
                    await loadFollowed(account: account)
                }
            }
            .task {
                guard let account, didLoadFollowed == false else { return }
                await loadFollowed(account: account)
            }
            .onChange(of: account?.id) { _ in
                loadTask?.cancel()
                requestGeneration += 1
                followedForums = []
                followedError = nil
                didLoadFollowed = false
                isLoadingFollowed = false
                navigationPath = []
                if let account {
                    Task { await loadFollowed(account: account) }
                }
            }
            .onDisappear {
                loadTask?.cancel()
                requestGeneration += 1
                isLoadingFollowed = false
            }
            .navigationDestination(for: ForumHubRoute.self) { route in
                ForumThreadsView(account: account, forum: route.forum)
            }
        }
    }

    private func openForum(named name: String) {
        guard let route = ForumHubRoutePolicy.route(forInput: name) else { return }
        openForum(route.forum)
    }

    private func openForum(_ forum: Forum) {
        guard ForumHubTapPolicy.destination(for: .rowBackground) == .forum else { return }
        recentStore.save(forum)
        navigationPath.append(ForumHubRoutePolicy.route(for: forum))
    }

    private func loadFollowed(account: Account) async {
        loadTask?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        let accountID = account.id
        isLoadingFollowed = true
        followedError = nil

        do {
            let task = Task { try await environment.api.followedForums(account: account) }
            loadTask = task
            let loaded = try await task.value
            guard generation == requestGeneration, accountID == self.account?.id else { return }
            followedForums = loaded
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            loadTask = nil
            isLoadingFollowed = false
            return
        } catch {
            guard generation == requestGeneration, accountID == self.account?.id else { return }
            followedError = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration else { return }
        loadTask = nil
        isLoadingFollowed = false
        didLoadFollowed = true
    }

    private func forumMetadata(_ forum: Forum) -> String {
        [
            forum.threadCount > 0 ? "\(forum.threadCount)个帖子" : "",
            forum.memberCount > 0 ? "\(forum.memberCount)位吧友" : ""
        ]
        .filter { $0.isEmpty == false }
        .joined(separator: " · ")
    }
}

struct ForumHubRoute: Hashable {
    private let forumID: Int64
    private let name: String
    private let displayName: String
    private let avatarURL: URL?
    private let memberCount: Int
    private let threadCount: Int

    init(forum: Forum) {
        forumID = forum.id
        name = forum.name
        displayName = forum.displayName
        avatarURL = forum.avatarURL
        memberCount = forum.memberCount
        threadCount = forum.threadCount
    }

    var forum: Forum {
        Forum(
            id: forumID,
            name: name,
            displayName: displayName,
            avatarURL: avatarURL,
            memberCount: memberCount,
            threadCount: threadCount
        )
    }
}

enum ForumHubRoutePolicy {
    static func route(forInput input: String) -> ForumHubRoute? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return ForumHubRoute(
            forum: Forum(
                id: 0,
                name: trimmed,
                displayName: "\(trimmed)吧",
                avatarURL: nil,
                memberCount: 0,
                threadCount: 0
            )
        )
    }

    static func route(for forum: Forum) -> ForumHubRoute {
        ForumHubRoute(forum: forum)
    }
}

enum ForumHubRowTapTarget: CaseIterable {
    case avatar
    case title
    case subtitle
    case rowBackground
    case accessory
}

enum ForumHubTapDestination: Equatable {
    case forum
}

enum ForumHubTapPolicy {
    static func destination(for _: ForumHubRowTapTarget) -> ForumHubTapDestination {
        .forum
    }
}

private struct ForumHubForumButton: View {
    let title: String
    let subtitle: String
    let avatarURL: URL?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ForumSummaryRow(title: title, subtitle: subtitle, avatarURL: avatarURL)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("进入\(title)")
        .accessibilityIdentifier("forum-hub-forum-row")
    }
}

private struct ForumSummaryRow: View {
    let title: String
    let subtitle: String
    let avatarURL: URL?

    var body: some View {
        HStack(spacing: TiebaPureTheme.Spacing.sm) {
            AvatarView(url: avatarURL, title: title)

            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                if subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: TiebaPureTheme.Spacing.sm)

            Image(systemName: "chevron.right")
                .font(.system(size: TiebaPureTheme.IconSize.inline, weight: .semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .minTouchTarget()
    }
}
