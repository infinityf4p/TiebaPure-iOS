import SwiftUI
import UIKit

struct ThreadDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var localThreadLibraryStore = LocalThreadLibraryStore.shared
    let account: Account?
    let threadID: Int64
    let forumID: Int64?
    let initialPostID: UInt64?

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
    @State private var isSearchActive = false
    @State private var didCopyLink = false
    @State private var pendingInitialPostID: UInt64?
    @State private var requestGeneration = 0
    @State private var loadTask: Task<ThreadPage, Error>?
    @State private var scrollDistanceFromTop: CGFloat = 0
    @State private var isTrackingPullGesture = false
    @State private var pullGestureStartedAtTop = false
    @State private var showsInlineRefreshAnimation = false
    @State private var showsPullRefreshIndicator = false
    @State private var savedReadingPosition: ThreadReadingPosition?
    @State private var didResolveSavedReadingPosition = false
    @State private var isResumingReadingPosition = false
    @State private var scrollRequest: ThreadPostScrollRequest?
    @State private var lastRecordedReadingPostID: UInt64?
    @State private var didMoveAwayFromTop = false
    @State private var updatingPostLikeIDs = Set<UInt64>()
    @State private var postLikeTasks: [UInt64: Task<Void, Never>] = [:]
    @State private var likeActionError: String?

    init(account: Account?, threadID: Int64, forumID: Int64? = nil, initialPostID: UInt64? = nil) {
        self.account = account
        self.threadID = threadID
        self.forumID = forumID
        self.initialPostID = initialPostID
        _pendingInitialPostID = State(initialValue: initialPostID)
    }

    var body: some View {
        Group {
            if isLoading && didLoad == false {
                ReaderStateView.loading("正在加载帖子")
            } else if let errorMessage, posts.isEmpty {
                ReaderStateScrollView(refresh: { await reload() }) {
                    ReaderStateView.error(message: errorMessage) {
                        Task { await reload() }
                    }
                }
            } else if posts.isEmpty {
                ReaderStateScrollView(refresh: { await reload() }) {
                    ReaderStateView.empty(title: "暂无内容", message: "下拉即可刷新帖子。")
                }
            } else {
                refreshablePostScrollView {
                    LazyVStack(spacing: 0) {
                        if let savedReadingPosition {
                            ContinueReadingButton(
                                position: savedReadingPosition,
                                isLoading: isResumingReadingPosition,
                                action: continueFromSavedReadingPosition
                            )
                            .padding(.horizontal, TiebaPureTheme.Spacing.sm)
                            .padding(.vertical, TiebaPureTheme.Spacing.xs)
                        }

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
                                ReaderStateView.empty(title: "暂无回复", message: seeLz ? "这个帖子暂时没有楼主回复。" : "这个帖子暂时没有更多回复。")
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
            if showsInlineRefreshAnimation || showsPullRefreshIndicator {
                InlineRefreshActivityIndicator(
                    accessibilityIdentifier: "thread-refresh-animation"
                )
                .transition(.opacity)
                .allowsHitTesting(false)
                .zIndex(2)
            }
        }
        .navigationTitle(threadPage?.thread.title.isEmpty == false ? threadPage?.thread.title ?? "帖子" : "帖子")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let forum = threadPage?.forum {
                    NavigationLink {
                        ForumThreadsView(account: account, forum: forum)
                    } label: {
                        ForumToolbarTitle(forum: forum)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                    isSearchActive = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("搜索本吧")

                Menu {
                    Button {
                        Task { await refreshFromPullGestureIfIdle() }
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
        }
        .navigationDestination(isPresented: selectedUserIsActive) {
            if let selectedUser {
                UserProfileView(account: account, user: selectedUser)
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
            showsInlineRefreshAnimation = false
            showsPullRefreshIndicator = false
            pendingInitialPostID = initialPostID
            scrollDistanceFromTop = 0
            savedReadingPosition = nil
            didResolveSavedReadingPosition = false
            isResumingReadingPosition = false
            scrollRequest = nil
            lastRecordedReadingPostID = nil
            didMoveAwayFromTop = false
            cancelLikeTasks()
            likeActionError = nil
            resetPullGestureState()
            Task { await reload() }
        }
        .toolbar(.hidden, for: .tabBar)
        .onDisappear {
            loadTask?.cancel()
            requestGeneration += 1
            isLoading = false
            showsInlineRefreshAnimation = false
            showsPullRefreshIndicator = false
            isResumingReadingPosition = false
            scrollRequest = nil
            cancelLikeTasks()
            resetPullGestureState()
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

    private func openUser(_ user: UserSummary) {
        selectedUser = user
    }

    private func refreshablePostScrollView<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ThreadDetailScrollTopOffsetPreferenceKey.self,
                            value: proxy.frame(in: .named(ThreadDetailScrollCoordinateSpace.name)).minY
                        )
                    }
                    .frame(height: 0)

                    content()
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("thread-detail-scroll-view")
            .coordinateSpace(name: ThreadDetailScrollCoordinateSpace.name)
            .onPreferenceChange(ThreadDetailScrollTopOffsetPreferenceKey.self) { markerOffset in
                if #unavailable(iOS 18.0) {
                    scrollDistanceFromTop = ShortPullRefreshPolicy.distanceFromTop(
                        markerOffset: markerOffset
                    )
                }
            }
            .onPreferenceChange(ThreadPostViewportPreferenceKey.self) { entries in
                recordReadingPositionIfNeeded(entries: Array(entries.values))
            }
            .onChange(of: scrollDistanceFromTop) { distance in
                handleReadingScrollDistanceChange(distance)
            }
            .onChange(of: scrollRequest) { request in
                guard let request else { return }
                DispatchQueue.main.async {
                    if reduceMotion {
                        scrollProxy.scrollTo(request.postID, anchor: .top)
                    } else {
                        withAnimation(.easeInOut(duration: 0.24)) {
                            scrollProxy.scrollTo(request.postID, anchor: .top)
                        }
                    }
                    if scrollRequest?.id == request.id {
                        scrollRequest = nil
                    }
                }
            }
            .trackVerticalScrollDistanceFromTop($scrollDistanceFromTop)
            .simultaneousGesture(
                DragGesture(minimumDistance: ShortPullRefreshPolicy.minimumTrackingDistance)
                    .onChanged { value in
                        if isTrackingPullGesture == false {
                            isTrackingPullGesture = true
                            pullGestureStartedAtTop = ShortPullRefreshPolicy.shouldBegin(
                                distanceFromTop: scrollDistanceFromTop,
                                initialTranslation: value.translation
                            )
                            if pullGestureStartedAtTop, isLoading == false {
                                setPullRefreshIndicator(visible: true)
                            }
                        } else if ShortPullRefreshPolicy.isAtTop(
                            distanceFromTop: scrollDistanceFromTop
                        ) == false {
                            pullGestureStartedAtTop = false
                            setPullRefreshIndicator(visible: false)
                        }
                    }
                    .onEnded { value in
                        let shouldRefresh = ShortPullRefreshPolicy.shouldTrigger(
                            startedAtTop: pullGestureStartedAtTop,
                            isRefreshing: isLoading,
                            translation: value.translation
                        )
                        resetPullGestureState()
                        guard shouldRefresh else { return }
                        Task { await refreshFromPullGestureIfIdle() }
                    }
            )
        }
    }

    private func refreshFromPullGestureIfIdle() async {
        guard isLoading == false else { return }
        let showsAnimation = reduceMotion == false
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
                let minimumVisibilityTask = Task.detached {
                    try? await Task.sleep(nanoseconds: remaining)
                }
                await minimumVisibilityTask.value
            }
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

    private func setPullRefreshIndicator(visible: Bool) {
        let resolvedVisibility = visible && reduceMotion == false
        if HomeRefreshAnimationPolicy.disablesUITestAnimations(
            arguments: ProcessInfo.processInfo.arguments
        ) {
            showsPullRefreshIndicator = resolvedVisibility
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                showsPullRefreshIndicator = resolvedVisibility
            }
        }
    }

    private func resetPullGestureState() {
        isTrackingPullGesture = false
        pullGestureStartedAtTop = false
        setPullRefreshIndicator(visible: false)
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

    private func continueFromSavedReadingPosition() {
        guard let position = savedReadingPosition,
              isResumingReadingPosition == false else { return }
        if posts.contains(where: { $0.id == position.postID }) {
            savedReadingPosition = nil
            requestScroll(to: position.postID)
            return
        }

        isResumingReadingPosition = true
        pendingInitialPostID = position.postID
        Task { await reload() }
    }

    private func requestScroll(to postID: UInt64) {
        guard postID > 0 else { return }
        scrollRequest = ThreadPostScrollRequest(id: UUID(), postID: postID)
    }

    private func recordReadingPositionIfNeeded(entries: [ThreadPostViewportEntry]) {
        guard didLoad,
              let entry = ThreadReadingViewportPolicy.position(
                entries: entries,
                scrollDistanceFromTop: scrollDistanceFromTop
              ),
              entry.postID != lastRecordedReadingPostID else { return }

        localThreadLibraryStore.recordReadingPosition(
            threadID: threadID,
            postID: entry.postID,
            floor: entry.floor
        )
        lastRecordedReadingPostID = entry.postID
        savedReadingPosition = nil
        isResumingReadingPosition = false
    }

    private func handleReadingScrollDistanceChange(_ distance: CGFloat) {
        if distance >= ThreadReadingViewportPolicy.minimumRecordingDistance {
            didMoveAwayFromTop = true
            return
        }
        guard didMoveAwayFromTop,
              ShortPullRefreshPolicy.isAtTop(distanceFromTop: distance) else { return }
        localThreadLibraryStore.clearReadingPosition(threadID: threadID)
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
        if posts.isEmpty {
            didLoad = false
        }
        await loadMore(generation: requestGeneration)
    }

    private func loadMore() async {
        await loadMore(generation: requestGeneration)
    }

    private func loadMore(generation: Int) async {
        guard isLoading == false, hasMore else { return }
        let requestedAccountID = account?.id
        let requestedSeeLz = seeLz
        let requestedSort = sortType
        isLoading = true
        errorMessage = nil

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
            threadPage = loaded
            if requestedPage == 1 {
                posts = loaded.posts
                pendingInitialPostID = nil
                localThreadLibraryStore.refreshFavoriteMetadata(
                    thread: loaded.thread,
                    forum: loaded.forum,
                    fallbackForumID: forumID
                )
                if didRecordBrowsingHistory == false {
                    BrowsingHistoryStore.shared.record(
                        thread: loaded.thread,
                        forum: loaded.forum,
                        fallbackForumID: forumID
                    )
                    didRecordBrowsingHistory = true
                }
                if didResolveSavedReadingPosition == false {
                    didResolveSavedReadingPosition = true
                    if initialPostID == nil {
                        savedReadingPosition = localThreadLibraryStore.position(for: threadID)
                    }
                }
                if let requestedPostID {
                    let loadedPostIDs = Set(loaded.posts.map(\.id) + [loaded.mainPost?.id].compactMap { $0 })
                    if loadedPostIDs.contains(requestedPostID) {
                        requestScroll(to: requestedPostID)
                    } else if isResumingReadingPosition {
                        localThreadLibraryStore.clearReadingPosition(threadID: threadID)
                    }
                    if savedReadingPosition?.postID == requestedPostID {
                        savedReadingPosition = nil
                    }
                    isResumingReadingPosition = false
                }
            } else {
                let knownIDs = Set(posts.map(\.id))
                posts.append(contentsOf: loaded.posts.filter { knownIDs.contains($0.id) == false })
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

    private func cancelLikeTasks() {
        postLikeTasks.values.forEach { $0.cancel() }
        postLikeTasks.removeAll()
        updatingPostLikeIDs.removeAll()
    }
}

private enum ThreadDetailScrollCoordinateSpace {
    static let name = "thread-detail-refresh-scroll"
}

private struct ThreadDetailScrollTopOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ThreadPostViewportEntry: Equatable, Sendable {
    var postID: UInt64
    var floor: Int
    var minY: CGFloat
    var maxY: CGFloat
}

enum ThreadReadingViewportPolicy {
    static let minimumRecordingDistance: CGFloat = 44
    static let captureLineY: CGFloat = 88

    static func position(
        entries: [ThreadPostViewportEntry],
        scrollDistanceFromTop: CGFloat
    ) -> ThreadPostViewportEntry? {
        guard scrollDistanceFromTop >= minimumRecordingDistance else { return nil }
        return entries
            .filter { entry in
                entry.postID > 0
                    && entry.floor > 1
                    && entry.minY.isFinite
                    && entry.maxY.isFinite
                    && entry.minY <= captureLineY
                    && entry.maxY > captureLineY
            }
            .max(by: { $0.minY < $1.minY })
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

private struct ContinueReadingButton: View {
    let position: ThreadReadingPosition
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: TiebaPureTheme.Spacing.sm) {
                Image(systemName: "arrow.down.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                    Text(isLoading ? "正在定位上次阅读位置" : "继续上次阅读")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("上次读到 \(position.floor)楼")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, TiebaPureTheme.Spacing.sm)
            .padding(.vertical, TiebaPureTheme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.card, style: .continuous)
                    .fill(TiebaPureTheme.ColorToken.readerSecondarySurface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "正在定位上次阅读位置" : "继续上次阅读")
        .accessibilityValue("\(position.floor)楼")
        .accessibilityHint("跳转到上次阅读的回复")
        .accessibilityIdentifier("continue-reading-button")
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
    @Environment(\.dismiss) private var dismiss

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
                                        onOpenUser: { selectedUser = post.author }
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

                            Rectangle()
                                .fill(TiebaPureTheme.ColorToken.readerGroupedBackground)
                                .frame(height: ThreadReplyLayout.sectionSeparatorHeight)
                                .accessibilityHidden(true)

                            ForEach(Array(subposts.enumerated()), id: \.element.id) { index, subpost in
                                SubpostRowView(
                                    subpost: subpost,
                                    threadAuthorID: threadAuthorID,
                                    onOpenUser: { selectedUser = subpost.author },
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
                .navigationTitle(SubpostSheetTitle.text(floor: post.floor, count: post.subpostCount))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") { dismiss() }
                    }
                }
                .navigationDestination(isPresented: selectedUserIsActive) {
                    if let selectedUser {
                        UserProfileView(account: account, user: selectedUser)
                    }
                }
                .alert("提示", isPresented: likeActionErrorIsPresented) {
                    Button("好", role: .cancel) {
                        likeActionError = nil
                    }
                } message: {
                    Text(likeActionError ?? "")
                }
            }
            .accessibilityAction(named: "关闭楼中楼") {
                dismiss()
            }
            .task {
                guard didLoad == false else { return }
                await reload()
            }
            .onDisappear {
                loadTask?.cancel()
                requestGeneration += 1
                isLoading = false
                cancelLikeTasks()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .background {
                SubpostSheetInteractiveDismissInstaller(
                    onDismiss: onInteractiveDismiss
                )
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

    private func loadMore(generation: Int) async {
        guard isLoading == false, hasMore else { return }
        isLoading = true
        errorMessage = nil

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
            if requestedPage == 1 {
                subposts = loaded
            } else {
                let knownIDs = Set(subposts.map(\.id))
                subposts.append(contentsOf: loaded.filter { knownIDs.contains($0.id) == false })
            }
            hasMore = loaded.isEmpty == false && subposts.count < post.subpostCount
            nextPage = requestedPage + 1
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

private struct SubpostRowView: View {
    let subpost: Subpost
    let threadAuthorID: Int64?
    let onOpenUser: (() -> Void)?
    let isLikeUpdating: Bool
    let onToggleLike: (() -> Void)?

    var body: some View {
        ReaderCard {
            VStack(alignment: .leading, spacing: ThreadReplyLayout.headerContentSpacing) {
                UserHeaderView(
                    author: subpost.author,
                    floor: subpost.floor,
                    isThreadAuthor: isThreadAuthor,
                    showsFloorBadge: true,
                    trailingLikeCount: subpost.likeCount,
                    isLiked: subpost.isLiked,
                    isLikeUpdating: isLikeUpdating,
                    onToggleLike: onToggleLike,
                    likeAccessibilityIdentifier: "thread-subpost-like-button-\(subpost.id)",
                    onOpenUser: onOpenUser
                )

                VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
                    ContentBlocksView(
                        blocks: subpost.blocks,
                        textStyle: .reply,
                        lineLimit: ThreadContentDisplayPolicy.detailLineLimit,
                        inlineAccessibilityIdentifier: "thread-subpost-text"
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
