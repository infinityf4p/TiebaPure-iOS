import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let account: Account?
    var refreshToken: Int = 0

    @State private var searchText = ""
    @State private var activeSearch: SearchRoute?
    @State private var threads: [ThreadSummary] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var navigationPath: [HomeNavigationRoute] = []
    @State private var selectedImagePreview: ImagePreviewSession?
    @State private var selectedVideoPreview: HomeVideoPreview?
    @State private var showsInlineRefreshAnimation = false
    @State private var lastScenePhase: ScenePhase = .inactive
    @State private var scrollToTopRequest = 0
    @State private var requestGeneration = 0
    @State private var loadTask: Task<[ThreadSummary], Error>?
    @State private var pendingPaginationRequest = false
    @State private var paginationRequestScheduled = false

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if isLoading && didLoad == false {
                    ReaderStateView.loading("正在加载帖子")
                } else if let errorMessage, threads.isEmpty {
                    refreshableScrollView {
                        ReaderStateView.error(message: errorMessage) {
                            Task { await reload(trigger: .retry) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, TiebaPureTheme.Spacing.lg)
                    }
                } else if threads.isEmpty {
                    refreshableScrollView {
                        ReaderStateView.empty(title: "暂无推荐", message: "下拉即可刷新推荐帖子。")
                            .frame(maxWidth: .infinity)
                            .padding(.top, TiebaPureTheme.Spacing.lg)
                    }
                } else {
                    ScrollViewReader { scrollProxy in
                        refreshableScrollView {
                            LazyVStack(spacing: TiebaPureTheme.Spacing.sm, pinnedViews: []) {
                                Color.clear
                                    .frame(height: 0)
                                    .id(HomeScrollTarget.top)

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
                                        onOpenMedia: { item, mediaItems in
                                            switch HomeMediaActionPolicy.action(for: item, in: mediaItems) {
                                            case let .previewImages(images, index):
                                                selectedImagePreview = ImagePreviewSession(
                                                    images: images,
                                                    initialIndex: index
                                                )
                                            case let .playVideo(video):
                                                selectedVideoPreview = HomeVideoPreview(video: video)
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
                }
            }
            .overlay(alignment: .top) {
                if showsInlineRefreshAnimation {
                    HStack(spacing: TiebaPureTheme.Spacing.xs) {
                        if disablesUITestAnimations {
                            Image(systemName: "arrow.clockwise")
                                .font(.footnote.weight(.semibold))
                                .accessibilityHidden(true)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("正在刷新")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, TiebaPureTheme.Spacing.sm)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, TiebaPureTheme.Spacing.xs)
                    .transition(.opacity)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("home-refresh-animation")
                }
            }
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索帖子或回复")
            .onSubmit(of: .search) {
                submitSearch()
            }
            .navigationDestination(isPresented: searchIsActive) {
                if let activeSearch {
                    SearchResultsView(account: account, scope: .global, initialKeyword: activeSearch.keyword)
                }
            }
            .navigationDestination(for: HomeNavigationRoute.self) { route in
                switch route {
                case let .thread(threadID, forumID):
                    ThreadDetailView(
                        account: account,
                        threadID: threadID,
                        forumID: forumID
                    )
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
                        )
                    )
                }
            }
            .task {
                guard didLoad == false else { return }
                await reload(trigger: .initial)
            }
            .onChange(of: refreshToken) { _ in
                Task { await reload(trigger: .tabTap) }
            }
            .onChange(of: account?.id) { _ in
                loadTask?.cancel()
                requestGeneration += 1
                threads = []
                page = 1
                hasMore = true
                didLoad = false
                isLoading = false
                pendingPaginationRequest = false
                paginationRequestScheduled = false
                errorMessage = nil
                navigationPath = []
                Task { await reload(trigger: .initial) }
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
            .fullScreenCover(item: $selectedImagePreview) { preview in
                FullScreenImageView(session: preview)
            }
            .fullScreenCover(item: $selectedVideoPreview) { preview in
                DirectVideoPlaybackView(video: preview.video)
            }
            .onDisappear {
                loadTask?.cancel()
                requestGeneration += 1
                isLoading = false
                pendingPaginationRequest = false
                paginationRequestScheduled = false
            }
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

    private func submitSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        activeSearch = SearchRoute(keyword: trimmed)
    }

    private func openThread(threadID: Int64, forumID: Int64?) {
        navigationPath.append(.thread(threadID: threadID, forumID: forumID))
    }

    private func refreshableScrollView<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                content()
            }
            .contentShape(Rectangle())
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .refreshable { await reload(trigger: .pullToRefresh) }
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
        isLoading = false
        pendingPaginationRequest = false
        paginationRequestScheduled = false
        let showsInlineAnimation = HomeRefreshAnimationPolicy.shouldAnimate(
            trigger: trigger,
            hasExistingContent: threads.isEmpty == false,
            reduceMotion: reduceMotion
        )
        if showsInlineAnimation && reduceMotion == false {
            if disablesUITestAnimations {
                showsInlineRefreshAnimation = true
            } else {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsInlineRefreshAnimation = true
                }
            }
        }
        let animationStart = DispatchTime.now().uptimeNanoseconds
        page = 1
        hasMore = true
        errorMessage = nil
        if threads.isEmpty {
            didLoad = false
        }
        await loadMore(generation: requestGeneration)
        if showsInlineAnimation && reduceMotion == false {
            let minimumVisibleDuration = HomeRefreshAnimationPolicy.minimumVisibleDurationNanoseconds
            let elapsed = DispatchTime.now().uptimeNanoseconds - animationStart
            let remaining = HomeRefreshAnimationPolicy.remainingVisibleDurationNanoseconds(
                minimum: minimumVisibleDuration,
                elapsed: elapsed
            )
            if remaining > 0 {
                do { try await Task.sleep(nanoseconds: remaining) } catch { return }
            }
            if disablesUITestAnimations {
                showsInlineRefreshAnimation = false
            } else {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsInlineRefreshAnimation = false
                }
            }
        }
    }

    private var disablesUITestAnimations: Bool {
        HomeRefreshAnimationPolicy.disablesUITestAnimations(
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    private func loadMore() async {
        await loadMore(generation: requestGeneration)
    }

    private func loadMore(generation: Int) async {
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
        let requestedAccountID = account?.id
        isLoading = true
        errorMessage = nil

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
                  requestedAccountID == account?.id,
                  Task.isCancelled == false else { return }
            if requestedPage == 1 {
                threads = next
            } else {
                threads = HomeFeedMerge.append(existing: threads, incoming: next)
            }
            hasMore = next.isEmpty == false
            page = requestedPage + 1
        } catch is CancellationError {
            return
        } catch {
            guard generation == requestGeneration, requestedAccountID == account?.id else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration else { return }
        loadTask = nil
        isLoading = false
        didLoad = true
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

        return 250_000_000
    }

    static func disablesUITestAnimations(arguments: [String]) -> Bool {
        #if DEBUG
        return arguments.contains("UITEST_DISABLE_ANIMATIONS")
        #else
        return false
        #endif
    }

    static func showsInlineAnimation(trigger: HomeRefreshTrigger, hasExistingContent: Bool) -> Bool {
        hasExistingContent && (trigger == .tabTap || trigger == .pullToRefresh || trigger == .appOpen)
    }

    static func shouldAnimate(trigger: HomeRefreshTrigger, hasExistingContent: Bool, reduceMotion: Bool) -> Bool {
        reduceMotion == false && showsInlineAnimation(trigger: trigger, hasExistingContent: hasExistingContent)
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
    static func refresh(existing: [ThreadSummary], incoming: [ThreadSummary]) -> [ThreadSummary] {
        merge(preferred: incoming, fallback: existing)
    }

    static func append(existing: [ThreadSummary], incoming: [ThreadSummary]) -> [ThreadSummary] {
        merge(preferred: existing, fallback: incoming)
    }

    private static func merge(preferred: [ThreadSummary], fallback: [ThreadSummary]) -> [ThreadSummary] {
        var seen = Set<Int64>()
        var merged: [ThreadSummary] = []
        merged.reserveCapacity(preferred.count + fallback.count)

        for thread in preferred + fallback where seen.insert(thread.id).inserted {
            merged.append(thread)
        }

        return merged
    }
}

struct HomeVideoPreview: Identifiable {
    let id = UUID()
    let video: VideoContent
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

private enum HomeNavigationRoute: Hashable {
    case thread(threadID: Int64, forumID: Int64?)
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
