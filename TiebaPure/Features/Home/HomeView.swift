import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.readingPreferences) private var readingPreferences
    let account: Account?
    var refreshToken: Int = 0

    @ObservedObject private var blocklistStore = BlocklistStore.shared
    @State private var activeSearch: SearchRoute?
    @State private var threads: [ThreadSummary] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var navigationPath: [HomeNavigationRoute] = []
    @State private var selectedUser: UserSummary?
    @State private var programmaticRefreshToken = 0
    @State private var lastScenePhase: ScenePhase = .inactive
    @State private var scrollToTopRequest = 0
    @State private var requestGeneration = 0
    @State private var loadTask: Task<[ThreadSummary], Error>?
    @State private var pendingPaginationRequest = false
    @State private var paginationRequestScheduled = false
    @State private var splitDetailPath: [ReaderSplitThreadRoute] = []

    var body: some View {
        ReaderSplitLayout(
            account: account,
            navigationPath: $navigationPath,
            detailPath: $splitDetailPath,
            openThreadInDetail: { openThreadInSplitDetail($0) },
            openThreadInCompact: { openThreadInCompactStack($0) },
            listColumn: { feedColumn },
            detailRoot: { placeholder in
                // Regular width routes global search into the detail column so
                // the feed list stays visible and drivable next to it.
                placeholder
                    .navigationDestinationCompat(isPresented: splitSearchIsActive) {
                        if let activeSearch {
                            SearchResultsView(account: account, scope: .global, initialKeyword: activeSearch.keyword)
                                .interactiveNavigationPopStateSync {
                                    self.activeSearch = nil
                                }
                        }
                    }
            }
        )
        .toolbar(.visible, for: .tabBar)
        .onChange(of: horizontalSizeClass) { sizeClass in
            foldNavigationForSizeClassChange(to: sizeClass)
        }
    }

    private var feedColumn: some View {
        ScrollViewReader { scrollProxy in
            refreshableScrollView {
                feedContent
            }
            .onChange(of: scrollToTopRequest) { _ in
                if reduceMotion || disablesUITestAnimations {
                    scrollProxy.scrollTo(HomeScrollTarget.top, anchor: .top)
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        scrollProxy.scrollTo(HomeScrollTarget.top, anchor: .top)
                    }
                }
            }
        }
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    activeSearch = SearchRoute(keyword: "")
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .minTouchTarget()
                .accessibilityLabel("搜索")
                .accessibilityHint("打开单独的搜索页面")
                .accessibilityIdentifier("home-search-button")
            }
        }
        .navigationDestinationCompat(isPresented: searchIsActive) {
            if let activeSearch {
                SearchResultsView(account: account, scope: .global, initialKeyword: activeSearch.keyword)
                    .interactiveNavigationPopStateSync {
                        self.activeSearch = nil
                    }
            }
        }
        .navigationDestination(for: HomeNavigationRoute.self) { route in
            switch route {
            case let .thread(threadRoute):
                ThreadDetailView(
                    account: account,
                    threadID: threadRoute.threadID,
                    forumID: threadRoute.forumID,
                    initialPostID: threadRoute.initialPostID,
                    ownThreadDeletionTarget: threadRoute.ownThreadDeletionTarget
                )
                .interactiveNavigationPopStateSync {
                    removeNavigationRouteIfCurrent(route)
                }
            case let .forum(id, name, displayName, avatarURL):
                ForumThreadsView(
                    account: account,
                    forum: Forum(
                        id: id,
                        name: name,
                        displayName: displayName,
                        avatarURL: avatarURL,
                        memberCount: 0,
                        threadCount: 0
                    ),
                    openThreadInParent: { route in
                        openThreadFromNestedForum(route)
                    }
                )
                .interactiveNavigationPopStateSync {
                    removeNavigationRouteIfCurrent(route)
                }
            }
        }
        .navigationDestinationCompat(isPresented: selectedUserIsActive) {
            if let selectedUser {
                UserProfileView(account: account, user: selectedUser)
                    .interactiveNavigationPopStateSync {
                        self.selectedUser = nil
                    }
            }
        }
        .interactiveNavigationPopRevealSource()
        .task {
            guard didLoad == false else { return }
            await reload(trigger: .initial)
        }
        .onChange(of: refreshToken) { _ in
            // Tab re-tap while pushed pops to root instead of refreshing
            // the covered feed, matching the iOS tab-reselect convention. In
            // the split layout the detail selection likewise clears back to
            // the placeholder without reloading.
            if navigationPath.isEmpty == false || activeSearch != nil || selectedUser != nil
                || splitDetailPath.isEmpty == false {
                navigationPath = []
                activeSearch = nil
                selectedUser = nil
                splitDetailPath = []
                return
            }
            programmaticRefreshToken &+= 1
        }
        .onChange(of: account?.sessionIdentity) { _ in
            requestGeneration += 1
            loadTask?.cancel()
            threads = []
            page = 1
            hasMore = true
            didLoad = false
            isLoading = false
            pendingPaginationRequest = false
            paginationRequestScheduled = false
            errorMessage = nil
            navigationPath = []
            selectedUser = nil
            splitDetailPath = []
            Task { await reload(trigger: .initial) }
        }
        .onChange(of: blocklistStore.entries) { _ in
            threads.removeAll { TiebaContentFilter.shouldKeep(thread: $0) == false }
        }
        .onChange(of: scenePhase) { newPhase in
            let previousPhase = lastScenePhase
            lastScenePhase = newPhase
            guard HomeOpenRefreshPolicy.shouldRefreshOnScenePhaseChange(
                from: previousPhase,
                to: newPhase,
                didLoad: didLoad
            ) else {
                return
            }
            Task { await reload(trigger: .appOpen) }
        }
        .onDisappear {
            loadTask?.cancel()
            requestGeneration += 1
            isLoading = false
            pendingPaginationRequest = false
            paginationRequestScheduled = false
        }
    }

    private var usesSplitDetailLayout: Bool {
        horizontalSizeClass == .regular
    }

    // Search presents in exactly one column per layout: the feed stack when
    // compact, the detail column when the split layout is active.
    private var searchIsActive: Binding<Bool> {
        Binding(
            get: { usesSplitDetailLayout == false && activeSearch != nil },
            set: { isActive in
                if isActive == false {
                    activeSearch = nil
                }
            }
        )
    }

    private var splitSearchIsActive: Binding<Bool> {
        Binding(
            get: { usesSplitDetailLayout && activeSearch != nil },
            set: { isActive in
                if isActive == false {
                    activeSearch = nil
                }
            }
        )
    }

    private var selectedUserIsActive: Binding<Bool> {
        Binding(
            get: { selectedUser != nil },
            set: { isActive in
                if isActive == false { selectedUser = nil }
            }
        )
    }

    private func removeNavigationRouteIfCurrent(_ route: HomeNavigationRoute) {
        guard navigationPath.last == route else { return }
        navigationPath.removeLast()
    }

    private func openThread(threadID: Int64, forumID: Int64?) {
        let route = ReaderSplitThreadRoute(threadID: threadID, forumID: forumID)
        if usesSplitDetailLayout {
            openThreadInSplitDetail(route)
            return
        }
        navigationPath.append(.thread(route))
    }

    private func openThreadInSplitDetail(_ route: ReaderSplitThreadRoute) {
        // A newly selected thread owns the whole detail column; a search page
        // pushed there would otherwise keep covering the new selection.
        activeSearch = nil
        splitDetailPath = [route]
    }

    private func openThreadInCompactStack(_ route: ReaderSplitThreadRoute) {
        navigationPath.append(.thread(route))
    }

    private func openThreadFromNestedForum(_ route: ReaderSplitThreadRoute) {
        if usesSplitDetailLayout {
            openThreadInSplitDetail(route)
        } else {
            openThreadInCompactStack(route)
        }
    }

    /// Keeps the open thread when the split layout appears or collapses
    /// mid-session (e.g. iPad Split View resizes across the width threshold).
    private func foldNavigationForSizeClassChange(to sizeClass: UserInterfaceSizeClass?) {
        let bridged = HomeSplitDetailBridgePolicy.state(
            changingTo: sizeClass,
            navigationPath: navigationPath,
            splitDetail: splitDetailPath.last
        )
        navigationPath = bridged.navigationPath
        splitDetailPath = bridged.splitDetail.map { [$0] } ?? []
    }

    @ViewBuilder
    private var feedContent: some View {
        Color.clear
            .frame(height: 0)
            .id(HomeScrollTarget.top)

        if isLoading && didLoad == false {
            ReaderStateView.loading("正在加载帖子")
        } else if let errorMessage, threads.isEmpty {
            ReaderStateView.error(message: errorMessage) {
                Task { await reload(trigger: .retry) }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, TiebaPureTheme.Spacing.lg)
        } else if threads.isEmpty {
            ReaderStateView.empty(
                title: "暂无推荐",
                message: "下拉即可刷新推荐帖子。",
                actionTitle: hasMore && didLoad ? "继续加载" : nil,
                action: hasMore && didLoad ? { Task { await loadMore() } } : nil
            )
            .frame(maxWidth: .infinity)
            .padding(.top, TiebaPureTheme.Spacing.lg)
        } else {
            LazyVStack(spacing: TiebaPureTheme.Spacing.sm, pinnedViews: []) {
                ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                    ForumThreadRow(
                        thread: thread,
                        presentation: .homeFeed,
                        onOpenThread: {
                            openThread(threadID: thread.id, forumID: thread.forumID)
                        },
                        onOpenForum: { forum in
                            RecentForumStore.shared.save(forum)
                            navigationPath.append(.fromForum(forum))
                        },
                        onOpenUser: { selectedUser = $0 },
                        onBlockForum: { blockedThread in
                            blocklistStore.addForum(
                                id: blockedThread.forumID,
                                named: blockedThread.forumName
                            )
                        },
                        onOpenMedia: { item, mediaItems, sourceFrame, sourceImage, sourceAnchor in
                            switch HomeMediaActionPolicy.action(for: item, in: mediaItems) {
                            case let .previewImages(images, index):
                                ImagePreviewCoordinator.shared.present(
                                    ImagePreviewSession(
                                        images: images,
                                        initialIndex: index,
                                        sourceFrame: sourceFrame,
                                        sourceImage: sourceImage,
                                        sourceAnchor: sourceAnchor,
                                        prefetchesAdjacentPages: readingPreferences.mediaLoading != .manual
                                    )
                                )
                            case let .playVideo(video):
                                VideoPreviewCoordinator.shared.present(
                                    VideoPreviewSession(
                                        video: video,
                                        sourceFrame: sourceFrame,
                                        sourceImage: sourceImage,
                                        sourceAnchor: sourceAnchor
                                    )
                                )
                            case .openThread:
                                openThread(threadID: thread.id, forumID: thread.forumID)
                            }
                        }
                    )
                    .onAppear {
                        requestLoadMoreIfNeeded(currentIndex: index, totalCount: threads.count)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("thread-row")

                    if index == threads.count - 1, isLoading, didLoad {
                        ProgressView()
                            .padding(TiebaPureTheme.Spacing.md)
                            .accessibilityLabel("正在加载更多帖子")
                    }
                }

                if let errorMessage {
                    InlineLoadErrorView(message: errorMessage) {
                        Task {
                            if page <= 1 { await reload(trigger: .retry) }
                            else {
                                self.errorMessage = nil
                                await loadMore()
                            }
                        }
                    }
                } else if hasMore, isLoading == false, didLoad {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        Label("加载更多", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .minTouchTarget()
                    .accessibilityHint("加载下一页推荐帖子")
                    .padding(.horizontal, TiebaPureTheme.Spacing.md)
                }

                Color.clear
                    .frame(height: 64)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, TiebaPureTheme.Spacing.sm)
            .padding(.vertical, TiebaPureTheme.Spacing.sm)
            .readableWidth()
        }
    }

    @ViewBuilder
    private func refreshableScrollView<Content: View>(
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .scrollBounceBehaviorAlwaysVertical()
        .accessibilityIdentifier("home-feed-scroll-view")
        .shortPullRefresh(
            isEnabled: didLoad && isLoading == false,
            surface: .grouped,
            accessibilityIdentifier: "home-refresh-animation",
            programmaticRefreshToken: programmaticRefreshToken
        ) { source in
            if source == .pullGesture {
                guard isLoading == false else { return }
            }
            await reload(
                trigger: source == .programmatic ? .tabTap : .pullToRefresh
            )
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
    }

    private func reload(trigger: HomeRefreshTrigger) async {
        if HomeRefreshRevealPolicy.shouldScrollToTop(
            trigger: trigger,
            hasExistingContent: threads.isEmpty == false
        ) {
            scrollToTopRequest += 1
        }
        loadTask?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        isLoading = false
        pendingPaginationRequest = false
        paginationRequestScheduled = false
        page = 1
        hasMore = true
        errorMessage = nil
        await loadMore(generation: generation)
    }

    private var disablesUITestAnimations: Bool {
        HomeRefreshAnimationPolicy.disablesUITestAnimations(
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    private func loadMore() async {
        await loadMore(generation: requestGeneration)
    }

    private func loadMore(
        generation: Int,
        consecutiveHiddenPageCount: Int = 0
    ) async {
        guard hasMore else {
            pendingPaginationRequest = false
            return
        }
        guard errorMessage == nil else {
            pendingPaginationRequest = false
            return
        }
        guard isLoading == false else {
            pendingPaginationRequest = true
            return
        }
        let requestedSession = account?.sessionIdentity
        isLoading = true
        errorMessage = nil
        var continuation: LocallyFilteredPaginationDecision?

        do {
            let requestedPage = page
            let task = Task {
                try await environment.api.personalizedThreads(
                    account: account,
                    page: requestedPage,
                    loadType: requestedPage == 1 ? 1 : 2
                )
            }
            loadTask = task
            let next = try await task.value
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity else { return }
            let visibleNext = next.filter(TiebaContentFilter.shouldKeep(thread:))
            if requestedPage == 1 {
                threads = HomeFeedMerge.refresh(existing: threads, incoming: visibleNext)
            } else {
                threads = HomeFeedMerge.append(existing: threads, incoming: visibleNext)
            }
            // Pagination follows the service page, not the number left after
            // applying local block rules.
            hasMore = next.isEmpty == false
            page = requestedPage + 1
            continuation = LocallyFilteredPaginationPolicy.decision(
                visibleItemCount: visibleNext.count,
                serverHasMore: hasMore,
                consecutiveHiddenPageCount: consecutiveHiddenPageCount
            )
        } catch is CancellationError {
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity else { return }
            loadTask = nil
            isLoading = false
            pendingPaginationRequest = false
            paginationRequestScheduled = false
            return
        } catch {
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration,
              requestedSession == account?.sessionIdentity else { return }
        loadTask = nil
        isLoading = false
        didLoad = true
        if let continuation, continuation.shouldAutomaticallyLoadNextPage {
            await loadMore(
                generation: generation,
                consecutiveHiddenPageCount: continuation.consecutiveHiddenPageCount
            )
            return
        }
        if continuation?.shouldOfferManualContinuation == true {
            // A still-visible footer/empty-state button resumes with a fresh
            // bounded batch instead of turning a queued prefetch into a loop.
            pendingPaginationRequest = false
            return
        }
        let shouldContinuePagination = pendingPaginationRequest
            && hasMore
            && errorMessage == nil
        pendingPaginationRequest = false
        if shouldContinuePagination {
            await loadMore(generation: generation)
        }
    }

    private func requestLoadMoreIfNeeded(currentIndex: Int, totalCount: Int) {
        guard PaginationPrefetchPolicy.shouldLoadMore(
            currentIndex: currentIndex,
            totalCount: totalCount
        ) else { return }
        if isLoading {
            pendingPaginationRequest = true
            return
        }
        guard paginationRequestScheduled == false else { return }
        paginationRequestScheduled = true
        Task {
            await loadMore()
            paginationRequestScheduled = false
        }
    }
}

enum HomeRefreshTrigger {
    case initial
    case retry
    case pullToRefresh
    case tabTap
    case appOpen
}

enum HomeRefreshAnimationPolicy {
    static var minimumVisibleDurationNanoseconds: UInt64 {
        minimumVisibleDurationNanoseconds(arguments: ProcessInfo.processInfo.arguments)
    }

    static func minimumVisibleDurationNanoseconds(arguments: [String]) -> UInt64 {
        #if DEBUG
        if arguments.contains("UITEST_EXTENDED_REFRESH_ANIMATION") {
            return 5_000_000_000
        }
        #endif

        return 600_000_000
    }

    static func disablesUITestAnimations(arguments: [String]) -> Bool {
        #if DEBUG
        return arguments.contains("UITEST_DISABLE_ANIMATIONS")
        #else
        return false
        #endif
    }

    static func remainingVisibleDurationNanoseconds(minimum: UInt64, elapsed: UInt64) -> UInt64 {
        minimum > elapsed ? minimum - elapsed : 0
    }
}

enum HomeRefreshRevealPolicy {
    static func shouldScrollToTop(trigger: HomeRefreshTrigger, hasExistingContent: Bool) -> Bool {
        hasExistingContent && trigger == .tabTap
    }
}

enum HomeOpenRefreshPolicy {
    static func shouldRefreshOnScenePhaseChange(
        from previousPhase: ScenePhase,
        to newPhase: ScenePhase,
        didLoad: Bool
    ) -> Bool {
        didLoad && previousPhase == .background && newPhase == .active
    }
}

private enum HomeScrollTarget {
    case top
}

enum HomeFeedMerge {
    static let maximumItemCount = 300

    static func refresh(
        existing: [ThreadSummary],
        incoming: [ThreadSummary],
        maximumItemCount: Int = HomeFeedMerge.maximumItemCount
    ) -> [ThreadSummary] {
        merge(
            preferred: incoming,
            fallback: existing,
            maximumItemCount: maximumItemCount
        )
    }

    static func append(
        existing: [ThreadSummary],
        incoming: [ThreadSummary],
        maximumItemCount: Int = HomeFeedMerge.maximumItemCount
    ) -> [ThreadSummary] {
        merge(
            preferred: existing,
            fallback: incoming,
            maximumItemCount: maximumItemCount
        )
    }

    private static func merge(
        preferred: [ThreadSummary],
        fallback: [ThreadSummary],
        maximumItemCount: Int
    ) -> [ThreadSummary] {
        let boundedCount = max(maximumItemCount, 0)
        guard boundedCount > 0 else { return [] }
        var seen = Set<Int64>()
        var merged: [ThreadSummary] = []
        merged.reserveCapacity(min(preferred.count + fallback.count, boundedCount))

        for thread in preferred + fallback where seen.insert(thread.id).inserted {
            merged.append(thread)
            if merged.count == boundedCount { break }
        }

        return merged
    }
}

enum HomeMediaAction: Equatable {
    case previewImages([ImageContent], index: Int)
    case playVideo(VideoContent)
    case openThread
}

enum HomeMediaActionPolicy {
    static func action(for item: ReaderMediaItem, in mediaItems: [ReaderMediaItem]) -> HomeMediaAction {
        if let video = item.video {
            return .playVideo(video)
        }
        if let image = item.image {
            let images = mediaItems.compactMap(\.image)
            let resolvedImages = images.isEmpty ? [image] : images
            let index = resolvedImages.firstIndex(of: image) ?? 0
            return .previewImages(resolvedImages, index: index)
        }
        return .openThread
    }

    static func action(for item: ReaderMediaItem) -> HomeMediaAction {
        action(for: item, in: [item])
    }
}

enum HomeNavigationRoute: Hashable {
    case thread(ReaderSplitThreadRoute)
    case forum(id: Int64, name: String, displayName: String, avatarURL: URL?)

    static func fromForum(_ forum: Forum) -> HomeNavigationRoute {
        .forum(
            id: forum.id,
            name: forum.name,
            displayName: forum.displayName,
            avatarURL: forum.avatarURL
        )
    }
}

struct HomeSplitDetailBridgeState: Equatable {
    var navigationPath: [HomeNavigationRoute]
    var splitDetail: ReaderSplitThreadRoute?
}

enum HomeSplitDetailBridgePolicy {
    static func state(
        changingTo sizeClass: UserInterfaceSizeClass?,
        navigationPath: [HomeNavigationRoute],
        splitDetail: ReaderSplitThreadRoute?
    ) -> HomeSplitDetailBridgeState {
        switch sizeClass {
        case .compact:
            guard let splitDetail else {
                return HomeSplitDetailBridgeState(
                    navigationPath: navigationPath,
                    splitDetail: nil
                )
            }
            return HomeSplitDetailBridgeState(
                navigationPath: navigationPath + [.thread(splitDetail)],
                splitDetail: nil
            )
        case .regular:
            guard case let .thread(compactDetail)? = navigationPath.last else {
                return HomeSplitDetailBridgeState(
                    navigationPath: navigationPath,
                    splitDetail: splitDetail
                )
            }
            return HomeSplitDetailBridgeState(
                navigationPath: Array(navigationPath.dropLast()),
                splitDetail: compactDetail
            )
        default:
            return HomeSplitDetailBridgeState(
                navigationPath: navigationPath,
                splitDetail: splitDetail
            )
        }
    }
}
