import SwiftUI
import UIKit

struct ThreadDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        if let mainPost {
                            PostRowView(
                                post: mainPost,
                                threadTitle: threadPage?.thread.title,
                                threadAuthorID: threadAuthorID,
                                isMainPost: true,
                                onOpenSubposts: openSubpostsIfPossible
                            )
                            .padding(.bottom, TiebaPureTheme.Spacing.xs)
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
                                        onOpenSubposts: openSubpostsIfPossible
                                    )
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
        .alert("已复制链接", isPresented: $didCopyLink) {
            Button("好", role: .cancel) {}
        }
        .sheet(item: $selectedSubpostPost) { post in
            if let forumID = resolvedForumID {
                SubpostListSheet(
                    account: account,
                    threadID: threadID,
                    forumID: forumID,
                    post: post,
                    threadAuthorID: threadAuthorID,
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
            showsInlineRefreshAnimation = false
            showsPullRefreshIndicator = false
            pendingInitialPostID = initialPostID
            scrollDistanceFromTop = 0
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
            resetPullGestureState()
        }
        .fullScreenInteractiveNavigationPop(isEnabled: selectedSubpostPost == nil)
    }

    private func refreshablePostScrollView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
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
        .coordinateSpace(name: ThreadDetailScrollCoordinateSpace.name)
        .onPreferenceChange(ThreadDetailScrollTopOffsetPreferenceKey.self) { markerOffset in
            if #unavailable(iOS 18.0) {
                scrollDistanceFromTop = ShortPullRefreshPolicy.distanceFromTop(
                    markerOffset: markerOffset
                )
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
                if didRecordBrowsingHistory == false {
                    BrowsingHistoryStore.shared.record(
                        thread: loaded.thread,
                        forum: loaded.forum,
                        fallbackForumID: forumID
                    )
                    didRecordBrowsingHistory = true
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
            return
        } catch {
            guard generation == requestGeneration,
                  requestedAccountID == account?.id,
                  requestedSeeLz == seeLz,
                  requestedSort == sortType else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
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
    let post: Post
    let threadAuthorID: Int64?
    let onInteractiveDismiss: () -> Void

    @State private var subposts: [Subpost] = []
    @State private var nextPage = 1
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var requestGeneration = 0
    @State private var loadTask: Task<[Subpost], Error>?

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
                                        trailingLikeCount: post.likeCount
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
                                SubpostRowView(subpost: subpost, threadAuthorID: threadAuthorID)
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .background {
                SubpostSheetInteractiveDismissInstaller(
                    onDismiss: onInteractiveDismiss
                )
            }
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
}

private struct SubpostRowView: View {
    let subpost: Subpost
    let threadAuthorID: Int64?

    var body: some View {
        ReaderCard {
            VStack(alignment: .leading, spacing: ThreadReplyLayout.headerContentSpacing) {
                UserHeaderView(
                    author: subpost.author,
                    floor: subpost.floor,
                    isThreadAuthor: isThreadAuthor,
                    showsFloorBadge: true,
                    trailingLikeCount: subpost.likeCount
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
