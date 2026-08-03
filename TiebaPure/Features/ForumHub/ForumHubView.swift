import SwiftUI

struct ForumHubView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let account: Account?

    @ObservedObject private var recentStore = RecentForumStore.shared
    @ObservedObject private var blocklistStore = BlocklistStore.shared
    @State private var followedForums: [Forum] = []
    @State private var isLoadingFollowed = false
    @State private var didLoadFollowed = false
    @State private var followedError: String?
    @State private var forumInput = ""
    @State private var navigationPath: [ForumHubNavigationRoute] = []
    @State private var splitDetailPath: [ReaderSplitThreadRoute] = []
    @State private var requestGeneration = 0
    @State private var loadTask: Task<[Forum], Error>?

    var body: some View {
        ReaderSplitLayout(
            account: account,
            navigationPath: $navigationPath,
            detailPath: $splitDetailPath,
            openThreadInDetail: { route in
                splitDetailPath = [route]
            },
            openThreadInCompact: { route in
                openThreadFromForum(route)
            },
            listColumn: { hubColumn }
        )
        .toolbar(.visible, for: .tabBar)
        .onChange(of: horizontalSizeClass) { sizeClass in
            bridgeDetailForSizeClassChange(to: sizeClass)
        }
    }

    private var hubColumn: some View {
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

            if visibleRecentForums.isEmpty == false {
                Section("最近浏览") {
                    ForEach(visibleRecentForums) { recent in
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
                    } else if let followedError, visibleFollowedForums.isEmpty {
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
                    } else if visibleFollowedForums.isEmpty {
                        Text("没有关注贴吧")
                            .foregroundStyle(.secondary)
                    } else {
                        if let followedError {
                            InlineLoadErrorView(message: followedError) {
                                Task { await loadFollowed(account: account) }
                            }
                        }
                        ForEach(visibleFollowedForums) { forum in
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
        .hidesBottomTabBarScrollEdgeEffect()
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("forum-hub-list")
        .shortPullRefresh(
            isEnabled: isLoadingFollowed == false,
            surface: .grouped,
            accessibilityIdentifier: "forum-hub-refresh-animation"
        ) {
            recentStore.reload()
            if let account {
                await loadFollowed(account: account)
            }
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .navigationTitle("进吧")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveNavigationPopRevealSource()
        .task {
            guard let account, didLoadFollowed == false else { return }
            await loadFollowed(account: account)
        }
        .onChange(of: account?.sessionIdentity) { _ in
            requestGeneration += 1
            loadTask?.cancel()
            followedForums = []
            followedError = nil
            didLoadFollowed = false
            isLoadingFollowed = false
            navigationPath = []
            splitDetailPath = []
            if let account {
                Task { await loadFollowed(account: account) }
            }
        }
        .onReceive(environment.socialRelationshipState.forumFollowDidChange) { change in
            applyForumFollowChange(change)
        }
        .onDisappear {
            loadTask?.cancel()
            requestGeneration += 1
            isLoadingFollowed = false
        }
        .navigationDestination(for: ForumHubNavigationRoute.self) { route in
            switch route {
            case let .forum(forumRoute):
                ForumThreadsView(
                    account: account,
                    forum: forumRoute.forum,
                    openThreadInParent: openThreadFromForum,
                    openSearchInParent: openSearchFromForum,
                    openUserInParent: { user in
                        openUser(user, sourceThreadID: nil)
                    }
                )
            case let .thread(threadRoute):
                ThreadDetailView(
                    account: account,
                    threadID: threadRoute.threadID,
                    forumID: threadRoute.forumID,
                    initialPostID: threadRoute.initialPostID,
                    ownThreadDeletionTarget: threadRoute.ownThreadDeletionTarget,
                    openSearchInParent: { scope in
                        openSearch(scope)
                    },
                    openUserInParent: { user in
                        openUser(user, sourceThreadID: threadRoute.threadID)
                    },
                    openForumInParent: openForum
                )
                .id(threadRoute)
            case let .search(searchRoute):
                SearchResultsView(
                    account: account,
                    scope: .forum(searchRoute.forum.forum),
                    initialKeyword: searchRoute.keyword,
                    openThreadInParent: { route in
                        openThreadFromForum(
                            ReaderSplitThreadRoute(
                                threadID: route.threadID,
                                forumID: route.forumID,
                                initialPostID: route.postID
                            )
                        )
                    },
                    openForumInParent: openForum,
                    openUserInParent: { user in
                        openUser(user, sourceThreadID: nil)
                    }
                )
            case let .user(user, sourceThreadID):
                UserProfileView(
                    account: account,
                    user: user,
                    sourceThreadID: sourceThreadID,
                    onReturnToSourceThread: {
                        removeNavigationRouteIfCurrent(route)
                    },
                    openThreadInParent: openThreadFromForum,
                    openForumInParent: openForum
                )
            }
        }
    }

    private var visibleRecentForums: [RecentForum] {
        recentStore.items.filter { TiebaContentFilter.shouldKeep(forum: $0.forum) }
    }

    private var visibleFollowedForums: [Forum] {
        followedForums.filter(TiebaContentFilter.shouldKeep(forum:))
    }

    private func bridgeDetailForSizeClassChange(to sizeClass: UserInterfaceSizeClass?) {
        let bridged = ForumHubSplitDetailBridgePolicy.state(
            changingTo: sizeClass,
            navigationPath: navigationPath,
            splitDetail: splitDetailPath.last
        )
        navigationPath = bridged.navigationPath
        splitDetailPath = bridged.splitDetail.map { [$0] } ?? []
    }

    private func openThreadFromForum(_ route: ReaderSplitThreadRoute) {
        if horizontalSizeClass == .regular {
            splitDetailPath = [route]
        } else {
            navigationPath.append(.thread(route))
        }
    }

    private func openSearchFromForum(_ route: ForumSearchLaunchRoute) {
        openSearch(route.scope, keyword: route.keyword)
    }

    private func openSearch(_ scope: SearchScope, keyword: String = "") {
        guard let route = ForumHubSearchRoutePolicy.route(
            scope: scope,
            keyword: keyword,
            navigationPath: navigationPath
        ) else { return }
        navigationPath.append(.search(route))
    }

    private func openUser(_ user: UserSummary, sourceThreadID: Int64?) {
        navigationPath.append(.user(user: user, sourceThreadID: sourceThreadID))
    }

    private func removeNavigationRouteIfCurrent(_ route: ForumHubNavigationRoute) {
        guard navigationPath.last == route else { return }
        navigationPath.removeLast()
    }

    private func openForum(named name: String) {
        guard let route = ForumHubRoutePolicy.route(forInput: name) else { return }
        openForum(route.forum)
    }

    private func openForum(_ forum: Forum) {
        guard ForumHubTapPolicy.destination(for: .rowBackground) == .forum else { return }
        recentStore.save(forum)
        navigationPath.append(.forum(ForumHubRoutePolicy.route(for: forum)))
    }

    private func loadFollowed(account: Account) async {
        loadTask?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        let accountID = account.id
        let requestedSession = account.sessionIdentity
        isLoadingFollowed = true
        followedError = nil

        do {
            let task = Task { try await environment.api.followedForums(account: account) }
            loadTask = task
            let loaded = try await task.value
            guard generation == requestGeneration,
                  requestedSession == self.account?.sessionIdentity else { return }
            followedForums = environment.socialRelationshipState.reconciledFollowedForums(
                accountID: accountID,
                loaded: loaded
            )
            environment.socialRelationshipState.seedFollowedForums(
                accountID: accountID,
                forums: followedForums
            )
        } catch is CancellationError {
            guard generation == requestGeneration,
                  requestedSession == self.account?.sessionIdentity else { return }
            loadTask = nil
            isLoadingFollowed = false
            return
        } catch {
            guard generation == requestGeneration,
                  requestedSession == self.account?.sessionIdentity else { return }
            followedError = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration,
              requestedSession == self.account?.sessionIdentity else { return }
        loadTask = nil
        isLoadingFollowed = false
        didLoadFollowed = true
    }

    private func applyForumFollowChange(_ change: ForumFollowChange) {
        guard change.accountID == account?.id else { return }
        if change.isFollowed {
            if let index = followedForums.firstIndex(where: {
                SocialRelationshipState.sameForum($0, change.forum)
            }) {
                followedForums[index] = change.forum
            } else {
                followedForums.insert(change.forum, at: 0)
            }
        } else {
            followedForums.removeAll {
                SocialRelationshipState.sameForum($0, change.forum)
            }
        }
        didLoadFollowed = true
        followedError = nil
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

enum ForumHubNavigationRoute: Hashable {
    case forum(ForumHubRoute)
    case thread(ReaderSplitThreadRoute)
    case search(ForumHubSearchRoute)
    case user(user: UserSummary, sourceThreadID: Int64?)
}

struct ForumHubSearchRoute: Hashable {
    let forum: ForumHubRoute
    let keyword: String
}

enum ForumHubSearchRoutePolicy {
    static func route(
        scope: SearchScope,
        keyword: String,
        navigationPath: [ForumHubNavigationRoute]
    ) -> ForumHubSearchRoute? {
        let forumRoute: ForumHubRoute
        switch scope {
        case let .forum(forum):
            forumRoute = ForumHubRoutePolicy.route(for: forum)
        case .global:
            guard let inferredForum = navigationPath.reversed().lazy.compactMap({
                switch $0 {
                case let .forum(route):
                    return route
                case let .search(route):
                    return route.forum
                case .thread, .user:
                    return nil
                }
            }).first else {
                return nil
            }
            forumRoute = inferredForum
        }
        return ForumHubSearchRoute(forum: forumRoute, keyword: keyword)
    }
}

struct ForumHubSplitDetailBridgeState: Equatable {
    var navigationPath: [ForumHubNavigationRoute]
    var splitDetail: ReaderSplitThreadRoute?
}

enum ForumHubSplitDetailBridgePolicy {
    static func state(
        changingTo sizeClass: UserInterfaceSizeClass?,
        navigationPath: [ForumHubNavigationRoute],
        splitDetail: ReaderSplitThreadRoute?
    ) -> ForumHubSplitDetailBridgeState {
        switch sizeClass {
        case .compact:
            guard let splitDetail else {
                return ForumHubSplitDetailBridgeState(
                    navigationPath: navigationPath,
                    splitDetail: nil
                )
            }
            var compactPath = navigationPath
            if compactPath.contains(.thread(splitDetail)) == false {
                compactPath.append(.thread(splitDetail))
            }
            return ForumHubSplitDetailBridgeState(
                navigationPath: compactPath,
                splitDetail: nil
            )
        case .regular:
            guard case let .thread(compactDetail)? = navigationPath.last else {
                return ForumHubSplitDetailBridgeState(
                    navigationPath: navigationPath,
                    splitDetail: splitDetail
                )
            }
            var regularPath = navigationPath
            regularPath.removeLast()
            return ForumHubSplitDetailBridgeState(
                navigationPath: regularPath,
                splitDetail: compactDetail
            )
        default:
            return ForumHubSplitDetailBridgeState(
                navigationPath: navigationPath,
                splitDetail: splitDetail
            )
        }
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
