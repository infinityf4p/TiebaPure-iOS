import SwiftUI
import UIKit

struct ThreadDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var localThreadLibraryStore = LocalThreadLibraryStore.shared
    @ObservedObject private var blocklistStore = BlocklistStore.shared
    let account: Account?
    let threadID: Int64
    let forumID: Int64?
    let initialPostID: UInt64?
    private let openSearchInParent: ((SearchScope) -> Void)?
    private let openUserInParent: ((UserSummary) -> Void)?
    private let openForumInParent: ((Forum) -> Void)?

    @State private var threadPage: ThreadPage?
    @State private var posts: [Post] = []
    @State private var nextPage = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var didRecordBrowsingHistory = false
    @State private var errorMessage: String?
    @State private var seeLz = false
    @State private var sortType: ThreadReplySort = .hot
    @State private var selectedSubpostPost: Post?
    @State private var selectedUser: UserSummary?
    @State private var userResolutionTask: Task<Void, Never>?
    @State private var userResolutionGeneration = 0
    @State private var userResolutionError: String?
    @State private var isSearchActive = false
    @State private var didCopyLink = false
    @State private var pendingInitialPostID: UInt64?
    @State private var requestGeneration = 0
    @State private var loadTask: Task<ThreadPage, Error>?
    @State private var scrollDistanceFromTop: CGFloat = 0
    @State private var showsInlineRefreshAnimation = false
    @State private var inlineRefreshAnimationToken = 0
    @State private var savedReadingPosition: ThreadReadingPosition?
    @State private var restoredReadingFloor: Int?
    @State private var showsRestoredReadingBanner = false
    @State private var restoredBannerHideTask: Task<Void, Never>?
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var didResolveSavedReadingPosition = false
    @State private var isResumingReadingPosition = false
    @State private var scrollRequest: ThreadPostScrollRequest?
    @State private var pendingPreciseScrollPostID: UInt64?
    @State private var preciseScrollRetryCount = 0
    @State private var preciseScrollDeadline: Date?
    @State private var lastRecordedReadingPostID: UInt64?
    @State private var didMoveAwayFromTop = false
    @State private var updatingPostLikeIDs = Set<UInt64>()
    @State private var postLikeTasks: [UInt64: Task<Void, Never>] = [:]
    @State private var likeActionError: String?

    init(
        account: Account?,
        threadID: Int64,
        forumID: Int64? = nil,
        initialPostID: UInt64? = nil,
        openSearchInParent: ((SearchScope) -> Void)? = nil,
        openUserInParent: ((UserSummary) -> Void)? = nil,
        openForumInParent: ((Forum) -> Void)? = nil
    ) {
        self.account = account
        self.threadID = threadID
        self.forumID = forumID
        self.initialPostID = initialPostID
        self.openSearchInParent = openSearchInParent
        self.openUserInParent = openUserInParent
        self.openForumInParent = openForumInParent
        _pendingInitialPostID = State(initialValue: initialPostID)
    }

    var body: some View {
        Group {
            if isLoading && didLoad == false {
                ReaderStateView.loading(
                    isResumingReadingPosition ? "正在恢复上次阅读位置" : "正在加载帖子"
                )
            } else if let errorMessage, posts.isEmpty {
                ReaderStateScrollView(refresh: { await reload() }) {
                    ReaderStateView.error(message: errorMessage) {
                        Task { await reload() }
                    }
                }
            } else if posts.isEmpty {
                ReaderStateScrollView(refresh: { await reload() }) {
                    ReaderStateView.empty(
                        title: "暂无内容",
                        message: "下拉即可刷新帖子。",
                        actionTitle: hasMore && didLoad ? "继续加载" : nil,
                        action: hasMore && didLoad ? { Task { await loadMore() } } : nil
                    )
                }
            } else {
                refreshablePostScrollView {
                    LazyVStack(spacing: 0) {
                        if let mainPost {
                            PostRowView(
                                post: mainPost,
                                threadTitle: threadPage?.thread.title,
                                threadAuthorID: threadAuthorID,
                                isMainPost: true,
                                onOpenSubposts: openSubpostsIfPossible,
                                onOpenUser: openUser,
                                isLikeUpdating: updatingPostLikeIDs.contains(mainPost.id),
                                onToggleLike: {
                                    toggleLike(for: mainPost, objectType: .thread)
                                }
                            )
                            .padding(.bottom, TiebaPureTheme.Spacing.xs)
                            .threadReadingAnchor(post: mainPost)
                            .id(mainPost.id)
                        }

                        Section {
                            if replyPosts.isEmpty, isLoading == false {
                                ReaderStateView.empty(
                                    title: "暂无回复",
                                    message: seeLz ? "这个帖子暂时没有楼主回复。" : "这个帖子暂时没有更多回复。",
                                    actionTitle: hasMore ? "继续加载" : nil,
                                    action: hasMore ? { Task { await loadMore() } } : nil
                                )
                                    .frame(maxWidth: .infinity)
                                    .background(Color(uiColor: .systemBackground))
                            } else {
                                ForEach(Array(replyPosts.enumerated()), id: \.element.id) { index, post in
                                    PostRowView(
                                        post: post,
                                        threadAuthorID: threadAuthorID,
                                        onOpenSubposts: openSubpostsIfPossible,
                                        onOpenUser: openUser,
                                        isLikeUpdating: updatingPostLikeIDs.contains(post.id),
                                        onToggleLike: {
                                            toggleLike(for: post, objectType: .post)
                                        }
                                    )
                                    .threadReadingAnchor(post: post)
                                    .id(post.id)
                                    .onAppear {
                                        guard PaginationPrefetchPolicy.shouldLoadMore(
                                            currentIndex: index,
                                            totalCount: replyPosts.count
                                        ) else { return }
                                        Task { await loadMore() }
                                    }
                                }
                            }

                            if isLoading, didLoad, nextPage > 1 {
                                ProgressView()
                                    .padding(TiebaPureTheme.Spacing.md)
                                    .accessibilityLabel("正在加载更多回复")
                            }

                            if let errorMessage {
                                InlineLoadErrorView(message: errorMessage) {
                                    Task {
                                        if nextPage <= 1 { await reload() } else { await loadMore() }
                                    }
                                }
                            } else if hasMore, isLoading == false, didLoad {
                                Button {
                                    Task { await loadMore() }
                                } label: {
                                    Label("加载更多回复", systemImage: "arrow.down.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .minTouchTarget()
                                .padding(.horizontal, TiebaPureTheme.Spacing.md)
                                .accessibilityIdentifier("thread-replies-load-more")
                            }
                        } header: {
                            ReplyControlBar(
                                seeLz: seeLz,
                                sortType: sortType,
                                onSeeLzChange: { value in
                                    guard seeLz != value else { return }
                                    seeLz = value
                                    Task { await reload() }
                                },
                                onSortChange: { value in
                                    guard sortType != value else { return }
                                    sortType = value
                                    Task { await reload() }
                                }
                            )
                        }

                        Color.clear
                            .frame(height: 32)
                            .accessibilityHidden(true)
                    }
                    .readableWidth()
                }
                .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            if showsInlineRefreshAnimation {
                InlineRefreshActivityIndicator(
                    progress: 1,
                    isRefreshing: true,
                    accessibilityIdentifier: "thread-refresh-animation"
                )
                .padding(.top, TiebaPureTheme.Spacing.xs)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .allowsHitTesting(false)
                .zIndex(2)
            }
        }
        .overlay(alignment: .top) {
            if showsRestoredReadingBanner {
                RestoredReadingBanner(
                    floor: restoredReadingFloor,
                    onReturnToTop: returnToTopFromRestoredPosition
                )
                .padding(.horizontal, TiebaPureTheme.Spacing.sm)
                .padding(.top, TiebaPureTheme.Spacing.xs)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .navigationTitle(threadPage?.thread.title.isEmpty == false ? threadPage?.thread.title ?? "帖子" : "帖子")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let forum = threadPage?.forum {
                    if let openForumInParent {
                        Button {
                            openForumInParent(forum)
                        } label: {
                            ForumToolbarTitle(forum: forum)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink {
                            ForumThreadsView(account: account, forum: forum)
                        } label: {
                            ForumToolbarTitle(forum: forum)
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ForumToolbarTitle(forum: nil)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                }
                .disabled(threadPage == nil)
                .accessibilityLabel(isFavorite ? "取消收藏帖子" : "收藏帖子")
                .accessibilityValue(isFavorite ? "已收藏" : "未收藏")
                .accessibilityHint(isFavorite ? "从本机帖子收藏中移除" : "保存到本机帖子收藏")
                .accessibilityIdentifier("thread-favorite-button")

                Button {
                    let scope = searchScope
                    if ThreadDetailSearchOpenRoutingPolicy.destination(
                        hasParentHandler: openSearchInParent != nil
                    ) == .parentPath, let openSearchInParent {
                        openSearchInParent(scope)
                    } else {
                        isSearchActive = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("搜索本吧")

                Menu {
                    Button {
                        Task { await refreshFromMenuIfIdle() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }

                    Button {
                        UIPasteboard.general.string = threadWebURL.absoluteString
                        didCopyLink = true
                    } label: {
                        Label("复制链接", systemImage: "doc.on.doc")
                    }

                    Button {
                        openURL(threadWebURL)
                    } label: {
                        Label("浏览器打开", systemImage: "safari")
                    }

                    ShareLink(item: threadWebURL) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("更多")
            }
        }
        .navigationDestination(isPresented: $isSearchActive) {
            SearchResultsView(account: account, scope: searchScope, initialKeyword: "")
                .interactiveNavigationPopStateSync {
                    isSearchActive = false
                }
        }
        .navigationDestination(isPresented: selectedUserIsActive) {
            if let selectedUser {
                UserProfileView(
                    account: account,
                    user: selectedUser,
                    sourceThreadID: threadID,
                    onReturnToSourceThread: {
                        self.selectedUser = nil
                    }
                )
                .interactiveNavigationPopStateSync {
                    self.selectedUser = nil
                }
            }
        }
        .alert("已复制链接", isPresented: $didCopyLink) {
            Button("好", role: .cancel) {}
        }
        .alert("提示", isPresented: likeActionErrorIsPresented) {
            Button("好", role: .cancel) {
                likeActionError = nil
            }
        } message: {
            Text(likeActionError ?? "")
        }
        .alert("无法打开用户主页", isPresented: userResolutionErrorIsPresented) {
            Button("好", role: .cancel) {
                userResolutionError = nil
            }
        } message: {
            Text(userResolutionError ?? "")
        }
        .sheet(item: $selectedSubpostPost) { post in
            if let forumID = resolvedForumID {
                SubpostListSheet(
                    account: account,
                    threadID: threadID,
                    forumID: forumID,
                    post: post,
                    threadAuthorID: threadAuthorID,
                    onPostLikeChanged: applyChangedPost,
                    onInteractiveDismiss: {
                        selectedSubpostPost = nil
                    }
                )
                .environmentObject(environment)
                .subpostInteractivePresentation()
            } else {
                ReaderStateView.error(message: "缺少贴吧 ID，无法加载楼中楼。")
                    .padding()
            }
        }
        .task {
            guard didLoad == false else { return }
            await reload()
        }
        .onChange(of: account?.id) { _ in
            loadTask?.cancel()
            requestGeneration += 1
            threadPage = nil
            posts = []
            nextPage = 1
            hasMore = true
            isLoading = false
            didLoad = false
            errorMessage = nil
            selectedSubpostPost = nil
            selectedUser = nil
            cancelUserResolution()
            userResolutionError = nil
            showsInlineRefreshAnimation = false
            pendingInitialPostID = initialPostID
            scrollDistanceFromTop = 0
            savedReadingPosition = nil
            didResolveSavedReadingPosition = false
            isResumingReadingPosition = false
            restoredReadingFloor = nil
            hideRestoredReadingBanner()
            pendingPreciseScrollPostID = nil
            scrollRequest = nil
            lastRecordedReadingPostID = nil
            didMoveAwayFromTop = false
            cancelLikeTasks()
            likeActionError = nil
            Task { await reload() }
        }
        .onChange(of: blocklistStore.entries) { _ in
            posts = posts.compactMap(postApplyingCurrentBlocklist)
            if var currentPage = threadPage {
                currentPage.posts = currentPage.posts.compactMap(postApplyingCurrentBlocklist)
                currentPage.mainPost = currentPage.mainPost.flatMap(postApplyingCurrentBlocklist)
                threadPage = currentPage
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onDisappear {
            loadTask?.cancel()
            requestGeneration += 1
            isLoading = false
            showsInlineRefreshAnimation = false
            isResumingReadingPosition = false
            hideRestoredReadingBanner()
            scrollRequest = nil
            cancelLikeTasks()
            cancelUserResolution()
        }
        .fullScreenInteractiveNavigationPop(isEnabled: selectedSubpostPost == nil)
    }

    private var selectedUserIsActive: Binding<Bool> {
        Binding(
            get: { selectedUser != nil },
            set: { isActive in
                if isActive == false { selectedUser = nil }
            }
        )
    }

    private var likeActionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { likeActionError != nil },
            set: { isPresented in
                if isPresented == false { likeActionError = nil }
            }
        )
    }

    private var userResolutionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { userResolutionError != nil },
            set: { isPresented in
                if isPresented == false { userResolutionError = nil }
            }
        )
    }

    private func openUser(_ user: UserSummary) {
        cancelUserResolution()
        userResolutionError = nil
        guard user.id <= 0 else {
            presentUser(user)
            return
        }

        let name = TiebaUserName.referenceText(user.displayNameResolved)
        userResolutionGeneration += 1
        let generation = userResolutionGeneration
        userResolutionTask = Task {
            do {
                let resolved = try await environment.api.resolveUser(named: name)
                try Task.checkCancellation()
                guard generation == userResolutionGeneration else { return }
                userResolutionTask = nil
                presentUser(resolved)
            } catch {
                guard generation == userResolutionGeneration else { return }
                userResolutionTask = nil
                guard Task.isCancelled == false,
                      (error is CancellationError) == false,
                      (error as? URLError)?.code != .cancelled else {
                    return
                }
                userResolutionError = ReaderErrorMessage.message(for: error)
            }
        }
    }

    private func presentUser(_ user: UserSummary) {
        if let openUserInParent {
            openUserInParent(user)
        } else {
            selectedUser = user
        }
    }

    private func cancelUserResolution() {
        userResolutionTask?.cancel()
        userResolutionTask = nil
        userResolutionGeneration += 1
    }

    private func refreshablePostScrollView<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    content()
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("thread-detail-scroll-view")
            .shortPullRefresh(
                isEnabled: didLoad && isLoading == false,
                accessibilityIdentifier: "thread-refresh-animation"
            ) {
                guard isLoading == false else { return }
                await reload()
            }
            .coordinateSpace(name: ThreadDetailScrollCoordinateSpace.name)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                scrollViewportHeight = height
            }
            .onPreferenceChange(ThreadPostViewportPreferenceKey.self) { entries in
                recordReadingPositionIfNeeded(entries: Array(entries.values))
                correctPendingPreciseScroll(entries: entries, proxy: scrollProxy)
            }
            .onScrollPhaseChange { _, newPhase in
                guard newPhase == .tracking || newPhase == .interacting else { return }
                pendingPreciseScrollPostID = nil
            }
            .onChange(of: scrollDistanceFromTop) { distance in
                handleReadingScrollDistanceChange(distance)
            }
            .onChange(of: scrollRequest) { request in
                guard let request else { return }
                performScrollRequest(request, proxy: scrollProxy)
            }
            .onAppear {
                // The auto-restore request is issued while the loading state
                // is still on screen, so this scroll view first materializes
                // with the request already set — onChange never observes that
                // transition and the pending request must be replayed here.
                guard let request = scrollRequest else { return }
                performInitialScrollRequest(request, proxy: scrollProxy)
            }
            .trackVerticalScrollDistanceFromTop($scrollDistanceFromTop)
        }
    }

    private func refreshFromMenuIfIdle() async {
        guard isLoading == false else { return }
        let showsAnimation = reduceMotion == false
        // Ownership is tracked separately from requestGeneration: sort
        // toggles and other reloads bump the generation without managing the
        // indicator, and must not be able to strand it visible.
        inlineRefreshAnimationToken += 1
        let animationToken = inlineRefreshAnimationToken
        if showsAnimation {
            setInlineRefreshAnimation(visible: true)
        }
        let animationStart = DispatchTime.now().uptimeNanoseconds
        await reload()
        if showsAnimation {
            let elapsed = DispatchTime.now().uptimeNanoseconds - animationStart
            let remaining = HomeRefreshAnimationPolicy.remainingVisibleDurationNanoseconds(
                minimum: HomeRefreshAnimationPolicy.minimumVisibleDurationNanoseconds,
                elapsed: elapsed
            )
            if remaining > 0 {
                // Do not inherit cancellation from SwiftUI's gesture task. The
                // request generation remains the authority for whether this
                // refresh is still current.
                let minimumVisibilityTask = Task.detached {
                    try? await Task.sleep(nanoseconds: remaining)
                }
                await minimumVisibilityTask.value
            }
            // Only a newer pull refresh may take over hiding the indicator.
            guard animationToken == inlineRefreshAnimationToken else { return }
            setInlineRefreshAnimation(visible: false)
        }
    }

    private func setInlineRefreshAnimation(visible: Bool) {
        if HomeRefreshAnimationPolicy.disablesUITestAnimations(
            arguments: ProcessInfo.processInfo.arguments
        ) || reduceMotion {
            showsInlineRefreshAnimation = visible
        } else {
            withAnimation(.easeInOut(duration: 0.18)) {
                showsInlineRefreshAnimation = visible
            }
        }
    }

    private var mainPost: Post? {
        threadPage?.mainPost ?? posts.first { $0.floor == 1 }
    }

    private var replyPosts: [Post] {
        guard let mainPost else { return posts }
        return posts.filter { $0.id != mainPost.id }
    }

    private var threadAuthorID: Int64? {
        threadPage?.thread.author.id
    }

    private var resolvedForumID: Int64? {
        if let id = threadPage?.forum.id, id != 0 {
            return id
        }
        return forumID
    }

    private var searchScope: SearchScope {
        if let forum = threadPage?.forum, forum.name.isEmpty == false || forum.displayName.isEmpty == false {
            return .forum(forum)
        }
        return .global
    }

    private var threadWebURL: URL {
        var components = URLComponents(string: "https://tieba.baidu.com/p/\(threadID)")!
        if seeLz {
            components.queryItems = [URLQueryItem(name: "see_lz", value: "1")]
        }
        return components.url!
    }

    private var isFavorite: Bool {
        localThreadLibraryStore.isFavorite(threadID: threadID)
    }

    private func toggleFavorite() {
        guard let threadPage else { return }
        localThreadLibraryStore.toggleFavorite(
            thread: threadPage.thread,
            forum: threadPage.forum,
            fallbackForumID: forumID
        )
    }

    /// Restores the saved reading position automatically on the first load of
    /// any entry point. The first page request targets the saved post ID, so
    /// the server locates its page and the list opens there without a second
    /// load or a manual action.
    private func resolveAutoRestoreIfNeeded() {
        guard didResolveSavedReadingPosition == false else { return }
        didResolveSavedReadingPosition = true
        guard initialPostID == nil,
              pendingInitialPostID == nil,
              let position = localThreadLibraryStore.position(for: threadID) else { return }
        savedReadingPosition = position
        restoredReadingFloor = position.floor
        pendingInitialPostID = position.postID
        isResumingReadingPosition = true
        // Server-side post-ID paging is only well-defined in floor order; hot
        // order also reshuffles between visits, so resuming into it would be
        // meaningless anyway. Resume in floor order for deterministic paging.
        sortType = .ascending
    }

    private func showRestoredReadingBanner() {
        restoredBannerHideTask?.cancel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            showsRestoredReadingBanner = true
        }
        restoredBannerHideTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard Task.isCancelled == false else { return }
            hideRestoredReadingBanner()
        }
    }

    private func hideRestoredReadingBanner() {
        restoredBannerHideTask?.cancel()
        restoredBannerHideTask = nil
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            showsRestoredReadingBanner = false
        }
    }

    private func returnToTopFromRestoredPosition() {
        hideRestoredReadingBanner()
        guard let mainPost else { return }
        // Reaching the top clears the stored position through the existing
        // scroll-distance handler, so the next open starts from the beginning.
        requestScroll(to: mainPost.id)
    }

    private func requestScroll(to postID: UInt64) {
        guard postID > 0 else { return }
        scrollRequest = ThreadPostScrollRequest(id: UUID(), postID: postID)
    }

    private func performScrollRequest(
        _ request: ThreadPostScrollRequest,
        proxy: ScrollViewProxy
    ) {
        DispatchQueue.main.async {
            if reduceMotion {
                proxy.scrollTo(request.postID, anchor: .top)
            } else {
                withAnimation(.easeInOut(duration: 0.24)) {
                    proxy.scrollTo(request.postID, anchor: .top)
                }
            }
            if scrollRequest?.id == request.id {
                scrollRequest = nil
            }
        }
    }

    /// The restore target sits below rows whose heights the lazy container
    /// has only estimated (tall images especially), so scrollTo(id:) alone
    /// deterministically lands short. Issue the first jump here, then let the
    /// viewport preference updates correct against measured row frames until
    /// the target actually sits at the top.
    private func performInitialScrollRequest(
        _ request: ThreadPostScrollRequest,
        proxy: ScrollViewProxy
    ) {
        pendingPreciseScrollPostID = request.postID
        preciseScrollRetryCount = 0
        preciseScrollDeadline = Date().addingTimeInterval(1.5)
        DispatchQueue.main.async {
            proxy.scrollTo(request.postID, anchor: .top)
            if scrollRequest?.id == request.id {
                scrollRequest = nil
            }
        }
    }

    /// Media rows above the target settle to their real heights over several
    /// layout passes after the first jump, each time shifting the content the
    /// jump had already positioned. Keep re-anchoring against measured frames
    /// for a short settling window instead of trusting the first success.
    private func correctPendingPreciseScroll(
        entries: [UInt64: ThreadPostViewportEntry],
        proxy: ScrollViewProxy
    ) {
        guard let target = pendingPreciseScrollPostID else { return }
        if let deadline = preciseScrollDeadline, Date() > deadline {
            pendingPreciseScrollPostID = nil
            preciseScrollDeadline = nil
            return
        }
        guard preciseScrollRetryCount < 12 else {
            pendingPreciseScrollPostID = nil
            return
        }
        guard let entry = entries[target], entry.minY.isFinite,
              abs(entry.minY) > 4 else { return }
        preciseScrollRetryCount += 1
        DispatchQueue.main.async {
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private func recordReadingPositionIfNeeded(entries: [ThreadPostViewportEntry]) {
        // Screen height over-approximates the viewport until the geometry
        // callback delivers the real one; both only bound the visibility test.
        let viewportHeight = scrollViewportHeight > 0
            ? scrollViewportHeight
            : UIScreen.main.bounds.height
        guard didLoad,
              let entry = ThreadReadingViewportPolicy.position(
                entries: entries,
                scrollDistanceFromTop: scrollDistanceFromTop,
                viewportHeight: viewportHeight,
                excludedPostID: mainPost?.id
              ),
              entry.postID != lastRecordedReadingPostID else { return }

        let didPersist = localThreadLibraryStore.recordReadingPosition(
            threadID: threadID,
            postID: entry.postID,
            floor: entry.floor
        )
        if didPersist {
            lastRecordedReadingPostID = entry.postID
        }
    }

    private func handleReadingScrollDistanceChange(_ distance: CGFloat) {
        if distance >= ThreadReadingViewportPolicy.minimumRecordingDistance {
            didMoveAwayFromTop = true
            return
        }
        guard didMoveAwayFromTop,
              ShortPullRefreshPolicy.isAtTop(distanceFromTop: distance) else { return }
        guard localThreadLibraryStore.clearReadingPosition(threadID: threadID) else {
            return
        }
        savedReadingPosition = nil
        lastRecordedReadingPostID = nil
        didMoveAwayFromTop = false
    }

    private func reload() async {
        loadTask?.cancel()
        requestGeneration += 1
        isLoading = false
        nextPage = 1
        hasMore = true
        errorMessage = nil
        resolveAutoRestoreIfNeeded()
        // Explicit page-1 rebuilds (refresh, sort toggles) drop the saved
        // position; the initial auto-restore load keeps it until the target
        // page lands.
        if isResumingReadingPosition == false {
            savedReadingPosition = nil
        }
        if posts.isEmpty {
            didLoad = false
        }
        await loadMore(generation: requestGeneration)
    }

    private func loadMore() async {
        await loadMore(generation: requestGeneration)
    }

    private func loadMore(
        generation: Int,
        consecutiveHiddenPageCount: Int = 0
    ) async {
        guard isLoading == false, hasMore else { return }
        let requestedAccountID = account?.id
        let requestedSeeLz = seeLz
        let requestedSort = sortType
        isLoading = true
        errorMessage = nil
        var continuation: LocallyFilteredPaginationDecision?

        do {
            let requestedPage = nextPage
            let requestedPostID = requestedPage == 1 ? pendingInitialPostID : nil
            let task = Task { try await environment.api.threadPage(
                account: account,
                threadID: threadID,
                page: requestedPage,
                forumID: forumID,
                postID: requestedPostID,
                seeLz: requestedSeeLz,
                sortType: requestedSort
            ) }
            loadTask = task
            let loaded = try await task.value
            guard generation == requestGeneration,
                  requestedAccountID == account?.id,
                  requestedSeeLz == seeLz,
                  requestedSort == sortType else { return }
            var visiblePage = loaded
            visiblePage.posts = loaded.posts.compactMap(postApplyingCurrentBlocklist)
            visiblePage.mainPost = loaded.mainPost.flatMap(postApplyingCurrentBlocklist)
            threadPage = visiblePage
            if requestedPage == 1 {
                posts = visiblePage.posts
                pendingInitialPostID = nil
                localThreadLibraryStore.refreshFavoriteMetadata(
                    thread: loaded.thread,
                    forum: loaded.forum,
                    fallbackForumID: forumID
                )
                if didRecordBrowsingHistory == false {
                    didRecordBrowsingHistory = BrowsingHistoryStore.shared.record(
                        thread: loaded.thread,
                        forum: loaded.forum,
                        fallbackForumID: forumID
                    )
                }
                if let requestedPostID {
                    let loadedPostIDs = Set(loaded.posts.map(\.id) + [loaded.mainPost?.id].compactMap { $0 })
                    var didResolveRequestedPost = true
                    if loadedPostIDs.contains(requestedPostID) {
                        requestScroll(to: requestedPostID)
                        if isResumingReadingPosition {
                            showRestoredReadingBanner()
                        }
                    } else if isResumingReadingPosition {
                        // The saved post no longer exists; fall back to the
                        // first page and forget the stale position.
                        didResolveRequestedPost = localThreadLibraryStore.clearReadingPosition(
                            threadID: threadID
                        )
                    }
                    if didResolveRequestedPost {
                        if savedReadingPosition?.postID == requestedPostID {
                            savedReadingPosition = nil
                        }
                        isResumingReadingPosition = false
                    } else {
                        // Retain the target so an explicit reload can retry the
                        // durable cleanup instead of treating it as completed.
                        pendingInitialPostID = requestedPostID
                    }
                }
            } else {
                let knownIDs = Set(posts.map(\.id))
                posts.append(contentsOf: visiblePage.posts.filter { knownIDs.contains($0.id) == false })
            }
            hasMore = loaded.hasMore
            if let followingPage = TiebaPaginationPolicy.nextPage(
                requestedPage: requestedPage,
                responseCurrentPage: loaded.currentPage
            ) {
                nextPage = followingPage
            } else {
                hasMore = false
            }
            let visibleMainPostID = visiblePage.mainPost?.id
            let visibleReplyCount = visiblePage.posts.filter {
                $0.floor != 1 && $0.id != visibleMainPostID
            }.count
            continuation = LocallyFilteredPaginationPolicy.decision(
                visibleItemCount: visibleReplyCount,
                serverHasMore: hasMore,
                consecutiveHiddenPageCount: consecutiveHiddenPageCount
            )
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            loadTask = nil
            isLoading = false
            isResumingReadingPosition = false
            return
        } catch {
            guard generation == requestGeneration,
                  requestedAccountID == account?.id,
                  requestedSeeLz == seeLz,
                  requestedSort == sortType else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
            isResumingReadingPosition = false
        }
        guard generation == requestGeneration else { return }
        loadTask = nil
        isLoading = false
        didLoad = true
        if let continuation, continuation.shouldAutomaticallyLoadNextPage {
            await loadMore(
                generation: generation,
                consecutiveHiddenPageCount: continuation.consecutiveHiddenPageCount
            )
        }
    }

    private func openSubpostsIfPossible(_ post: Post) {
        guard post.subpostCount > 0 else { return }
        selectedSubpostPost = post
    }

    private func toggleLike(for post: Post, objectType: TiebaLikeObjectType) {
        guard updatingPostLikeIDs.contains(post.id) == false else { return }
        guard let account else {
            likeActionError = "登录后才能点赞。"
            return
        }

        let targetState = post.isLiked == false
        updatingPostLikeIDs.insert(post.id)
        likeActionError = nil

        let task = Task {
            do {
                try await environment.api.setPostLiked(
                    account: account,
                    threadID: threadID,
                    postID: post.id,
                    objectType: objectType,
                    liked: targetState
                )
                try Task.checkCancellation()
                applyPostLikeState(postID: post.id, liked: targetState)
            } catch is CancellationError {
                // Leaving the screen or switching accounts intentionally cancels the action.
            } catch {
                likeActionError = ReaderErrorMessage.message(for: error)
            }
            updatingPostLikeIDs.remove(post.id)
            postLikeTasks[post.id] = nil
        }
        postLikeTasks[post.id] = task
    }

    private func applyPostLikeState(postID: UInt64, liked: Bool) {
        if var page = threadPage {
            if var mainPost = page.mainPost, mainPost.id == postID {
                updateLikeState(of: &mainPost, liked: liked)
                page.mainPost = mainPost
            }
            for index in page.posts.indices where page.posts[index].id == postID {
                updateLikeState(of: &page.posts[index], liked: liked)
            }
            threadPage = page
        }
        for index in posts.indices where posts[index].id == postID {
            updateLikeState(of: &posts[index], liked: liked)
        }
        if var selectedPost = selectedSubpostPost, selectedPost.id == postID {
            updateLikeState(of: &selectedPost, liked: liked)
            selectedSubpostPost = selectedPost
        }
    }

    private func applyChangedPost(_ changedPost: Post) {
        if var page = threadPage {
            if page.mainPost?.id == changedPost.id {
                page.mainPost = changedPost
            }
            for index in page.posts.indices where page.posts[index].id == changedPost.id {
                page.posts[index] = changedPost
            }
            threadPage = page
        }
        for index in posts.indices where posts[index].id == changedPost.id {
            posts[index] = changedPost
        }
        if selectedSubpostPost?.id == changedPost.id {
            selectedSubpostPost = changedPost
        }
    }

    private func updateLikeState(of post: inout Post, liked: Bool) {
        guard post.isLiked != liked else { return }
        post.isLiked = liked
        post.likeCount = max(post.likeCount + (liked ? 1 : -1), 0)
    }

    private func postApplyingCurrentBlocklist(_ candidate: Post) -> Post? {
        guard TiebaContentFilter.shouldKeep(post: candidate) else { return nil }
        var filtered = candidate
        filtered.previewSubposts.removeAll {
            TiebaContentFilter.shouldKeep(subpost: $0) == false
        }
        return filtered
    }

    private func cancelLikeTasks() {
        postLikeTasks.values.forEach { $0.cancel() }
        postLikeTasks.removeAll()
        updatingPostLikeIDs.removeAll()
    }
}

enum ThreadDetailSearchOpenDestination: Equatable {
    case parentPath
    case localSearch
}

enum ThreadDetailSearchOpenRoutingPolicy {
    static func destination(
        hasParentHandler: Bool
    ) -> ThreadDetailSearchOpenDestination {
        hasParentHandler ? .parentPath : .localSearch
    }
}

private enum ThreadDetailScrollCoordinateSpace {
    static let name = "thread-detail-refresh-scroll"
}

struct ThreadPostViewportEntry: Equatable, Sendable {
    var postID: UInt64
    var floor: Int
    var minY: CGFloat
    var maxY: CGFloat
}

enum ThreadReadingViewportPolicy {
    static let minimumRecordingDistance: CGFloat = 44

    /// Returns the bottom-most reply visible in the viewport. Floors are not
    /// part of the condition: hot-sorted responses omit floor numbers, and the
    /// position is restored by post ID. The main post is excluded so a long
    /// first floor never records a position of its own.
    static func position(
        entries: [ThreadPostViewportEntry],
        scrollDistanceFromTop: CGFloat,
        viewportHeight: CGFloat,
        excludedPostID: UInt64?
    ) -> ThreadPostViewportEntry? {
        guard scrollDistanceFromTop >= minimumRecordingDistance,
              viewportHeight > 0 else { return nil }
        return entries
            .filter { entry in
                entry.postID > 0
                    && entry.postID != excludedPostID
                    && entry.minY.isFinite
                    && entry.maxY.isFinite
                    && entry.minY < viewportHeight
                    && entry.maxY > 0
            }
            .max(by: { $0.maxY < $1.maxY })
    }
}

private struct ThreadPostScrollRequest: Equatable {
    var id: UUID
    var postID: UInt64
}

private struct ThreadPostViewportPreferenceKey: PreferenceKey {
    static var defaultValue: [UInt64: ThreadPostViewportEntry] = [:]

    static func reduce(
        value: inout [UInt64: ThreadPostViewportEntry],
        nextValue: () -> [UInt64: ThreadPostViewportEntry]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private extension View {
    func threadReadingAnchor(post: Post) -> some View {
        background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(ThreadDetailScrollCoordinateSpace.name))
                Color.clear.preference(
                    key: ThreadPostViewportPreferenceKey.self,
                    value: [
                        post.id: ThreadPostViewportEntry(
                            postID: post.id,
                            floor: post.floor,
                            minY: frame.minY,
                            maxY: frame.maxY
                        )
                    ]
                )
            }
        }
    }
}

private struct RestoredReadingBanner: View {
    let floor: Int?
    let onReturnToTop: () -> Void

    private var title: String {
        if let floor, floor > 1 {
            return "\u{5df2}\u{6062}\u{590d}\u{5230}\u{7b2c} \(floor) \u{697c}"
        }
        return "\u{5df2}\u{6062}\u{590d}\u{4e0a}\u{6b21}\u{9605}\u{8bfb}\u{4f4d}\u{7f6e}"
    }

    var body: some View {
        HStack(spacing: TiebaPureTheme.Spacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text(title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Button(action: onReturnToTop) {
                Text("\u{56de}\u{5230}\u{9876}\u{90e8}")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("restored-reading-return-top")
        }
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.vertical, TiebaPureTheme.Spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(TiebaPureTheme.ColorToken.readerSecondarySurface)
                .shadow(color: Color.black.opacity(0.12), radius: 8, y: 2)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(floor.map { $0 > 1 ? "\($0)\u{697c}" : "" } ?? "")
        .accessibilityIdentifier("restored-reading-banner")
    }
}

private struct ForumToolbarTitle: View {
    let forum: Forum?

    var body: some View {
        HStack(spacing: TiebaPureTheme.Spacing.xs) {
            if let forum {
                AvatarView(url: forum.avatarURL, title: forum.displayName, size: 24)
                Text(forum.displayName.isEmpty ? forum.name : forum.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text("帖子")
                    .font(.headline)
            }
        }
        .padding(.horizontal, TiebaPureTheme.Spacing.xs)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(TiebaPureTheme.ColorToken.readerSecondarySurface)
        )
    }
}

private struct ReplyControlBar: View {
    let seeLz: Bool
    let sortType: ThreadReplySort
    let onSeeLzChange: (Bool) -> Void
    let onSortChange: (ThreadReplySort) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TiebaPureTheme.Spacing.sm) {
                filterControls
                Spacer(minLength: TiebaPureTheme.Spacing.sm)
                sortControls
            }
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
                filterControls
                sortControls
            }
        }
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.vertical, TiebaPureTheme.Spacing.xs)
        .background(.regularMaterial)
    }

    private var filterControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TiebaPureTheme.Spacing.md) {
                filterButton(title: "全部回复", isSelected: seeLz == false) {
                    onSeeLzChange(false)
                }
                filterButton(title: "只看楼主", isSelected: seeLz) {
                    onSeeLzChange(true)
                }
            }
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                filterButton(title: "全部回复", isSelected: seeLz == false) {
                    onSeeLzChange(false)
                }
                filterButton(title: "只看楼主", isSelected: seeLz) {
                    onSeeLzChange(true)
                }
            }
        }
    }

    private var sortControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                ForEach(ThreadReplySort.allCases) { item in
                    sortButton(item)
                }
            }
            .padding(3)
            .background(
                Capsule(style: .continuous)
                    .fill(TiebaPureTheme.ColorToken.readerGroupedBackground)
            )
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                ForEach(ThreadReplySort.allCases) { item in
                    sortButton(item)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.chip, style: .continuous)
                    .fill(TiebaPureTheme.ColorToken.readerGroupedBackground)
            )
        }
    }

    private func sortButton(_ item: ThreadReplySort) -> some View {
        Button {
            onSortChange(item)
        } label: {
            Text(item.title)
                .font(.subheadline.weight(sortType == item ? .semibold : .regular))
                .foregroundStyle(sortType == item ? Color.primary : Color.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 48)
                .padding(.vertical, 7)
                .padding(.horizontal, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(sortType == item ? Color(uiColor: .systemBackground) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .minTouchTarget()
        .accessibilityLabel("按\(item.title)排列回复")
        .accessibilityAddTraits(sortType == item ? [.isSelected] : [])
    }

    private func filterButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .minTouchTarget()
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

private struct SubpostListSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var blocklistStore = BlocklistStore.shared

    // pb/floor carries no client page-size field; the server pages replies
    // ten at a time. A short or empty page therefore ends pagination, while
    // the snapshot subpostCount would freeze out replies posted after the
    // thread page loaded.
    private static let subpostsPageSize = 10

    let account: Account?
    let threadID: Int64
    let forumID: Int64
    let threadAuthorID: Int64?
    let onPostLikeChanged: (Post) -> Void
    let onInteractiveDismiss: () -> Void

    @State private var post: Post
    @State private var subposts: [Subpost] = []
    @State private var nextPage = 1
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var requestGeneration = 0
    @State private var loadTask: Task<[Subpost], Error>?
    @State private var selectedUser: UserSummary?
    @State private var userResolutionTask: Task<Void, Never>?
    @State private var userResolutionGeneration = 0
    @State private var userResolutionError: String?
    @State private var updatingLikeIDs = Set<UInt64>()
    @State private var likeTasks: [UInt64: Task<Void, Never>] = [:]
    @State private var likeActionError: String?

    init(
        account: Account?,
        threadID: Int64,
        forumID: Int64,
        post: Post,
        threadAuthorID: Int64?,
        onPostLikeChanged: @escaping (Post) -> Void,
        onInteractiveDismiss: @escaping () -> Void
    ) {
        self.account = account
        self.threadID = threadID
        self.forumID = forumID
        self.threadAuthorID = threadAuthorID
        self.onPostLikeChanged = onPostLikeChanged
        self.onInteractiveDismiss = onInteractiveDismiss
        _post = State(initialValue: post)
    }

    var body: some View {
        SubpostSheetInteractiveDismissSurface(
            isEnabled: selectedUser == nil,
            onDismiss: onInteractiveDismiss
        ) {
            NavigationStack {
                Group {
                if isLoading && didLoad == false {
                    ReaderStateView.loading("加载回复")
                } else if let errorMessage, subposts.isEmpty {
                    ReaderStateScrollView(refresh: { await reload() }) {
                        ReaderStateView.error(message: errorMessage) {
                            Task { await reload() }
                        }
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ReaderCard(showsDivider: false) {
                                VStack(alignment: .leading, spacing: ThreadReplyLayout.headerContentSpacing) {
                                    UserHeaderView(
                                        author: post.author,
                                        floor: post.floor,
                                        isThreadAuthor: post.author.id == threadAuthorID,
                                        trailingLikeCount: post.likeCount,
                                        isLiked: post.isLiked,
                                        isLikeUpdating: updatingLikeIDs.contains(post.id),
                                        onToggleLike: { togglePostLike() },
                                        likeAccessibilityIdentifier: "thread-subpost-parent-like-button",
                                        onOpenUser: { openUser(post.author) }
                                    )

                                    VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
                                        ContentBlocksView(
                                            blocks: post.blocks,
                                            textStyle: .reply,
                                            lineLimit: ThreadContentDisplayPolicy.detailLineLimit,
                                            inlineAccessibilityIdentifier: "thread-subpost-parent-text"
                                        )
                                        ThreadPostMetadataView(
                                            createdAt: post.createdAt,
                                            ipAddress: ThreadPostMetadataText.firstLocation(
                                                post.ipAddress,
                                                post.author.ipAddress
                                            ),
                                            accessibilityIdentifier: "thread-subpost-parent-metadata"
                                        )
                                    }
                                    .padding(.leading, ThreadReplyLayout.bodyLeadingInset)
                                }
                            }

                            SubpostSectionSeparator()

                            ForEach(Array(subposts.enumerated()), id: \.element.id) { index, subpost in
                                SubpostRowView(
                                    subpost: subpost,
                                    threadAuthorID: threadAuthorID,
                                    onOpenUser: openUser,
                                    isLikeUpdating: updatingLikeIDs.contains(subpost.id),
                                    onToggleLike: { toggleSubpostLike(subpost) }
                                )
                                    .onAppear {
                                        guard PaginationPrefetchPolicy.shouldLoadMore(
                                            currentIndex: index,
                                            totalCount: subposts.count
                                        ) else { return }
                                        Task { await loadMore() }
                                    }
                            }

                            if isLoading, didLoad {
                                ProgressView()
                                    .padding(TiebaPureTheme.Spacing.md)
                            }

                            if let errorMessage {
                                InlineLoadErrorView(message: errorMessage) {
                                    Task {
                                        if nextPage <= 1 { await reload() } else { await loadMore() }
                                    }
                                }
                            } else if hasMore, isLoading == false, didLoad {
                                Button {
                                    Task { await loadMore() }
                                } label: {
                                    Label("加载更多楼中楼回复", systemImage: "arrow.down.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .minTouchTarget()
                                .padding(.horizontal, TiebaPureTheme.Spacing.md)
                                .accessibilityIdentifier("subposts-load-more")
                            }

                            Color.clear
                                .frame(height: 24)
                                .accessibilityHidden(true)
                        }
                        .readableWidth()
                    }
                    .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
                }
                }
                .navigationTitle(SubpostSheetTitle.text(
                    floor: post.floor,
                    count: max(post.subpostCount, subposts.count)
                ))
                .navigationBarTitleDisplayMode(.inline)
                // User profiles pushed inside this sheet need a stable image
                // of the sheet root for the middle-screen interactive return.
                .interactiveNavigationPopRevealSource()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        SubpostSheetDismissButton()
                    }
                }
                .navigationDestination(isPresented: selectedUserIsActive) {
                    if let selectedUser {
                        UserProfileView(
                            account: account,
                            user: selectedUser,
                            sourceThreadID: threadID,
                            onReturnToSourceThread: {
                                self.selectedUser = nil
                            }
                        )
                        .interactiveNavigationPopStateSync {
                            self.selectedUser = nil
                        }
                    }
                }
                .alert("提示", isPresented: likeActionErrorIsPresented) {
                    Button("好", role: .cancel) {
                        likeActionError = nil
                    }
                } message: {
                    Text(likeActionError ?? "")
                }
                .alert("无法打开用户主页", isPresented: userResolutionErrorIsPresented) {
                    Button("好", role: .cancel) {
                        userResolutionError = nil
                    }
                } message: {
                    Text(userResolutionError ?? "")
                }
            }
            .task {
                guard didLoad == false else { return }
                await reload()
            }
            .onChange(of: blocklistStore.entries) { _ in
                subposts.removeAll { TiebaContentFilter.shouldKeep(subpost: $0) == false }
            }
            .onDisappear {
                loadTask?.cancel()
                requestGeneration += 1
                isLoading = false
                cancelLikeTasks()
                cancelUserResolution()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
        }
    }

    private var selectedUserIsActive: Binding<Bool> {
        Binding(
            get: { selectedUser != nil },
            set: { isActive in
                if isActive == false { selectedUser = nil }
            }
        )
    }

    private var likeActionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { likeActionError != nil },
            set: { isPresented in
                if isPresented == false { likeActionError = nil }
            }
        )
    }

    private var userResolutionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { userResolutionError != nil },
            set: { isPresented in
                if isPresented == false { userResolutionError = nil }
            }
        )
    }

    private func openUser(_ user: UserSummary) {
        cancelUserResolution()
        userResolutionError = nil
        guard user.id <= 0 else {
            selectedUser = user
            return
        }

        let name = TiebaUserName.referenceText(user.displayNameResolved)
        userResolutionGeneration += 1
        let generation = userResolutionGeneration
        userResolutionTask = Task {
            do {
                let resolved = try await environment.api.resolveUser(named: name)
                try Task.checkCancellation()
                guard generation == userResolutionGeneration else { return }
                userResolutionTask = nil
                selectedUser = resolved
            } catch {
                guard generation == userResolutionGeneration else { return }
                userResolutionTask = nil
                guard Task.isCancelled == false,
                      (error is CancellationError) == false,
                      (error as? URLError)?.code != .cancelled else {
                    return
                }
                userResolutionError = ReaderErrorMessage.message(for: error)
            }
        }
    }

    private func cancelUserResolution() {
        userResolutionTask?.cancel()
        userResolutionTask = nil
        userResolutionGeneration += 1
    }

    private func reload() async {
        loadTask?.cancel()
        requestGeneration += 1
        isLoading = false
        nextPage = 1
        hasMore = true
        errorMessage = nil
        if subposts.isEmpty {
            didLoad = false
        }
        await loadMore(generation: requestGeneration)
    }

    private func loadMore() async {
        await loadMore(generation: requestGeneration)
    }

    private func loadMore(
        generation: Int,
        consecutiveHiddenPageCount: Int = 0
    ) async {
        guard isLoading == false, hasMore else { return }
        isLoading = true
        errorMessage = nil
        var continuation: LocallyFilteredPaginationDecision?

        do {
            let requestedPage = nextPage
            let task = Task { try await environment.api.subposts(
                account: account,
                threadID: threadID,
                postID: post.id,
                forumID: forumID,
                page: requestedPage
            ) }
            loadTask = task
            let loaded = try await task.value
            guard generation == requestGeneration else { return }
            let visibleSubposts = loaded.filter(TiebaContentFilter.shouldKeep(subpost:))
            if requestedPage == 1 {
                subposts = visibleSubposts
            } else {
                let knownIDs = Set(subposts.map(\.id))
                subposts.append(contentsOf: visibleSubposts.filter { knownIDs.contains($0.id) == false })
            }
            // The API deliberately returns an unfiltered page so local
            // blocking cannot shorten the apparent server page.
            hasMore = loaded.count == Self.subpostsPageSize
            nextPage = requestedPage + 1
            continuation = LocallyFilteredPaginationPolicy.decision(
                visibleItemCount: visibleSubposts.count,
                serverHasMore: hasMore,
                consecutiveHiddenPageCount: consecutiveHiddenPageCount
            )
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
        if let continuation, continuation.shouldAutomaticallyLoadNextPage {
            await loadMore(
                generation: generation,
                consecutiveHiddenPageCount: continuation.consecutiveHiddenPageCount
            )
        }
    }

    private func togglePostLike() {
        let objectType: TiebaLikeObjectType = post.floor == 1 ? .thread : .post
        performLikeMutation(
            id: post.id,
            objectType: objectType,
            currentlyLiked: post.isLiked
        ) { liked in
            guard post.isLiked != liked else { return }
            post.isLiked = liked
            post.likeCount = max(post.likeCount + (liked ? 1 : -1), 0)
            onPostLikeChanged(post)
        }
    }

    private func toggleSubpostLike(_ subpost: Subpost) {
        performLikeMutation(
            id: subpost.id,
            objectType: .subpost,
            currentlyLiked: subpost.isLiked
        ) { liked in
            guard let index = subposts.firstIndex(where: { $0.id == subpost.id }),
                  subposts[index].isLiked != liked else { return }
            subposts[index].isLiked = liked
            subposts[index].likeCount = max(subposts[index].likeCount + (liked ? 1 : -1), 0)
        }
    }

    private func performLikeMutation(
        id: UInt64,
        objectType: TiebaLikeObjectType,
        currentlyLiked: Bool,
        apply: @escaping (Bool) -> Void
    ) {
        guard updatingLikeIDs.contains(id) == false else { return }
        guard let account else {
            likeActionError = "登录后才能点赞。"
            return
        }

        let targetState = currentlyLiked == false
        updatingLikeIDs.insert(id)
        likeActionError = nil
        let task = Task {
            do {
                try await environment.api.setPostLiked(
                    account: account,
                    threadID: threadID,
                    postID: id,
                    objectType: objectType,
                    liked: targetState
                )
                try Task.checkCancellation()
                apply(targetState)
            } catch is CancellationError {
                // Closing the sheet intentionally cancels pending mutations.
            } catch {
                likeActionError = ReaderErrorMessage.message(for: error)
            }
            updatingLikeIDs.remove(id)
            likeTasks[id] = nil
        }
        likeTasks[id] = task
    }

    private func cancelLikeTasks() {
        likeTasks.values.forEach { $0.cancel() }
        likeTasks.removeAll()
        updatingLikeIDs.removeAll()
    }
}

enum SubpostDetailSectionLayout {
    static let separatorHeight: CGFloat = TiebaPureTheme.Spacing.sm
}

private struct SubpostSectionSeparator: View {
    var body: some View {
        ZStack {
            TiebaPureTheme.ColorToken.readerSectionBand

            VStack(spacing: 0) {
                Divider()
                Spacer(minLength: 0)
                Divider()
            }
        }
        .frame(height: SubpostDetailSectionLayout.separatorHeight)
        .accessibilityHidden(true)
    }
}

private struct SubpostRowView: View {
    let subpost: Subpost
    let threadAuthorID: Int64?
    let onOpenUser: ((UserSummary) -> Void)?
    let isLikeUpdating: Bool
    let onToggleLike: (() -> Void)?

    var body: some View {
        ReaderCard {
            VStack(alignment: .leading, spacing: ThreadReplyLayout.headerContentSpacing) {
                UserHeaderView(
                    author: subpost.author,
                    floor: subpost.floor,
                    isThreadAuthor: isThreadAuthor,
                    nameTone: .secondary,
                    showsFloorBadge: true,
                    trailingLikeCount: subpost.likeCount,
                    isLiked: subpost.isLiked,
                    isLikeUpdating: isLikeUpdating,
                    onToggleLike: onToggleLike,
                    likeAccessibilityIdentifier: "thread-subpost-like-button-\(subpost.id)",
                    onOpenUser: onOpenUser.map { open in { open(subpost.author) } }
                )

                VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
                    ContentBlocksView(
                        blocks: subpost.blocks,
                        textStyle: .reply,
                        lineLimit: ThreadContentDisplayPolicy.detailLineLimit,
                        inlineAccessibilityIdentifier: "thread-subpost-text",
                        onOpenUser: onOpenUser
                    )
                    ThreadPostMetadataView(
                        createdAt: subpost.createdAt,
                        ipAddress: ThreadPostMetadataText.firstLocation(
                            subpost.ipAddress,
                            subpost.author.ipAddress
                        ),
                        accessibilityIdentifier: "thread-subpost-metadata"
                    )
                }
                .padding(.leading, ThreadReplyLayout.bodyLeadingInset)
            }
        }
    }

    private var isThreadAuthor: Bool {
        guard let threadAuthorID else { return false }
        return threadAuthorID != 0 && subpost.author.id == threadAuthorID
    }
}

enum SubpostSheetTitle {
    static func text(floor: Int, count: Int) -> String {
        let floorText = floor > 0 ? "\(floor)楼" : "本楼"
        return "\(floorText)的回复(\(max(count, 0))条)"
    }
}

private extension View {
    @ViewBuilder
    func subpostInteractivePresentation() -> some View {
        if #available(iOS 16.4, *) {
            presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(.clear)
                .interactiveDismissDisabled()
        } else {
            presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .interactiveDismissDisabled()
        }
    }
}
