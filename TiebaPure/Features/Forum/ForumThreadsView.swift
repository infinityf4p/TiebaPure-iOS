import SwiftUI

struct ForumThreadsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.readerSplitOpenThread) private var readerSplitOpenThread
    @Environment(\.dismiss) private var dismiss
    let account: Account?
    let forum: Forum
    private let sortPreferenceStore: ForumThreadSortPreferenceStore
    private let openThreadInParent: ((ReaderSplitThreadRoute) -> Void)?
    private let openSearchInParent: ((ForumSearchLaunchRoute) -> Void)?
    private let openUserInParent: ((UserSummary) -> Void)?

    @ObservedObject private var blocklistStore = BlocklistStore.shared
    @State private var threads: [ThreadSummary] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var showsPinnedThreads = false
    @State private var activeSearch: ForumSearchLaunchRoute?
    @State private var activeThread: ForumThreadRoute?
    @State private var selectedUser: UserSummary?
    @State private var selectedCategory: ForumThreadCategory
    @State private var latestSortCategory: ForumThreadCategory
    @State private var requestGeneration = 0
    @State private var activeRequestKey: ForumThreadsRequestKey?
    @State private var loadTask: Task<[ThreadSummary], Error>?

    init(
        account: Account?,
        forum: Forum,
        sortPreferenceStore: ForumThreadSortPreferenceStore = ForumThreadSortPreferenceStore(),
        openThreadInParent: ((ReaderSplitThreadRoute) -> Void)? = nil,
        openSearchInParent: ((ForumSearchLaunchRoute) -> Void)? = nil,
        openUserInParent: ((UserSummary) -> Void)? = nil
    ) {
        self.account = account
        self.forum = forum
        self.sortPreferenceStore = sortPreferenceStore
        self.openThreadInParent = openThreadInParent
        self.openSearchInParent = openSearchInParent
        self.openUserInParent = openUserInParent
        let storedCategory = sortPreferenceStore.selection(for: forum)
        _selectedCategory = State(initialValue: storedCategory)
        _latestSortCategory = State(initialValue: storedCategory)
    }

    private var pinnedPresentation: ForumPinnedPresentation {
        ForumPinnedPresentationPolicy.presentation(
            threads: threads,
            showsPinnedThreads: showsPinnedThreads
        )
    }

    private var visibleThreads: [ThreadSummary] {
        pinnedPresentation.visibleThreads
    }

    var body: some View {
        VStack(spacing: 0) {
            forumThreadsScrollView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(forum.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: searchIsActive) {
            if let activeSearch {
                SearchResultsView(account: account, scope: activeSearch.scope, initialKeyword: activeSearch.keyword)
                    .interactiveNavigationPopStateSync {
                        self.activeSearch = nil
                    }
            }
        }
        .navigationDestination(isPresented: threadIsActive) {
            if let activeThread {
                ThreadDetailView(
                    account: account,
                    threadID: activeThread.threadID,
                    forumID: activeThread.forumID
                )
                .interactiveNavigationPopStateSync {
                    self.activeThread = nil
                }
            }
        }
        .navigationDestination(isPresented: userIsActive) {
            if let selectedUser {
                UserProfileView(account: account, user: selectedUser)
                    .interactiveNavigationPopStateSync {
                        self.selectedUser = nil
                    }
            }
        }
        .task {
            RecentForumStore.shared.save(forum)
            guard didLoad == false else { return }
            await reload()
        }
        .onChange(of: account?.id) { _ in
            loadTask?.cancel()
            requestGeneration += 1
            activeRequestKey = nil
            threads = []
            page = 1
            hasMore = true
            isLoading = false
            didLoad = false
            errorMessage = nil
            showsPinnedThreads = false
            activeSearch = nil
            activeThread = nil
            selectedUser = nil
            Task { await reload() }
        }
        .onChange(of: selectedCategory) { _, _ in
            loadTask?.cancel()
            requestGeneration += 1
            activeRequestKey = nil
            threads = []
            page = 1
            hasMore = true
            isLoading = false
            didLoad = false
            errorMessage = nil
            showsPinnedThreads = false
            Task { await reload() }
        }
        .onChange(of: blocklistStore.entries) { _ in
            threads.removeAll { TiebaContentFilter.shouldKeep(thread: $0) == false }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    launchSearch(.toolbarButton)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("搜索本吧")

                Menu {
                    Button {
                        Task { await reload() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading)

                    Button(role: .destructive) {
                        blockCurrentForum()
                    } label: {
                        Label("屏蔽\(forum.displayName)", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .minTouchTarget()
                .accessibilityLabel("更多")
                .accessibilityHint("刷新或屏蔽当前贴吧")
                .accessibilityIdentifier("forum-more-menu")
            }
        }
        .onDisappear {
            loadTask?.cancel()
            requestGeneration += 1
            isLoading = false
        }
        .fullScreenInteractiveNavigationPop()
    }

    private var categoryPicker: some View {
        HStack(spacing: TiebaPureTheme.Spacing.xs) {
            Menu {
                ForEach(ForumThreadCategory.latestSortOptions) { category in
                    Button {
                        sortPreferenceStore.select(category, for: forum)
                        latestSortCategory = category
                        selectedCategory = category
                    } label: {
                        if latestSortCategory == category {
                            Label(category.sortOptionTitle, systemImage: "checkmark")
                        } else {
                            Text(category.sortOptionTitle)
                        }
                    }
                    .accessibilityLabel(category.sortOptionTitle)
                    .accessibilityHint(category.accessibilityHint)
                    .accessibilityAddTraits(
                        latestSortCategory == category ? .isSelected : []
                    )
                    .accessibilityIdentifier(category.accessibilityIdentifier)
                }
            } label: {
                categoryTabLabel(
                    title: "最新",
                    systemImage: "chevron.down",
                    isSelected: selectedCategory.belongsToLatestTab
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("最新")
            .accessibilityValue(latestSortCategory.sortOptionTitle)
            .accessibilityHint("选择按回复时间或发帖时间排序")
            .accessibilityAddTraits(selectedCategory.belongsToLatestTab ? .isSelected : [])
            .accessibilityIdentifier("forum-category-latest-menu")

            Button {
                selectedCategory = .featured
            } label: {
                categoryTabLabel(
                    title: "精华",
                    isSelected: selectedCategory == .featured
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("精华")
            .accessibilityHint(ForumThreadCategory.featured.accessibilityHint)
            .accessibilityAddTraits(selectedCategory == .featured ? .isSelected : [])
            .accessibilityIdentifier(ForumThreadCategory.featured.accessibilityIdentifier)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("帖子分类")
        .accessibilityIdentifier("forum-category-picker")
    }

    private func categoryTabLabel(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: TiebaPureTheme.Spacing.xs) {
            Text(title)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            }
        }
        .font(.footnote.weight(isSelected ? .semibold : .regular))
        .foregroundStyle(
            isSelected
                ? TiebaPureTheme.ColorToken.primaryAccent
                : Color.secondary
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(
                    isSelected
                        ? TiebaPureTheme.ColorToken.primaryAccent.opacity(0.10)
                        : Color.clear
                )
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 64, minHeight: 44)
        .contentShape(Rectangle())
    }

    private var forumThreadsScrollView: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    categoryPicker

                    Divider()

                    forumThreadsContent
                }
                .frame(maxWidth: .infinity)
                .frame(
                    minHeight: max(proxy.size.height + 1, 1),
                    alignment: .top
                )
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("forum-threads-scroll-view")
            .shortPullRefresh(
                isEnabled: didLoad && isLoading == false,
                accessibilityIdentifier: "forum-refresh-animation"
            ) {
                guard isLoading == false else { return }
                await reload()
            }
            .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        }
    }

    @ViewBuilder
    private var forumThreadsContent: some View {
        if isLoading && didLoad == false {
            ReaderStateView.loading("正在加载帖子")
        } else if let errorMessage, threads.isEmpty {
            ReaderStateView.error(message: errorMessage) {
                Task { await reload() }
            }
        } else if threads.isEmpty {
            ReaderStateView.empty(
                title: "暂无帖子",
                message: "下拉即可刷新本吧帖子。",
                actionTitle: hasMore && didLoad ? "继续加载" : nil,
                action: hasMore && didLoad ? { Task { await loadMore() } } : nil
            )
        } else {
            LazyVStack(spacing: 0) {
                if pinnedPresentation.pinnedThreads.isEmpty == false {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            showsPinnedThreads.toggle()
                        }
                    } label: {
                        HStack(spacing: TiebaPureTheme.Spacing.xs) {
                            Image(systemName: "pin.fill")
                                .foregroundStyle(.secondary)
                            Text("置顶内容")
                                .font(.subheadline.weight(.medium))
                            Text("\(pinnedPresentation.pinnedThreads.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer(minLength: TiebaPureTheme.Spacing.sm)
                            Image(systemName: showsPinnedThreads ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, TiebaPureTheme.Spacing.md)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        showsPinnedThreads
                            ? "收起\(pinnedPresentation.pinnedThreads.count)条置顶内容"
                            : "展开\(pinnedPresentation.pinnedThreads.count)条置顶内容"
                    )
                    .accessibilityIdentifier("forum-pinned-threads-toggle")

                    Divider()
                }

                ForEach(Array(visibleThreads.enumerated()), id: \.element.id) { index, thread in
                    ForumThreadRow(
                        thread: thread,
                        showsForumInfo: false,
                        forumCategory: selectedCategory,
                        onOpenThread: {
                            openThread(
                                threadID: thread.id,
                                forumID: thread.forumID ?? forum.id
                            )
                        },
                        onOpenUser: openUser
                    )
                    .onAppear {
                        guard PaginationPrefetchPolicy.shouldLoadMore(
                            currentIndex: index,
                            totalCount: visibleThreads.count
                        ) else { return }
                        Task { await loadMore() }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("thread-row")

                    if index == visibleThreads.count - 1, isLoading, didLoad {
                        ProgressView()
                            .padding(TiebaPureTheme.Spacing.md)
                            .accessibilityLabel("正在加载更多帖子")
                    }
                }

                if let errorMessage {
                    InlineLoadErrorView(message: errorMessage) {
                        Task {
                            if page <= 1 { await reload() } else { await loadMore() }
                        }
                    }
                } else if hasMore, isLoading == false, didLoad {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        Label("加载更多帖子", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .minTouchTarget()
                    .padding(.horizontal, TiebaPureTheme.Spacing.md)
                    .accessibilityIdentifier("forum-threads-load-more")
                }

                Color.clear
                    .frame(height: 32)
                    .accessibilityHidden(true)
            }
            .readableWidth()
        }
    }

    private var searchIsActive: Binding<Bool> {
        Binding(
            get: { activeSearch != nil },
            set: { isActive in
                if isActive == false {
                    activeSearch = nil
                }
            }
        )
    }

    private var threadIsActive: Binding<Bool> {
        Binding(
            get: { activeThread != nil },
            set: { isActive in
                if isActive == false { activeThread = nil }
            }
        )
    }

    private var userIsActive: Binding<Bool> {
        Binding(
            get: { selectedUser != nil },
            set: { isActive in
                if isActive == false { selectedUser = nil }
            }
        )
    }

    private func openThread(threadID: Int64, forumID: Int64?) {
        // Explicit ownership from the parent is authoritative. SwiftUI does
        // not reliably carry custom environment values across a
        // `navigationDestination` boundary, so Home/ForumHub pass this
        // closure directly. The environment action remains a fallback for a
        // list embedded directly in a ReaderSplitLayout column.
        let parentAction = openThreadInParent ?? readerSplitOpenThread?.open
        if ForumThreadsOpenRoutingPolicy.destination(
            hasParentHandler: parentAction != nil
        ) == .parentReader, let parentAction {
            parentAction(ReaderSplitThreadRoute(threadID: threadID, forumID: forumID))
            return
        }
        activeThread = ForumThreadRoute(threadID: threadID, forumID: forumID)
    }

    private func reload() async {
        loadTask?.cancel()
        requestGeneration += 1
        isLoading = false
        page = 1
        hasMore = true
        errorMessage = nil
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
        let requestedPage = page
        let requestKey = ForumThreadsRequestKey(
            accountID: requestedAccountID,
            forumID: forum.id,
            forumName: forum.name,
            category: selectedCategory,
            page: requestedPage
        )
        activeRequestKey = requestKey
        isLoading = true
        errorMessage = nil
        var continuation: LocallyFilteredPaginationDecision?

        do {
            let task = Task {
                try await environment.api.forumThreads(
                    account: account,
                    forumName: requestKey.forumName,
                    page: requestKey.page,
                    category: requestKey.category
                )
            }
            loadTask = task
            let next = try await task.value
            guard generation == requestGeneration,
                  requestKey == activeRequestKey,
                  requestedAccountID == account?.id,
                  requestKey.category == selectedCategory else { return }
            let visibleNext = next.filter(TiebaContentFilter.shouldKeep(thread:))
            if requestedPage == 1 {
                threads = visibleNext
            } else {
                threads = HomeFeedMerge.append(existing: threads, incoming: visibleNext)
            }
            // Local block rules must not make a non-empty service page look
            // like the end of the forum.
            hasMore = next.isEmpty == false
            page = requestedPage + 1
            continuation = LocallyFilteredPaginationPolicy.decision(
                visibleItemCount: visibleNext.count,
                serverHasMore: hasMore,
                consecutiveHiddenPageCount: consecutiveHiddenPageCount
            )
        } catch is CancellationError {
            guard generation == requestGeneration,
                  requestKey == activeRequestKey else { return }
            loadTask = nil
            activeRequestKey = nil
            isLoading = false
            return
        } catch {
            guard generation == requestGeneration,
                  requestKey == activeRequestKey,
                  requestedAccountID == account?.id,
                  requestKey.category == selectedCategory else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration,
              requestKey == activeRequestKey else { return }
        loadTask = nil
        activeRequestKey = nil
        isLoading = false
        didLoad = true
        if let continuation, continuation.shouldAutomaticallyLoadNextPage {
            await loadMore(
                generation: generation,
                consecutiveHiddenPageCount: continuation.consecutiveHiddenPageCount
            )
        }
    }

    private func launchSearch(_ trigger: ForumSearchLaunchTrigger) {
        guard let route = ForumSearchLaunchPolicy.route(
            for: trigger,
            currentText: "",
            forum: forum
        ) else { return }
        if let openSearchInParent {
            openSearchInParent(route)
        } else {
            activeSearch = route
        }
    }

    private func openUser(_ user: UserSummary) {
        if let openUserInParent {
            openUserInParent(user)
        } else {
            selectedUser = user
        }
    }

    private func blockCurrentForum() {
        blocklistStore.addForum(id: forum.id, named: forum.name)
        dismiss()
    }
}

enum ForumThreadsOpenDestination: Equatable {
    case parentReader
    case localStack
}

enum ForumThreadsOpenRoutingPolicy {
    static func destination(hasParentHandler: Bool) -> ForumThreadsOpenDestination {
        hasParentHandler ? .parentReader : .localStack
    }
}

private struct ForumThreadRoute {
    let threadID: Int64
    let forumID: Int64?
}

struct ForumSearchLaunchRoute: Equatable {
    let keyword: String
    let scope: SearchScope
}

struct ForumPinnedPresentation: Equatable {
    let pinnedThreads: [ThreadSummary]
    let regularThreads: [ThreadSummary]
    let visibleThreads: [ThreadSummary]
}

enum ForumPinnedPresentationPolicy {
    static func presentation(
        threads: [ThreadSummary],
        showsPinnedThreads: Bool
    ) -> ForumPinnedPresentation {
        let pinnedThreads = threads.filter(\.isTop)
        let regularThreads = threads.filter { $0.isTop == false }
        return ForumPinnedPresentation(
            pinnedThreads: pinnedThreads,
            regularThreads: regularThreads,
            visibleThreads: showsPinnedThreads
                ? pinnedThreads + regularThreads
                : regularThreads
        )
    }
}

enum ForumSearchLaunchTrigger {
    case toolbarButton
    case keyboardSubmit
}

enum ForumSearchLaunchPolicy {
    static func route(
        for trigger: ForumSearchLaunchTrigger,
        currentText: String,
        forum: Forum
    ) -> ForumSearchLaunchRoute? {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trigger {
        case .toolbarButton:
            return ForumSearchLaunchRoute(keyword: trimmed, scope: .forum(forum))
        case .keyboardSubmit:
            guard trimmed.isEmpty == false else { return nil }
            return ForumSearchLaunchRoute(keyword: trimmed, scope: .forum(forum))
        }
    }
}

struct ForumThreadRow: View {
    enum Presentation {
        case list
        case homeFeed
        case userProfile

        var showsDivider: Bool {
            switch self {
            case .list:
                return true
            case .homeFeed, .userProfile:
                return false
            }
        }

        var cardRadius: CGFloat {
            switch self {
            case .list:
                return 0
            case .homeFeed, .userProfile:
                return TiebaPureTheme.Radius.card
            }
        }

        func mediaLimit(totalCount: Int) -> Int? {
            switch self {
            case .list, .homeFeed, .userProfile:
                return ForumFeedMediaLayoutPolicy.visibleItemCount(totalCount: totalCount)
            }
        }

        var usesCompactFeedLayout: Bool {
            switch self {
            case .list, .homeFeed, .userProfile:
                return true
            }
        }

        func mediaMaxHeight(itemCount: Int) -> CGFloat? {
            switch self {
            case .list:
                return nil
            case .homeFeed, .userProfile:
                return itemCount == 1 ? 180 : 118
            }
        }

    }

    let thread: ThreadSummary
    var showsForumInfo = true
    var presentation: Presentation = .list
    var forumCategory: ForumThreadCategory?
    var highlightKeyword: String?
    var onOpenThread: (() -> Void)?
    var onOpenForum: ((Forum) -> Void)?
    var onOpenUser: ((UserSummary) -> Void)?
    var onBlockForum: ((ThreadSummary) -> Void)?
    var onOpenMedia: ((ReaderMediaItem, [ReaderMediaItem], CGRect?, UIImage?, ImagePreviewSourceAnchor?) -> Void)?
    var threadOpenAccessibilityIdentifier = "thread-open-area"

    var body: some View {
        ReaderCard(showsDivider: presentation.showsDivider, cornerRadius: presentation.cardRadius) {
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
                HStack(alignment: .top, spacing: TiebaPureTheme.Spacing.xs) {
                    threadHeader
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let onBlockForum {
                        Menu {
                            if canBlockForum {
                                Button(role: .destructive) {
                                    onBlockForum(thread)
                                } label: {
                                    Label(
                                        "屏蔽\(forumBlockDisplayName)",
                                        systemImage: "eye.slash"
                                    )
                                }
                            } else {
                                Button("贴吧信息不可用") {}
                                    .disabled(true)
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(forumBlockDisplayName)的更多帖子操作")
                        .accessibilityHint("屏蔽该帖子所属贴吧")
                        .accessibilityIdentifier("thread-forum-menu-\(thread.id)")
                    }
                }

                if hasThreadBodyPreview {
                    threadBodyPreview
                }

                if badgeItems.isEmpty == false {
                    HStack(spacing: TiebaPureTheme.Spacing.xs) {
                        ForEach(badgeItems, id: \.title) { item in
                            CapsuleLabel(item.title, systemImage: item.systemImage)
                        }
                    }
                }

                let allMedia = mediaItems
                let previewMedia = mediaPreviewItems(from: allMedia)
                if previewMedia.isEmpty == false {
                    decorativeMediaOpensThread {
                        MediaGridView(
                            items: previewMedia,
                            maxItemHeight: presentation.mediaMaxHeight(itemCount: previewMedia.count),
                            totalItemCount: allMedia.count,
                            usesCompactFeedLayout: presentation.usesCompactFeedLayout,
                            isInteractive: onOpenMedia != nil,
                            onTap: { item, sourceFrame, sourceImage, sourceAnchor in
                                guard ForumThreadTapPolicy.destination(for: .media) == .media else { return }
                                onOpenMedia?(item, allMedia, sourceFrame, sourceImage, sourceAnchor)
                            }
                        )
                    }
                }

                InteractionStatsView(
                    comments: thread.replyCount,
                    likes: thread.likeCount
                )
                    .padding(.top, TiebaPureTheme.Spacing.xxs)
            }
        }
    }

    @ViewBuilder
    private var threadHeader: some View {
        switch presentation {
        case .userProfile:
            UserProfileThreadHeader(
                thread: thread,
                onOpenForum: onOpenForum
            )
        case .list, .homeFeed:
            if showsForumInfo, let forum = thread.forumRoute {
                ForumInfoHeader(
                    thread: thread,
                    forum: forum,
                    onOpenForum: onOpenForum,
                    onOpenUser: onOpenUser
                )
            } else {
                AuthorHeader(
                    thread: thread,
                    category: forumCategory,
                    onOpenUser: onOpenUser
                )
            }
        }
    }

    private var hasThreadBodyPreview: Bool {
        thread.title.isEmpty == false || inlinePreviewBlocks.isEmpty == false
    }

    @ViewBuilder
    private var threadBodyPreview: some View {
        threadBodyButton {
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
                if thread.title.isEmpty == false {
                    KeywordHighlightedText(
                        text: thread.title,
                        keyword: highlightKeyword,
                        font: .body.weight(.semibold),
                        lineLimit: ThreadContentDisplayPolicy.summaryLineLimit
                    )
                } else if inlinePreviewBlocks.isEmpty == false {
                    InlineContentText(
                        blocks: inlinePreviewBlocks,
                        style: .body,
                        lineLimit: ThreadContentDisplayPolicy.summaryLineLimit,
                        highlightKeyword: highlightKeyword,
                        allowsLinkInteraction: false
                    )
                }

                if thread.title.isEmpty == false, inlinePreviewBlocks.isEmpty == false {
                    InlineContentText(
                        blocks: inlinePreviewBlocks,
                        style: previewTextStyle,
                        lineLimit: ThreadContentDisplayPolicy.summaryLineLimit,
                        highlightKeyword: highlightKeyword,
                        allowsLinkInteraction: false
                    )
                }
            }
        }
    }

    /// Decorative media exposes no controls of its own, so taps on it keep the
    /// pre-split whole-row behavior and open the thread. The overlay stays out
    /// of the accessibility tree; "thread-open-area" already provides the
    /// accessible open action for the row.
    @ViewBuilder
    private func decorativeMediaOpensThread<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if onOpenMedia == nil, let onOpenThread {
            content()
                .overlay {
                    Button {
                        guard ForumThreadTapPolicy.destination(for: .threadBody) == .thread else { return }
                        onOpenThread()
                    } label: {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)
                }
        } else {
            content()
        }
    }

    @ViewBuilder
    private func threadBodyButton<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let onOpenThread {
            ZStack(alignment: .topLeading) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .overlay {
                Button {
                    guard ForumThreadTapPolicy.destination(for: .threadBody) == .thread else { return }
                    onOpenThread()
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel(thread.title.isEmpty ? "打开帖子" : thread.title)
                .accessibilityValue(thread.textPreview)
                .accessibilityHint("打开帖子详情")
                .accessibilityIdentifier(threadOpenAccessibilityIdentifier)
            }
        } else {
            content()
        }
    }

    private var badgeItems: [ForumThreadBadgeItem] {
        ForumThreadBadgePolicy.items(
            isTop: thread.isTop,
            isGood: thread.isGood,
            hasVideo: thread.hasVideo
        )
    }

    private var mediaItems: [ReaderMediaItem] {
        Array(thread.blocks.enumerated()).compactMap { index, block in
            switch block {
            case let .image(image):
                return ReaderMediaItem(
                    id: "image-\(thread.id)-\(index)",
                    kind: .image,
                    thumbnailURL: image.thumbnailURL ?? image.originalURL,
                    image: image,
                    aspectRatio: CGFloat(image.aspectRatio),
                    accessibilityLabel: "帖子图片"
                )
            case let .video(video):
                return ReaderMediaItem(
                    id: "video-\(thread.id)-\(index)",
                    kind: .video,
                    thumbnailURL: video.coverURL,
                    video: video,
                    aspectRatio: CGFloat(video.aspectRatio),
                    accessibilityLabel: "帖子视频"
                )
            default:
                return nil
            }
        }
    }

    private var inlinePreviewBlocks: [ContentBlock] {
        var result: [ContentBlock] = []
        for block in thread.blocks {
            switch block {
            case .text, .link, .mention, .emoticon:
                result.append(block)
            case .image, .video:
                if result.isEmpty == false {
                    return result
                }
            }
        }
        return result
    }

    private var previewTextStyle: InlineContentText.Style {
        switch presentation {
        case .userProfile:
            return .body
        case .list, .homeFeed:
            return .preview
        }
    }

    private func mediaPreviewItems(from mediaItems: [ReaderMediaItem]) -> [ReaderMediaItem] {
        guard let limit = presentation.mediaLimit(totalCount: mediaItems.count) else {
            return mediaItems
        }
        return Array(mediaItems.prefix(limit))
    }

    private var canBlockForum: Bool {
        (thread.forumID ?? 0) > 0 || thread.forumDisplayNameResolved != nil
    }

    private var forumBlockDisplayName: String {
        thread.forumDisplayNameResolved ?? "该吧"
    }
}

private struct UserProfileThreadHeader: View {
    let thread: ThreadSummary
    let onOpenForum: ((Forum) -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.sm) {
            AvatarView(
                url: thread.author.portraitURL,
                title: thread.author.displayNameResolved,
                size: TiebaPureTheme.AvatarSize.medium
            )

            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                Text(thread.author.displayNameResolved)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: TiebaPureTheme.Spacing.xxs) {
                    forumIdentity

                    if let date = thread.createdAt ?? thread.lastReplyAt {
                        Text("·")
                            .accessibilityHidden(true)
                        Text(ReaderDateText.string(from: date))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("user-profile-thread-header")
    }

    @ViewBuilder
    private var forumIdentity: some View {
        if let forum = thread.forumRoute, let onOpenForum {
            Button {
                onOpenForum(forum)
            } label: {
                Text(forum.displayName)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("进入\(forum.displayName)")
        } else if let forum = thread.forumRoute {
            Text(forum.displayName)
        }
    }
}

struct ForumThreadBadgeItem: Equatable {
    let title: String
    let systemImage: String
}

enum ForumThreadBadgePolicy {
    static func items(isTop: Bool, isGood: Bool, hasVideo _: Bool) -> [ForumThreadBadgeItem] {
        var items: [ForumThreadBadgeItem] = []
        if isTop {
            items.append(ForumThreadBadgeItem(title: "置顶", systemImage: "pin.fill"))
        }
        if isGood {
            items.append(ForumThreadBadgeItem(title: "精品", systemImage: "sparkles"))
        }
        return items
    }
}

enum ForumThreadTapTarget {
    case forumIdentity
    case userIdentity
    case threadBody
    case media
    case stats
}

enum ForumThreadTapDestination: Equatable {
    case forum
    case user
    case thread
    case media
    case none
}

enum ForumThreadTapPolicy {
    static func destination(for target: ForumThreadTapTarget) -> ForumThreadTapDestination {
        switch target {
        case .forumIdentity:
            return .forum
        case .userIdentity:
            return .user
        case .threadBody:
            return .thread
        case .media:
            return .media
        case .stats:
            return .none
        }
    }
}

private struct ForumInfoHeader: View {
    let thread: ThreadSummary
    let forum: Forum
    let onOpenForum: ((Forum) -> Void)?
    let onOpenUser: ((UserSummary) -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.sm) {
            forumAvatar

            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                forumName

                HStack(spacing: TiebaPureTheme.Spacing.xxs) {
                    userName
                    if let dateText = thread.lastReplyAt.map({ ReaderDateText.string(from: $0) }),
                       dateText.isEmpty == false {
                        Text("·")
                            .accessibilityHidden(true)
                        Text(dateText)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var forumAvatar: some View {
        if let onOpenForum {
            Button {
                onOpenForum(forum)
            } label: {
                AvatarView(
                    url: forum.avatarURL,
                    title: forum.displayName,
                    size: TiebaPureTheme.AvatarSize.small
                )
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("进入\(forum.displayName)")
        } else {
            AvatarView(
                url: forum.avatarURL,
                title: forum.displayName,
                size: TiebaPureTheme.AvatarSize.small
            )
        }
    }

    @ViewBuilder
    private var forumName: some View {
        if let onOpenForum {
            Button {
                guard ForumThreadTapPolicy.destination(for: .forumIdentity) == .forum else { return }
                onOpenForum(forum)
            } label: {
                Text(forum.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("进入\(forum.displayName)")
        } else {
            Text(forum.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var userName: some View {
        if let onOpenUser {
            Button {
                guard ForumThreadTapPolicy.destination(for: .userIdentity) == .user else { return }
                onOpenUser(thread.author)
            } label: {
                Text(thread.author.displayNameResolved)
                    .lineLimit(1)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看用户\(thread.author.displayNameResolved)的主页")
            .accessibilityIdentifier("feed-user-button-\(thread.author.id)")
        } else {
            Text(thread.author.displayNameResolved)
                .lineLimit(1)
        }
    }
}

private struct AuthorHeader: View {
    let thread: ThreadSummary
    var category: ForumThreadCategory?
    let onOpenUser: ((UserSummary) -> Void)?

    var body: some View {
        if let onOpenUser {
            Button {
                onOpenUser(thread.author)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("查看用户\(thread.author.displayNameResolved)的主页")
            .accessibilityIdentifier("feed-user-button-\(thread.author.id)")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.sm) {
            AvatarView(url: thread.author.portraitURL, title: thread.author.displayNameResolved, size: TiebaPureTheme.AvatarSize.small)

            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                Text(thread.author.displayNameResolved)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                MetadataLine(
                    [metadataText],
                    systemImage: metadataSystemImage
                )
            }
        }
    }

    private var metadataText: String {
        guard let category else {
            return thread.lastReplyAt.map { ReaderDateText.string(from: $0) } ?? ""
        }
        let metadata = category.metadata(for: thread)
        guard let date = metadata.date else { return "" }
        return ReaderDateText.string(from: date) + metadata.actionSuffix
    }

    private var metadataSystemImage: String {
        category?.metadata(for: thread).systemImage
            ?? "bubble.left.and.text.bubble.right"
    }
}
