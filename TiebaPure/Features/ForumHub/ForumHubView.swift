import SwiftUI

struct ForumHubView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let account: Account?

    @EnvironmentObject private var signCoordinator: ForumSignCoordinator
    @ObservedObject private var recentStore = RecentForumStore.shared
    @ObservedObject private var blocklistStore = BlocklistStore.shared
    @State private var followedForums: [Forum] = []
    @State private var followedStatuses: [Int64: FollowedForumStatus] = [:]
    @State private var isLoadingFollowed = false
    @State private var didLoadFollowed = false
    @State private var followedError: String?
    @State private var forumInput = ""
    @State private var navigationPath: [ForumHubNavigationRoute] = []
    @State private var splitDetailPath: [ReaderSplitThreadRoute] = []
    @State private var requestGeneration = 0
    @State private var loadTask: Task<[Forum], Error>?
    @State private var statusTask: Task<[FollowedForumStatus], Error>?
    @State private var isManagingRecentForums = false
    @State private var showsClearRecentConfirmation = false
    @State private var showsRecentStorageError = false
    @State private var signSummaryMessage: String?

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
                Section {
                    ForumTileGrid(
                        tiles: visibleRecentForums.map { recent in
                            ForumTile(
                                id: recent.id,
                                title: recent.displayName,
                                avatarURL: recent.avatarURL,
                                forum: recent.forum
                            )
                        },
                        isManaging: isManagingRecentForums,
                        onOpen: openForum,
                        onDelete: { id in removeRecentForums(ids: [id]) }
                    )
                } header: {
                    HStack {
                        Text("最近浏览")
                        Spacer(minLength: TiebaPureTheme.Spacing.sm)
                        if isManagingRecentForums {
                            Button("清空") {
                                showsClearRecentConfirmation = true
                            }
                            .font(.footnote)
                            .textCase(nil)
                            .accessibilityLabel("清空最近浏览的贴吧")
                            .accessibilityIdentifier("forum-hub-recent-clear")

                            Button("完成") {
                                isManagingRecentForums = false
                            }
                            .font(.footnote.weight(.semibold))
                            .textCase(nil)
                            .padding(.leading, TiebaPureTheme.Spacing.sm)
                            .accessibilityIdentifier("forum-hub-recent-manage-done")
                        } else {
                            Button("管理") {
                                isManagingRecentForums = true
                            }
                            .font(.footnote)
                            .textCase(nil)
                            .accessibilityLabel("管理最近浏览的贴吧")
                            .accessibilityIdentifier("forum-hub-recent-manage")
                        }
                    }
                }
            }

            Section {
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
                        ForumTileGrid(
                            tiles: visibleFollowedForums.map { forum in
                                ForumTile(
                                    id: "\(forum.id)-\(forum.name)",
                                    title: forum.displayName,
                                    avatarURL: forum.avatarURL,
                                    forum: forum,
                                    level: followedStatuses[forum.id]?.level ?? 0,
                                    isSignedToday: followedStatuses[forum.id]?.isSignedToday ?? false
                                )
                            },
                            isManaging: false,
                            onOpen: openForum,
                            onDelete: nil
                        )
                    }
                } else {
                    Text("登录后显示关注的贴吧")
                        .foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("关注贴吧")
                    Spacer(minLength: TiebaPureTheme.Spacing.sm)
                    if account != nil, visibleFollowedForums.isEmpty == false {
                        if signCoordinator.isRunning {
                            HStack(spacing: TiebaPureTheme.Spacing.xs) {
                                ProgressView()
                                    .controlSize(.small)
                                    .accessibilityLabel("正在签到")
                                if let progress = signCoordinator.progress {
                                    Text(ForumSignProgressText.counter(for: progress))
                                        .font(.footnote)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                        .accessibilityIdentifier("forum-hub-sign-progress")
                                }
                                Button("取消") {
                                    signCoordinator.cancel()
                                }
                                .font(.footnote)
                                .textCase(nil)
                                .accessibilityLabel("取消签到")
                                .accessibilityIdentifier("forum-hub-sign-cancel")
                            }
                        } else {
                            Button("一键签到") {
                                startSignAllFollowedForums()
                            }
                            .font(.footnote)
                            .textCase(nil)
                            .accessibilityLabel("为关注的贴吧签到")
                            .accessibilityIdentifier("forum-hub-sign-all")
                        }
                    }
                }
            } footer: {
                if let progress = signCoordinator.progress,
                   let currentForum = ForumSignProgressText.currentForum(for: progress) {
                    Text(currentForum)
                        .font(.footnote)
                        .accessibilityIdentifier("forum-hub-sign-current-forum")
                }
            }
        }
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
        .confirmationDialog(
            "清空最近浏览的贴吧？",
            isPresented: $showsClearRecentConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive, action: clearRecentForums)
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会清除本机记录，不影响你关注的贴吧。")
        }
        .alert("无法更新最近浏览", isPresented: $showsRecentStorageError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("本机存储暂时不可用，请稍后再试。")
        }
        .alert("签到", isPresented: signSummaryIsPresented) {
            Button("好", role: .cancel) { signSummaryMessage = nil }
        } message: {
            Text(signSummaryMessage ?? "")
        }
        .interactiveNavigationPopRevealSource()
        .task {
            guard let account, didLoadFollowed == false else { return }
            await loadFollowed(account: account)
        }
        .onChange(of: account?.sessionIdentity) { _ in
            requestGeneration += 1
            loadTask?.cancel()
            statusTask?.cancel()
            followedForums = []
            followedStatuses = [:]
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
            statusTask?.cancel()
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
                    initialDestination: threadRoute.initialDestination,
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

    private var signSummaryIsPresented: Binding<Bool> {
        Binding(
            get: { signSummaryMessage != nil },
            set: { isPresented in
                if isPresented == false { signSummaryMessage = nil }
            }
        )
    }

    private func startSignAllFollowedForums() {
        guard let account, signCoordinator.isRunning == false else { return }
        Task {
            let summary = await signCoordinator.signAllFollowedForums(account: account)
            signSummaryMessage = signCoordinator.lastError
                ?? ForumSignSummaryText.message(for: summary)
            // A check-in changes the level and rank shown next to each forum.
            await loadFollowed(account: account)
        }
    }

    private var visibleRecentForums: [RecentForum] {
        recentStore.items.filter { TiebaContentFilter.shouldKeep(forum: $0.forum) }
    }

    private func removeRecentForums(ids: Set<String>) {
        guard ids.isEmpty == false else { return }
        if recentStore.remove(ids: ids) == false {
            showsRecentStorageError = true
            return
        }
        // The section disappears with its last tile, taking the done button
        // with it, so managing has to end here rather than on the next tap.
        if visibleRecentForums.isEmpty {
            isManagingRecentForums = false
        }
    }

    private func clearRecentForums() {
        if recentStore.clear() == false {
            showsRecentStorageError = true
            return
        }
        isManagingRecentForums = false
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
        statusTask?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        let accountID = account.id
        let requestedSession = account.sessionIdentity
        isLoadingFollowed = true
        followedError = nil

        do {
            let task = Task { try await environment.api.followedForums(account: account) }
            loadTask = task
            // Level and check-in come from a second listing. Start it right
            // away so both requests overlap instead of serializing.
            let statuses = Task { try await environment.api.followedForumStatuses(account: account) }
            statusTask = statuses
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
            // A forum list without a level is still a usable forum list, so a
            // failed status read leaves the tiles unadorned instead of empty.
            // The reason still reaches the diagnostic log, otherwise "no badge"
            // and "wrong field name" look identical from the outside.
            do {
                let reported = try await statuses.value
                guard generation == requestGeneration,
                      requestedSession == self.account?.sessionIdentity else { return }
                followedStatuses = Dictionary(
                    reported.map { ($0.forumID, $0) },
                    uniquingKeysWith: { _, latest in latest }
                )
            } catch is CancellationError {
                return
            } catch {
                await AppLog.shared.recordError("进吧等级", "读取失败，等级与签到不显示", error: error)
            }
        } catch is CancellationError {
            guard generation == requestGeneration,
                  requestedSession == self.account?.sessionIdentity else { return }
            loadTask = nil
            statusTask = nil
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
        statusTask = nil
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

/// The tile's level and check-in state are visual ornaments, so they reach
/// assistive tech as one readable label rather than three loose fragments.
enum ForumTileAccessibilityPolicy {
    static func label(
        title: String,
        level: Int,
        isSignedToday: Bool,
        isManaging: Bool
    ) -> String {
        guard isManaging == false else { return title }
        var parts = ["进入\(title)"]
        if level > 0 {
            parts.append("等级\(level)")
        }
        if isSignedToday {
            parts.append("今日已签到")
        }
        return parts.joined(separator: "，")
    }
}

struct ForumTile: Identifiable, Equatable {
    let id: String
    let title: String
    let avatarURL: URL?
    let forum: Forum
    /// The account's level in this forum; 0 when the status read did not report
    /// one, in which case no level is shown.
    var level: Int = 0
    var isSignedToday: Bool = false
}

/// Forums read as a wall of small squares rather than a list of rows: the name
/// and avatar are the whole point, and a grid fits several times as many on
/// screen.
private struct ForumTileGrid: View {
    let tiles: [ForumTile]
    let isManaging: Bool
    let onOpen: (Forum) -> Void
    let onDelete: ((String) -> Void)?

    private let columns = [
        GridItem(.adaptive(minimum: 76, maximum: 120), spacing: TiebaPureTheme.Spacing.sm)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: TiebaPureTheme.Spacing.md) {
            ForEach(tiles) { tile in
                ForumTileButton(
                    tile: tile,
                    isManaging: isManaging,
                    onOpen: { onOpen(tile.forum) },
                    onDelete: onDelete.map { delete in { delete(tile.id) } }
                )
            }
        }
        .padding(.vertical, TiebaPureTheme.Spacing.xs)
        .listRowInsets(EdgeInsets(
            top: TiebaPureTheme.Spacing.xs,
            leading: TiebaPureTheme.Spacing.md,
            bottom: TiebaPureTheme.Spacing.xs,
            trailing: TiebaPureTheme.Spacing.md
        ))
    }
}

private struct ForumTileButton: View {
    let tile: ForumTile
    let isManaging: Bool
    let onOpen: () -> Void
    let onDelete: (() -> Void)?

    /// One spoken label instead of three loose fragments: the level and the
    /// check-in mark are only useful to assistive tech as part of this row.
    private var accessibilityLabel: String {
        ForumTileAccessibilityPolicy.label(
            title: tile.title,
            level: tile.level,
            isSignedToday: tile.isSignedToday,
            isManaging: isManaging
        )
    }

    var body: some View {
        Button {
            // Managing is a separate mode: a tap there is almost always aimed
            // at the delete badge, so opening the forum would fight the user.
            guard isManaging == false else { return }
            onOpen()
        } label: {
            VStack(spacing: TiebaPureTheme.Spacing.xs) {
                AvatarView(url: tile.avatarURL, title: tile.title, size: 52)
                    // The row already announces the forum name; letting the
                    // avatar add its own would read the name twice.
                    .accessibilityHidden(true)
                    .overlay(alignment: .bottomTrailing) {
                        if tile.isSignedToday {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, Color(uiColor: .systemGreen))
                                .accessibilityHidden(true)
                        }
                    }

                Text(tile.title)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if tile.level > 0 {
                    Text("Lv.\(tile.level)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, TiebaPureTheme.Spacing.xxs)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.chip, style: .continuous)
                                .fill(TiebaPureTheme.ColorToken.readerSecondarySurface)
                        )
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("forum-hub-forum-row")
        .overlay(alignment: .topTrailing) {
            if isManaging, let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.red)
                }
                .buttonStyle(.plain)
                .minTouchTarget()
                .accessibilityLabel("删除\(tile.title)")
                .accessibilityIdentifier("forum-hub-recent-delete")
            }
        }
    }
}
