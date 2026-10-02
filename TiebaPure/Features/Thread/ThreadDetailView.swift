import SwiftUI
import UIKit

struct ThreadDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var contentSubmissionSettingsStore: ContentSubmissionSettingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readingPreferences) private var readingPreferences
    private let localThreadLibraryStore = LocalThreadLibraryStore.shared
    @ObservedObject private var savedThreadStore = SavedThreadStore.shared
    @ObservedObject private var blocklistStore = BlocklistStore.shared
    let account: Account?
    let threadID: Int64
    let forumID: Int64?
    let initialPostID: UInt64?
    let initialDestination: ThreadDetailInitialDestination?
    private let mainPostFallback: ThreadMainPostFallback?
    private let ownThreadDeletionTarget: OwnThreadDeletionTarget?
    private let onOwnThreadDeleted: ((Int64) -> Void)?
    private let onOwnThreadDeletionNeedsRefresh: (() -> Void)?
    private let openSearchInParent: ((SearchScope) -> Void)?
    private let openUserInParent: ((UserSummary) -> Void)?
    private let openForumInParent: ((Forum) -> Void)?

    @State private var threadPage: ThreadPage?
    @State private var posts: [Post] = []
    @State private var nextPage = 1
    @State private var hasMore = true
    @State private var descendingTotalPage: Int?
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var didRecordBrowsingHistory = false
    @State private var isMainPostBlocked = false
    @State private var errorMessage: String?
    @State private var seeLz = false
    @State private var sortType: ThreadReplySort = .hot
    @State private var didApplyDefaultReplySort = false
    @State private var selectedSubpostPost: Post?
    @State private var selectedUser: UserSummary?
    @State private var selectedForum: Forum?
    @State private var navigationSourceLifecycle = NavigationSourceLifecycleState()
    @State private var userResolutionTask: Task<Void, Never>?
    @State private var userResolutionGeneration = 0
    @State private var userResolutionError: String?
    @State private var isSearchActive = false
    @State private var isStandaloneSearchPresented = false
    @State private var didCopyLink = false
    @State private var pendingInitialPostID: UInt64?
    @State private var pendingInitialDestination: ThreadDetailInitialDestination?
    @State private var initialDestinationScrollRequest = 0
    @State private var isReplyDestinationTargetReady = false
    @State private var requestGeneration = 0
    @State private var loadTask: Task<ThreadPage, Error>?
    @State private var showsInlineRefreshAnimation = false
    @State private var inlineRefreshAnimationToken = 0
    @State private var savedReadingPosition: ThreadReadingPosition?
    @State private var restoredReadingFloor: Int?
    @State private var showsRestoredReadingBanner = false
    @State private var restoredBannerHideTask: Task<Void, Never>?
    @State private var readingTrackingState = ThreadReadingTrackingState()
    @State private var legacyReadingViewportState = ThreadLegacyReadingViewportState()
    @State private var didResolveSavedReadingPosition = false
    @State private var isResumingReadingPosition = false
    @State private var scrollRequest: ThreadPostScrollRequest?
    @State private var preciseScrollSession: ThreadPreciseScrollSession?
    @State private var preciseScrollRetryCount = 0
    @State private var preciseScrollTimeoutTask: Task<Void, Never>?
    @State private var updatingPostLikeIDs = Set<UInt64>()
    @State private var postLikeTasks: [UInt64: Task<Void, Never>] = [:]
    @State private var likeActionError: String?
    @State private var isCollected = false
    @State private var isUpdatingCollection = false
    @State private var accountFavoriteTask: Task<Void, Never>?
    @State private var accountFavoriteGeneration = 0
    @State private var accountFavoriteError: String?
    @State private var composerRoute: ContentComposerRoute?
    @State private var pendingSubmissionReceipt: ContentSubmissionReceipt?
    @State private var pendingSubmissionTarget: ContentSubmissionTarget?
    @State private var pendingSubmissionAccount: Account?
    @State private var pendingSubmissionRouteID: UUID?
    @State private var contentNavigationGeneration = 0
    @State private var contentNavigationTask: Task<Void, Never>?
    @State private var pendingSubpostInitialID: UInt64?
    @State private var linkedRoute: ExternalRoute?
    @State private var contentActionError: String?
    @State private var showsOwnThreadDeleteConfirmation = false
    @State private var isDeletingOwnThread = false
    @State private var hasUnconfirmedOwnThreadDeletion = false
    @State private var ownThreadDeletionNotice: OwnThreadDeletionNotice?
    @State private var isPageVisible = false
    @State private var dismissAfterOwnThreadDeletionWhenVisible = false
    @State private var isSavingLocally = false
    @State private var localSaveTask: Task<Void, Never>?
    @State private var localSaveMessage: String?
    @State private var showsLocalSaveOptions = false

    init(
        account: Account?,
        threadID: Int64,
        forumID: Int64? = nil,
        initialPostID: UInt64? = nil,
        initialDestination: ThreadDetailInitialDestination? = nil,
        ownThreadDeletionTarget: OwnThreadDeletionTarget? = nil,
        mainPostFallback: ThreadMainPostFallback? = nil,
        onOwnThreadDeleted: ((Int64) -> Void)? = nil,
        onOwnThreadDeletionNeedsRefresh: (() -> Void)? = nil,
        openSearchInParent: ((SearchScope) -> Void)? = nil,
        openUserInParent: ((UserSummary) -> Void)? = nil,
        openForumInParent: ((Forum) -> Void)? = nil
    ) {
        self.account = account
        self.threadID = threadID
        self.forumID = forumID
        self.initialPostID = initialPostID
        self.initialDestination = initialDestination
        self.mainPostFallback = mainPostFallback
        self.ownThreadDeletionTarget = ownThreadDeletionTarget
        self.onOwnThreadDeleted = onOwnThreadDeleted
        self.onOwnThreadDeletionNeedsRefresh = onOwnThreadDeletionNeedsRefresh
        self.openSearchInParent = openSearchInParent
        self.openUserInParent = openUserInParent
        self.openForumInParent = openForumInParent
        _pendingInitialPostID = State(initialValue: initialPostID)
        _pendingInitialDestination = State(initialValue: initialDestination)
    }

    var body: some View {
        lifecycleContent
            .fullScreenInteractiveNavigationPop(
                isEnabled: selectedSubpostPost == nil && isDeletingOwnThread == false
            )
            // A tieba.baidu.com link tapped inside a post opens here instead of
            // leaving for Safari or the official client. The cover carries its
            // own stack, so a thread opened from a link can itself open the
            // next link without unwinding the reader underneath.
            .fullScreenCover(item: $linkedRoute) { route in
                ExternalRouteView(account: account, route: route) {
                    linkedRoute = nil
                }
            }
    }

    private var decoratedContent: some View {
        primaryContent
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if threadPage != nil,
                   selectedSubpostPost == nil,
                   contentSubmissionSettingsStore.repliesEnabled {
                    ContentReplyEntryBar(
                        title: "回复帖子",
                        accessibilityIdentifier: "thread-compose-reply-button",
                        action: openThreadReplyComposer
                    )
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
            .navigationTitle(threadNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { navigationToolbar }
    }

    private var navigationContent: some View {
        decoratedContent
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
                        onReturnToSourceThread: { self.selectedUser = nil }
                    )
                    .interactiveNavigationPopStateSync {
                        self.selectedUser = nil
                    }
                }
            }
            .navigationDestination(isPresented: selectedForumIsActive) {
                if let selectedForum {
                    ForumThreadsView(account: account, forum: selectedForum)
                        .interactiveNavigationPopStateSync {
                            self.selectedForum = nil
                    }
                }
            }
            .fullScreenCover(isPresented: $isStandaloneSearchPresented) {
                StandaloneSearchNavigationView(
                    account: account,
                    scope: searchScope,
                    initialKeyword: "",
                    onClose: { isStandaloneSearchPresented = false }
                )
            }
    }

    private var alertContent: some View {
        navigationContent
            .alert("已复制链接", isPresented: $didCopyLink) {
                Button("好", role: .cancel) {}
            }
            .alert("无法收藏", isPresented: accountFavoriteErrorIsPresented) {
            Button("好", role: .cancel) { accountFavoriteError = nil }
        } message: {
            Text(accountFavoriteError ?? "")
        }
            .confirmationDialog(
                savedThreadStore.contains(threadID: threadID) ? "更新本地保存" : "保存到本地",
                isPresented: $showsLocalSaveOptions,
                titleVisibility: .visible
            ) {
                Button("完整媒体") { startLocalSave(mode: .complete) }
                Button("正文和图片") { startLocalSave(mode: .images) }
                Button("仅正文") { startLocalSave(mode: .textOnly) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("完整媒体会下载帖子中的图片、视频和语音；保存过程失败时不会覆盖已有版本。")
            }
            .alert("本地保存", isPresented: Binding(
            get: { localSaveMessage != nil },
            set: { if $0 == false { localSaveMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(localSaveMessage ?? "")
        }
        .alert("提示", isPresented: likeActionErrorIsPresented) {
                Button("好", role: .cancel) { likeActionError = nil }
            } message: {
                Text(likeActionError ?? "")
            }
            .alert("无法打开用户主页", isPresented: userResolutionErrorIsPresented) {
                Button("好", role: .cancel) { userResolutionError = nil }
            } message: {
                Text(userResolutionError ?? "")
            }
            .alert("提示", isPresented: contentActionErrorIsPresented) {
                Button("好", role: .cancel) { contentActionError = nil }
            } message: {
                Text(contentActionError ?? "")
            }
            .confirmationDialog(
                "删除这个帖子？",
                isPresented: $showsOwnThreadDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除帖子", role: .destructive) {
                    Task { await deleteOwnThread() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后通常无法恢复。操作只会提交一次。")
            }
            .alert(item: $ownThreadDeletionNotice) { notice in
                switch notice {
                case let .failure(message):
                    Alert(
                        title: Text("删除失败"),
                        message: Text(message),
                        dismissButton: .default(Text("好"))
                    )
                case .resultPending:
                    Alert(
                        title: Text("结果待确认"),
                        message: Text("删除请求已经发出，但暂时无法确认是否成功。返回后将只刷新帖子列表，不会再次删除。"),
                        primaryButton: .default(Text("返回并刷新")) {
                            dismiss()
                        },
                        secondaryButton: .cancel(Text("留在本页"))
                    )
                }
            }
    }

    private var presentedContent: some View {
        alertContent
            .sheet(item: $composerRoute, onDismiss: handleComposerDismissed) { route in
                if let account {
                    let presentationGeneration = contentNavigationGeneration
                    ContentComposerPresentation(
                        account: account,
                        target: route.target,
                        onDismiss: { composerRoute = nil },
                        onSent: { receipt in
                            guard self.account?.sessionIdentity == account.sessionIdentity,
                                  composerRoute?.id == route.id,
                                  presentationGeneration == contentNavigationGeneration else { return }
                            pendingSubmissionReceipt = receipt
                            pendingSubmissionTarget = route.target
                            pendingSubmissionAccount = account
                            pendingSubmissionRouteID = route.id
                        },
                        onDraftCleanupFailure: {
                            contentActionError = "内容已发送，但本机草稿未能清除。重新打开编辑器前请先重试草稿读取。"
                        }
                    )
                    .environmentObject(environment)
                }
            }
            .sheet(item: $selectedSubpostPost, onDismiss: {
                pendingSubpostInitialID = nil
            }) { post in
                subpostSheetContent(post: post)
            }
    }

    private var lifecycleContent: some View {
        presentedContent
            .task {
                synchronizeOwnThreadDeletionState()
                await initialLoadIfNeeded()
            }
            .onChange(of: account?.sessionIdentity) { _ in resetForAccountChange() }
            .onChange(of: blocklistStore.entries) { _ in applyCurrentBlocklist() }
            .onReceive(environment.ownThreadMutationState.didChange) { event in
                guard event.accountID == account?.id,
                      event.threadID == threadID else { return }
                hasUnconfirmedOwnThreadDeletion = event.outcome == .needsRefresh
            }
            .toolbar(.hidden, for: .tabBar)
            .onAppear(perform: handleAppear)
            .onDisappear(perform: handleDisappear)
    }

    private var threadNavigationTitle: String {
        guard let title = threadPage?.thread.title, title.isEmpty == false else { return "帖子" }
        return title
    }

    @ViewBuilder
    private func subpostSheetContent(post: Post) -> some View {
        if let page = threadPage,
           let resolvedForum = ContentSubmissionForumResolver.resolve(
               page.forum,
               fallbackID: forumID
           ) {
            SubpostListSheet(
                account: account,
                thread: page.thread,
                forum: resolvedForum,
                post: post,
                initialSubpostID: pendingSubpostInitialID,
                threadAuthorID: threadAuthorID,
                onPostLikeChanged: applyChangedPost,
                onInteractiveDismiss: { selectedSubpostPost = nil }
            )
            .environmentObject(environment)
            .subpostInteractivePresentation()
        } else {
            ReaderStateView.error(message: "缺少贴吧 ID，无法加载楼中楼。")
                .padding()
        }
    }

    private func initialLoadIfNeeded() async {
        guard didLoad == false else { return }
        applyDefaultReplySortIfNeeded()
        await reload()
    }

    private func resetForAccountChange() {
        cancelAccountFavoritePresentation()
        cancelContentNavigation()
        localSaveTask?.cancel()
        localSaveTask = nil
        isSavingLocally = false
        loadTask?.cancel()
        requestGeneration += 1
        threadPage = nil
        isCollected = false
        posts = []
        nextPage = 1
        hasMore = true
        descendingTotalPage = nil
        isLoading = false
        didLoad = false
        isMainPostBlocked = false
        errorMessage = nil
        selectedSubpostPost = nil
        composerRoute = nil
        pendingSubmissionReceipt = nil
        pendingSubmissionTarget = nil
        pendingSubmissionAccount = nil
        pendingSubmissionRouteID = nil
        pendingSubpostInitialID = nil
        linkedRoute = nil
        isSearchActive = false
        isStandaloneSearchPresented = false
        selectedUser = nil
        cancelUserResolution()
        userResolutionError = nil
        showsInlineRefreshAnimation = false
        pendingInitialPostID = initialPostID
        pendingInitialDestination = initialDestination
        savedReadingPosition = nil
        didResolveSavedReadingPosition = false
        isResumingReadingPosition = false
        restoredReadingFloor = nil
        hideRestoredReadingBanner()
        cancelPreciseScroll()
        scrollRequest = nil
        readingTrackingState.reset()
        legacyReadingViewportState.reset()
        cancelLikeTasks()
        likeActionError = nil
        contentActionError = nil
        synchronizeOwnThreadDeletionState()
        requestReload()
    }

    private func applyCurrentBlocklist() {
        let currentMainPost = threadPage.flatMap(ThreadPageMainPostPolicy.mainPost(in:))
            ?? posts.first { $0.floor == 1 }
        isMainPostBlocked = currentMainPost.map {
            TiebaContentFilter.shouldKeep(post: $0) == false
        } ?? false
        posts = posts.compactMap { post in
            postApplyingCurrentBlocklist(
                post,
                isMainPost: post.id == currentMainPost?.id || post.floor == 1
            )
        }
        if var currentPage = threadPage {
            currentPage.posts = currentPage.posts.compactMap { post in
                postApplyingCurrentBlocklist(
                    post,
                    isMainPost: post.id == currentMainPost?.id || post.floor == 1
                )
            }
            currentPage.mainPost = currentMainPost.flatMap {
                postApplyingCurrentBlocklist($0, isMainPost: true)
            }
            threadPage = currentPage
        }
        if let target = preciseScrollSession?.postID,
           displayedPostIDs.contains(target) == false {
            cancelPreciseScroll()
        }
    }

    private var displayedPostIDs: Set<UInt64> {
        Set(posts.map(\.id) + [threadPage?.mainPost?.id].compactMap { $0 })
    }

    private func handleDisappear() {
        guard navigationSourceLifecycle.shouldTearDown(
            isPresentingLocalDestination: isSearchActive
                || isStandaloneSearchPresented
                || selectedUser != nil
                || selectedForum != nil
        ) else { return }
        isPageVisible = false
        let readingPositionRequest = readingPersistenceRequest(allowWhileLoading: true)
        readingTrackingState.cancelPendingCommit()
        readingTrackingState.pendingAutomaticPageLoad = false
        if let readingPositionRequest {
            _ = Self.enqueueReadingPositionRequest(
                readingPositionRequest,
                threadID: threadID,
                store: localThreadLibraryStore
            )
        }
        cancelContentNavigation()
        localSaveTask?.cancel()
        localSaveTask = nil
        isSavingLocally = false
        loadTask?.cancel()
        requestGeneration += 1
        isLoading = false
        showsInlineRefreshAnimation = false
        isResumingReadingPosition = false
        hideRestoredReadingBanner()
        scrollRequest = nil
        cancelPreciseScroll()
        cancelLikeTasks()
        cancelUserResolution()
    }

    private func handleAppear() {
        navigationSourceLifecycle.didAppear()
        isPageVisible = true
        completeOwnThreadDeletionNavigationIfPossible()
    }

    @ViewBuilder
    private var primaryContent: some View {
        if isLoading && didLoad == false {
            ReaderStateView.loading(
                isResumingReadingPosition ? "正在恢复上次阅读位置" : "正在加载帖子"
            )
        } else if isMainPostBlocked {
            ReaderStateScrollView(refresh: { await reload() }) {
                ReaderStateView.empty(
                    title: "帖子已被本机屏蔽",
                    message: "主楼命中了当前的用户或关键词屏蔽规则。"
                )
            }
        } else if let errorMessage, posts.isEmpty, mainPost == nil {
            ReaderStateScrollView(refresh: { await reload() }) {
                ReaderStateView.error(message: errorMessage, action: requestReload)
            }
        } else if posts.isEmpty, mainPost == nil {
            ReaderStateScrollView(refresh: { await reload() }) {
                ReaderStateView.empty(
                    title: "暂无内容",
                    message: "下拉即可刷新帖子。",
                    actionTitle: hasMore && didLoad ? "继续加载" : nil,
                    action: hasMore && didLoad ? requestLoadMore : nil
                )
            }
        } else {
            loadedPostContent
        }
    }

    private var loadedPostContent: some View {
        refreshablePostScrollView {
            LazyVStack(spacing: 0) {
                mainPostContent
                replySection
                Color.clear
                    .frame(height: 32)
                    .accessibilityHidden(true)
            }
            .readableWidth()
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
    }

    @ViewBuilder
    private var mainPostContent: some View {
        if let mainPost {
            VStack(spacing: 0) {
                if threadPage?.mainPostIsSummaryFallback == true {
                    Label("主楼完整内容暂不可用，以下为首页摘要。", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, TiebaPureTheme.Spacing.md)
                        .padding(.vertical, TiebaPureTheme.Spacing.sm)
                        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
                        .accessibilityIdentifier("thread-main-summary-fallback-notice")
                }
                PostRowView(
                    post: mainPost,
                    threadTitle: threadPage?.thread.title,
                    threadAuthorID: threadAuthorID,
                    isMainPost: true,
                    onOpenSubposts: openSubpostsIfPossible,
                    onOpenUser: openUser,
                    onOpenTiebaRoute: openTiebaRoute,
                    isLikeUpdating: updatingPostLikeIDs.contains(mainPost.id),
                    onToggleLike: contentSubmissionSettingsStore.likesEnabled && mainPost.id > 0
                        ? { toggleLike(for: mainPost, objectType: .thread) }
                        : nil,
                    onReply: contentSubmissionSettingsStore.repliesEnabled && mainPost.id > 0
                        ? { openReplyComposer(for: mainPost) }
                        : nil
                )
                .equatable()
                .padding(.bottom, TiebaPureTheme.Spacing.xs)
                .threadPreciseScrollAnchor(
                    post: mainPost,
                    isEnabled: preciseScrollSession?.postID == mainPost.id
                )
                .id(mainPost.id)
            }
        }
    }

    private var replySection: some View {
        Section {
            replyRowsContent

            if isLoading, didLoad, nextPage > 1 {
                ProgressView()
                    .padding(TiebaPureTheme.Spacing.md)
                    .accessibilityLabel("正在加载更多回复")
            }

            if let errorMessage {
                InlineLoadErrorView(message: errorMessage, retry: retryInlineLoad)
            } else if hasMore, isLoading == false, didLoad {
                loadMoreRepliesButton
            }
        } header: {
            ReplyControlBar(
                seeLz: seeLz,
                sortType: sortType,
                onSeeLzChange: changeSeeLz,
                onSortChange: changeReplySort
            )
            .id(ThreadDetailScrollTarget.replies)
            .onAppear {
                isReplyDestinationTargetReady = true
                requestInitialDestinationScrollIfReady()
            }
            .onDisappear {
                isReplyDestinationTargetReady = false
            }
        }
    }

    @ViewBuilder
    private var replyRowsContent: some View {
        let visibleReplyPosts = replyPosts
        let visibleReplyCount = visibleReplyPosts.count

        if visibleReplyPosts.isEmpty, isLoading == false {
            ReaderStateView.empty(
                title: "暂无回复",
                message: seeLz ? "这个帖子暂时没有楼主回复。" : "这个帖子暂时没有更多回复。",
                actionTitle: hasMore ? "继续加载" : nil,
                action: hasMore ? requestLoadMore : nil
            )
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemBackground))
        } else {
            ForEach(Array(visibleReplyPosts.enumerated()), id: \.element.id) { index, post in
                PostRowView(
                    post: post,
                    threadAuthorID: threadAuthorID,
                    onOpenSubposts: openSubpostsIfPossible,
                    onOpenUser: openUser,
                    onOpenTiebaRoute: openTiebaRoute,
                    isLikeUpdating: updatingPostLikeIDs.contains(post.id),
                    onToggleLike: contentSubmissionSettingsStore.likesEnabled
                        ? { toggleLike(for: post, objectType: .post) }
                        : nil,
                    onReply: contentSubmissionSettingsStore.repliesEnabled
                        ? { openReplyComposer(for: post) }
                        : nil
                )
                .equatable()
                .threadPreciseScrollAnchor(
                    post: post,
                    isEnabled: preciseScrollSession?.postID == post.id
                )
                .id(post.id)
                .threadReadingVisibility(post: post) { isVisible in
                    readingPostVisibilityChanged(post.id, isVisible: isVisible)
                    if isVisible {
                        prefetchRepliesIfNeeded(
                            index: index,
                            totalCount: visibleReplyCount
                        )
                    }
                }
            }
        }
    }

    private func requestReload() {
        Task { await reload() }
    }

    private func requestLoadMore() {
        Task { await loadMore() }
    }

    private func retryInlineLoad() {
        Task {
            if nextPage <= 1 { await reload() } else { await loadMore() }
        }
    }

    private func prefetchRepliesIfNeeded(index: Int, totalCount: Int) {
        guard didLoad,
              isLoading == false,
              hasMore,
              PaginationPrefetchPolicy.shouldLoadMore(
            currentIndex: index,
            totalCount: totalCount
        ) else { return }
        if readingTrackingState.isScrollIdle {
            requestLoadMore()
        } else {
            readingTrackingState.pendingAutomaticPageLoad = true
        }
    }

    private func changeSeeLz(_ value: Bool) {
        guard seeLz != value else { return }
        seeLz = value
        requestReload()
    }

    private func changeReplySort(_ value: ThreadReplySort) {
        guard sortType != value else { return }
        sortType = value
        requestReload()
    }

    private var selectedUserIsActive: Binding<Bool> {
        Binding(
            get: { selectedUser != nil },
            set: { isActive in
                if isActive == false { selectedUser = nil }
            }
        )
    }

    private var selectedForumIsActive: Binding<Bool> {
        Binding(
            get: { selectedForum != nil },
            set: { isActive in
                if isActive == false { selectedForum = nil }
            }
        )
    }

    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            forumToolbarTitle
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            favoriteToolbarButton
            searchToolbarButton
            moreToolbarMenu
        }
    }

    @ViewBuilder
    private var forumToolbarTitle: some View {
        if let forum = threadPage?.forum {
            Button {
                openForum(forum)
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

    private var favoriteToolbarButton: some View {
        Button(action: toggleCollection) {
            Image(systemName: isCollected ? "star.fill" : "star")
        }
        .disabled(threadPage == nil || isUpdatingCollection || (mainPost?.id ?? 0) == 0)
        .accessibilityLabel(isCollected ? "取消收藏帖子" : "收藏帖子")
        .accessibilityValue(isCollected ? "已收藏" : "未收藏")
        .accessibilityHint(favoriteAccessibilityHint)
        .accessibilityIdentifier("thread-favorite-button")
    }

    private var favoriteAccessibilityHint: String {
        guard account != nil else { return "登录后可以收藏帖子" }
        guard let mainPostID = mainPost?.id, mainPostID > 0 else {
            return "主楼标识暂不可用，无法收藏"
        }
        return isCollected ? "从贴吧账号的收藏中移除" : "收藏到贴吧账号"
    }

    private var searchToolbarButton: some View {
        Button(action: openThreadSearch) {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("搜索本吧")
    }

    private var moreToolbarMenu: some View {
        Menu {
            Button(action: requestMenuRefresh) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            Button {
                showsLocalSaveOptions = true
            } label: {
                Label(
                    savedThreadStore.contains(threadID: threadID) ? "更新本地保存" : "保存到本地",
                    systemImage: "arrow.down.doc"
                )
            }
            .disabled(threadPage == nil || isSavingLocally)
            .accessibilityIdentifier("thread-save-locally")
            Button(action: copyThreadLink) {
                Label("复制链接", systemImage: "doc.on.doc")
            }
            Button(action: openThreadInBrowser) {
                Label("浏览器打开", systemImage: "safari")
            }
            ShareLink(item: threadWebURL) {
                Label("分享", systemImage: "square.and.arrow.up")
            }
            if resolvedOwnThreadDeletionTarget != nil,
               hasPendingOwnThreadDeletion == false {
                Divider()
                Button(role: .destructive) {
                    showsOwnThreadDeleteConfirmation = true
                } label: {
                    Label("删除帖子", systemImage: "trash")
                }
                .disabled(isDeletingOwnThread)
                .accessibilityHint("需要再次确认，删除请求只会提交一次")
                .accessibilityIdentifier("thread-delete-own-thread")
            } else if hasPendingOwnThreadDeletion {
                Divider()
                Label("删除结果待确认", systemImage: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
        } label: {
            if isDeletingOwnThread || isSavingLocally {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "ellipsis")
            }
        }
        .disabled(isDeletingOwnThread)
        .accessibilityLabel(
            isDeletingOwnThread ? "正在删除帖子" : (isSavingLocally ? "正在保存帖子" : "更多")
        )
    }

    private func openThreadSearch() {
        let scope = searchScope
        switch NestedSearchOpenRoutingPolicy.destination(
            hasParentHandler: openSearchInParent != nil,
            systemMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        ) {
        case .parentPath:
            guard let openSearchInParent else { return }
            navigationSourceLifecycle.beginParentNavigation()
            openSearchInParent(scope)
        case .localSearch:
            isSearchActive = true
        case .standaloneSearch:
            isStandaloneSearchPresented = true
        }
    }

    private func requestMenuRefresh() {
        Task { await refreshFromMenuIfIdle() }
    }

    private func copyThreadLink() {
        UIPasteboard.general.string = threadWebURL.absoluteString
        didCopyLink = true
    }

    private func openThreadInBrowser() {
        openURL(threadWebURL)
    }

    private func startLocalSave(mode: SavedThreadMediaMode) {
        guard isSavingLocally == false, threadPage != nil else { return }
        localSaveTask?.cancel()
        isSavingLocally = true
        let capture = SavedThreadCaptureService(api: environment.api)
        localSaveTask = Task { @MainActor in
            defer {
                isSavingLocally = false
                localSaveTask = nil
            }
            do {
                var snapshot = try await capture.capture(
                    account: account,
                    threadID: threadID,
                    forumID: forumID
                )
                try Task.checkCancellation()
                let preparedMedia = try await savedThreadStore.mediaStore.prepareCapture(
                    snapshot: snapshot,
                    mode: mode
                )
                defer { preparedMedia.rollback() }
                try Task.checkCancellation()
                snapshot.mediaMode = mode
                snapshot.mediaAssets = preparedMedia.assets
                snapshot.latestCheckedAt = nil
                snapshot.latestReplyCount = nil
                try await savedThreadStore.saveWithoutBlocking(
                    snapshot,
                    preparedMedia: preparedMedia
                )
                let mediaBytes = Dictionary(grouping: preparedMedia.assets, by: \.fileName)
                    .values
                    .compactMap(\.first)
                    .reduce(0) { $0 + $1.byteCount }
                let mediaDescription = mode == .textOnly
                    ? "媒体仍需联网加载"
                    : "已离线保存\(preparedMedia.assets.count)项媒体（\(ByteCountFormatter.string(fromByteCount: Int64(mediaBytes), countStyle: .file))）"
                localSaveMessage = "已保存主楼、\(snapshot.replyCount)层回复和\(snapshot.subpostCount)条楼中楼；\(mediaDescription)。"
            } catch is CancellationError {
                return
            } catch {
                localSaveMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func deleteOwnThread() async {
        guard OwnThreadDeletionDispatchPolicy.canSubmit(
            hasValidatedTarget: resolvedOwnThreadDeletionTarget != nil,
            isSubmitting: isDeletingOwnThread,
            hasUnconfirmedOutcome: hasPendingOwnThreadDeletion
        ),
              let account,
              let target = resolvedOwnThreadDeletionTarget,
              target.threadID == threadID else { return }
        isDeletingOwnThread = true
        ownThreadDeletionNotice = nil
        let submittedAccountID = account.id
        let submittedSession = account.sessionIdentity

        do {
            try await environment.contentSubmissionCoordinator.performAccountWrite(
                account: account,
                target: .deleteThread(threadID),
                coalescesConcurrentCalls: true
            ) {
                try await environment.api.deleteOwnThread(account: account, target: target)
            }
            try Task.checkCancellation()
            isDeletingOwnThread = false
            guard self.account?.sessionIdentity == submittedSession else { return }
            environment.ownThreadMutationState.publish(
                accountID: submittedAccountID,
                threadID: threadID,
                outcome: .deleted
            )
            onOwnThreadDeleted?(threadID)
            await Task.yield()
            dismissAfterOwnThreadDeletionWhenVisible = true
            completeOwnThreadDeletionNavigationIfPossible()
        } catch is CancellationError {
            isDeletingOwnThread = false
        } catch {
            isDeletingOwnThread = false
            guard self.account?.sessionIdentity == submittedSession else { return }
            switch UserProfileMutationPresentationPolicy.failure(for: error) {
            case .resultPending:
                // A read-only list refresh is the only safe follow-up after a
                // dispatched write loses its response. Never resend here.
                hasUnconfirmedOwnThreadDeletion = true
                environment.ownThreadMutationState.publish(
                    accountID: submittedAccountID,
                    threadID: threadID,
                    outcome: .needsRefresh
                )
                onOwnThreadDeletionNeedsRefresh?()
                ownThreadDeletionNotice = .resultPending
            case let .retryable(message):
                ownThreadDeletionNotice = .failure(message: message)
            }
        }
    }

    private func completeOwnThreadDeletionNavigationIfPossible() {
        guard dismissAfterOwnThreadDeletionWhenVisible,
              OwnThreadDeletionNavigationPolicy.shouldDismissAfterCompletion(
                isPageVisible: isPageVisible
              ) else { return }
        dismissAfterOwnThreadDeletionWhenVisible = false
        dismiss()
    }

    private var loadMoreRepliesButton: some View {
        Button(action: requestMoreReplies) {
            Text("加载更多回复")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .minTouchTarget()
        .padding(.vertical, TiebaPureTheme.Spacing.xs)
        .accessibilityIdentifier("thread-replies-load-more")
    }

    private func requestMoreReplies() {
        Task { await loadMore() }
    }

    private var accountFavoriteErrorIsPresented: Binding<Bool> {
        Binding(
            get: { accountFavoriteError != nil },
            set: { isPresented in
                if isPresented == false { accountFavoriteError = nil }
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

    private var contentActionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { contentActionError != nil },
            set: { isPresented in
                if isPresented == false { contentActionError = nil }
            }
        )
    }

    private func openThreadReplyComposer() {
        guard contentSubmissionSettingsStore.repliesEnabled else {
            contentActionError = "请先在设置中开启“允许回帖”。"
            return
        }
        guard account != nil else {
            contentActionError = "登录后才能回复帖子。"
            return
        }
        guard let page = threadPage else {
            contentActionError = "帖子信息尚未加载完成。"
            return
        }
        guard let resolvedForum = resolvedForum(for: page) else {
            contentActionError = "贴吧信息尚未加载完成。"
            return
        }
        cancelContentNavigation()
        composerRoute = ContentComposerRoute(
            target: .threadReply(thread: page.thread, forum: resolvedForum)
        )
    }

    private func openReplyComposer(for post: Post) {
        guard contentSubmissionSettingsStore.repliesEnabled else {
            contentActionError = "请先在设置中开启“允许回帖”。"
            return
        }
        guard account != nil else {
            contentActionError = "登录后才能回复楼层。"
            return
        }
        guard let page = threadPage else {
            contentActionError = "帖子信息尚未加载完成。"
            return
        }
        guard let resolvedForum = resolvedForum(for: page) else {
            contentActionError = "贴吧信息尚未加载完成。"
            return
        }
        cancelContentNavigation()
        composerRoute = ContentComposerRoute(
            target: .postReply(thread: page.thread, forum: resolvedForum, post: post)
        )
    }

    private func handleComposerDismissed() {
        guard let receipt = pendingSubmissionReceipt,
              let target = pendingSubmissionTarget,
              let submittedAccount = pendingSubmissionAccount,
              pendingSubmissionRouteID != nil else { return }
        pendingSubmissionReceipt = nil
        pendingSubmissionTarget = nil
        pendingSubmissionAccount = nil
        pendingSubmissionRouteID = nil
        guard account?.sessionIdentity == submittedAccount.sessionIdentity else { return }
        handleSentContent(
            receipt,
            target: target,
            account: submittedAccount
        )
    }

    private func handleSentContent(
        _ receipt: ContentSubmissionReceipt,
        target: ContentSubmissionTarget,
        account submittedAccount: Account
    ) {
        contentNavigationTask?.cancel()
        contentNavigationGeneration += 1
        let generation = contentNavigationGeneration
        contentNavigationTask = Task { @MainActor in
            guard target.threadID == threadID,
                  account?.sessionIdentity == submittedAccount.sessionIdentity,
                  composerRoute == nil else { return }
            seeLz = false
            switch target.kind {
            case .threadReply:
                if let postID = receipt.postID, postID > 0 {
                    sortType = .ascending
                    pendingInitialPostID = postID
                } else {
                    sortType = .descending
                }
                await reload()
                guard contentNavigationIsCurrent(generation, account: submittedAccount) else { return }
            case .postReply:
                guard let parentPostID = target.parentPostID else {
                    await reload()
                    return
                }
                sortType = .ascending
                pendingInitialPostID = parentPostID
                await reload()
                guard contentNavigationIsCurrent(generation, account: submittedAccount) else { return }
                if let parent = posts.first(where: { $0.id == parentPostID })
                    ?? threadPage?.mainPost.flatMap({ $0.id == parentPostID ? $0 : nil }) {
                    pendingSubpostInitialID = receipt.postID.flatMap { $0 > 0 ? $0 : nil }
                    selectedSubpostPost = parent
                }
            case .newThread, .subpostReply:
                await reload()
                guard contentNavigationIsCurrent(generation, account: submittedAccount) else { return }
            }
            contentNavigationTask = nil
        }
    }

    private func contentNavigationIsCurrent(_ generation: Int, account submittedAccount: Account) -> Bool {
        Task.isCancelled == false
            && generation == contentNavigationGeneration
            && account?.sessionIdentity == submittedAccount.sessionIdentity
    }

    private func cancelContentNavigation() {
        contentNavigationTask?.cancel()
        contentNavigationTask = nil
        contentNavigationGeneration += 1
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
            navigationSourceLifecycle.beginParentNavigation()
            openUserInParent(user)
        } else {
            selectedUser = user
        }
    }

    private func openForum(_ forum: Forum) {
        if let openForumInParent {
            navigationSourceLifecycle.beginParentNavigation()
            openForumInParent(forum)
        } else {
            selectedForum = forum
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
            .scrollFrameProbeForUITests()
            .shortPullRefresh(
                isEnabled: didLoad && isLoading == false,
                surface: .grouped,
                accessibilityIdentifier: "thread-refresh-animation"
            ) {
                guard isLoading == false else { return }
                await reload()
            }
            .coordinateSpace(name: ThreadDetailScrollCoordinateSpace.name)
            .onPreferenceChange(ThreadPostViewportPreferenceKey.self) { entries in
                correctPendingPreciseScroll(entries: entries, proxy: scrollProxy)
                if #unavailable(iOS 18.0) {
                    legacyReadingViewportState.entries = entries
                    updateLegacyReadingVisibility()
                }
            }
            .modifier(
                ThreadDetailScrollTelemetryModifier(
                    onActivityChange: handleReadingScrollActivity,
                    onRegionChange: handleReadingScrollRegionChange,
                    onLegacySnapshot: handleLegacyScrollTelemetry
                )
            )
            .onChange(of: scrollRequest) { request in
                guard let request else { return }
                performScrollRequest(request, proxy: scrollProxy)
            }
            .onChange(of: initialDestinationScrollRequest) { _ in
                performInitialDestinationScroll(proxy: scrollProxy)
            }
            .onAppear {
                requestInitialDestinationScrollIfReady()
                // The auto-restore request is issued while the loading state
                // is still on screen, so this scroll view first materializes
                // with the request already set — onChange never observes that
                // transition and the pending request must be replayed here.
                guard let request = scrollRequest else { return }
                performInitialScrollRequest(request, proxy: scrollProxy)
            }
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

    private var resolvedOwnThreadDeletionTarget: OwnThreadDeletionTarget? {
        UserProfileManagementPolicy.threadDetailDeletionTarget(
            account: account,
            threadID: threadID,
            page: threadPage,
            explicitTarget: ownThreadDeletionTarget
        )
    }

    private var hasPendingOwnThreadDeletion: Bool {
        guard let account else { return false }
        return hasUnconfirmedOwnThreadDeletion
            || environment.ownThreadMutationState.hasUnconfirmedDeletion(
                accountID: account.id,
                threadID: threadID
            )
    }

    private func synchronizeOwnThreadDeletionState() {
        guard let account else {
            hasUnconfirmedOwnThreadDeletion = false
            return
        }
        hasUnconfirmedOwnThreadDeletion = environment.ownThreadMutationState
            .hasUnconfirmedDeletion(accountID: account.id, threadID: threadID)
    }

    private var replyPosts: [Post] {
        guard let mainPost else { return posts }
        return posts.filter { $0.id != mainPost.id }
    }

    private var threadAuthorID: Int64? {
        threadPage?.thread.author.id
    }

    private var resolvedForumID: Int64? {
        if let id = threadPage?.forum.id, id > 0 {
            return id
        }
        guard let forumID, forumID > 0 else { return nil }
        return forumID
    }

    private func resolvedForum(for page: ThreadPage) -> Forum? {
        ContentSubmissionForumResolver.resolve(page.forum, fallbackID: forumID)
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

    private func toggleCollection() {
        guard threadPage != nil, isUpdatingCollection == false else { return }
        // The collection lives on the account, like following a forum.
        guard let account else {
            accountFavoriteError = "登录后才能收藏帖子。"
            return
        }
        let willBeCollected = isCollected == false
        // The star flips right away and goes back only if the service refuses,
        // so the tap stays responsive without inventing a second local list.
        isCollected = willBeCollected
        isUpdatingCollection = true
        accountFavoriteGeneration &+= 1
        let generation = accountFavoriteGeneration
        let submittedSession = account.sessionIdentity
        let submittedPostID = markedPostIDForAccountFavorite
        let api = environment.api
        let coordinator = environment.contentSubmissionCoordinator
        accountFavoriteTask = Task {
            do {
                try await coordinator.performAccountWrite(
                    account: account,
                    target: .threadFavorite(threadID)
                ) {
                    try await api.setAccountThreadFavorite(
                        account: account,
                        threadID: threadID,
                        postID: submittedPostID,
                        favorited: willBeCollected
                    )
                }
                try Task.checkCancellation()
            } catch is CancellationError {
                // Session replacement owns the rollback by resetting the page.
            } catch {
                guard generation == accountFavoriteGeneration,
                      self.account?.sessionIdentity == submittedSession else { return }
                isCollected = willBeCollected == false
                accountFavoriteError = ReaderErrorMessage.message(for: error)
            }
            guard generation == accountFavoriteGeneration,
                  self.account?.sessionIdentity == submittedSession else { return }
            isUpdatingCollection = false
            accountFavoriteTask = nil
        }
    }

    private func cancelAccountFavoritePresentation() {
        accountFavoriteGeneration &+= 1
        accountFavoriteTask?.cancel()
        accountFavoriteTask = nil
        isUpdatingCollection = false
    }

    /// The floor the collection points at: where the reader actually is, or the
    /// first post when they have not moved.
    private var markedPostIDForAccountFavorite: UInt64 {
        localThreadLibraryStore.position(for: threadID)?.postID
            ?? mainPost?.id
            ?? 0
    }

    /// Restores the saved reading position automatically on the first load of
    /// any entry point. The first page request targets the saved post ID, so
    /// the server locates its page and the list opens there without a second
    /// load or a manual action.
    private func resolveAutoRestoreIfNeeded() {
        guard didResolveSavedReadingPosition == false else { return }
        didResolveSavedReadingPosition = true
        guard initialPostID == nil,
              initialDestination == nil,
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

    private func applyDefaultReplySortIfNeeded() {
        guard didApplyDefaultReplySort == false else { return }
        didApplyDefaultReplySort = true
        sortType = ThreadInitialReplySortPolicy.resolve(
            defaultReplySort: readingPreferences.defaultReplySort,
            initialPostID: initialPostID
        )
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
        // Reaching the top clears the stored position through the scroll-region
        // handler, so the next open starts from the beginning.
        requestScroll(to: mainPost.id)
    }

    private func requestScroll(to postID: UInt64) {
        guard postID > 0 else { return }
        scrollRequest = ThreadPostScrollRequest(id: UUID(), postID: postID)
    }

    private func requestInitialDestinationScrollIfReady() {
        guard pendingInitialDestination == .replies,
              isReplyDestinationTargetReady else { return }
        initialDestinationScrollRequest &+= 1
    }

    private func performInitialDestinationScroll(proxy: ScrollViewProxy) {
        guard pendingInitialDestination == .replies,
              isReplyDestinationTargetReady else { return }
        pendingInitialDestination = nil
        proxy.scrollTo(ThreadDetailScrollTarget.replies, anchor: .top)
    }

    private func performScrollRequest(
        _ request: ThreadPostScrollRequest,
        proxy: ScrollViewProxy
    ) {
        cancelPreciseScroll()
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
        cancelPreciseScroll()
        let session = ThreadPreciseScrollSession(postID: request.postID)
        preciseScrollSession = session
        preciseScrollRetryCount = 0
        if scrollRequest?.id == request.id {
            scrollRequest = nil
        }
        preciseScrollTimeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(1_500))
            } catch {
                return
            }
            guard preciseScrollSession == session else { return }
            cancelPreciseScroll()
        }
        DispatchQueue.main.async {
            guard preciseScrollSession == session else { return }
            proxy.scrollTo(session.postID, anchor: .top)
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
        guard let session = preciseScrollSession else { return }
        let target = session.postID
        guard preciseScrollRetryCount < 12 else {
            cancelPreciseScroll()
            return
        }
        guard let entry = entries[target], entry.minY.isFinite else { return }
        // Being aligned once is not terminal: content above the target can
        // still settle and move it again. Keep the single target anchor alive
        // until the independent timeout or a direct user interaction ends it.
        guard abs(entry.minY) > 4 else { return }
        preciseScrollRetryCount += 1
        DispatchQueue.main.async {
            guard preciseScrollSession == session else { return }
            proxy.scrollTo(target, anchor: .top)
        }
    }

    private func cancelPreciseScroll() {
        preciseScrollTimeoutTask?.cancel()
        preciseScrollTimeoutTask = nil
        preciseScrollSession = nil
        preciseScrollRetryCount = 0
    }

    private func readingPostVisibilityChanged(_ postID: UInt64, isVisible: Bool) {
        let didChange = isVisible
            ? readingTrackingState.postBecameVisible(postID)
            : readingTrackingState.postBecameHidden(postID)
        guard didChange else { return }
        if readingTrackingState.isScrollIdle,
           readingTrackingState.didMoveAwayFromTop {
            scheduleReadingPositionCommit()
        }
    }

    private func handleReadingScrollActivity(
        isDirectInteraction: Bool,
        isIdle: Bool
    ) {
        if isDirectInteraction {
            cancelPreciseScroll()
        }
        readingTrackingState.isScrollIdle = isIdle
        if isIdle {
            requestPendingAutomaticPageLoadIfPossible()
            scheduleReadingPositionCommit()
        } else {
            readingTrackingState.cancelPendingCommit()
        }
    }

    private func handleLegacyScrollTelemetry(_ snapshot: LegacyScrollTelemetrySnapshot) {
        let isDirectInteraction = snapshot.phase == .direct
        let isIdle = snapshot.phase == .idle
        if isDirectInteraction {
            cancelPreciseScroll()
        }
        readingTrackingState.isScrollIdle = isIdle
        if isIdle == false {
            readingTrackingState.cancelPendingCommit()
        }
        legacyReadingViewportState.viewportSize = snapshot.viewportSize
        updateLegacyReadingVisibility()
        handleReadingScrollRegionChange(
            ThreadReadingScrollRegion.resolve(
                distanceFromTop: snapshot.distanceFromTop
            )
        )
        if isIdle {
            requestPendingAutomaticPageLoadIfPossible()
            scheduleReadingPositionCommit()
        }
    }

    private func updateLegacyReadingVisibility() {
        guard legacyReadingViewportState.viewportSize.width > 0,
              legacyReadingViewportState.viewportSize.height > 0 else { return }
        let eligiblePostIDs = Set(replyPosts.map(\.id))
        let visiblePostIDs = ThreadReadingViewportPolicy.visiblePostIDs(
            entries: legacyReadingViewportState.entries,
            viewportSize: legacyReadingViewportState.viewportSize,
            eligiblePostIDs: eligiblePostIDs
        )
        let didChange = readingTrackingState.replaceVisiblePostIDs(visiblePostIDs)
        if didChange,
           readingTrackingState.isScrollIdle,
           readingTrackingState.didMoveAwayFromTop {
            scheduleReadingPositionCommit()
        }

        guard let lastVisibleIndex = replyPosts.lastIndex(where: {
            visiblePostIDs.contains($0.id)
        }) else { return }
        prefetchRepliesIfNeeded(index: lastVisibleIndex, totalCount: replyPosts.count)
    }

    private func requestPendingAutomaticPageLoadIfPossible() {
        let canLoad = didLoad &&
            readingTrackingState.isScrollIdle &&
            isLoading == false &&
            hasMore
        guard readingTrackingState.consumePendingAutomaticPageLoad(canLoad: canLoad) else {
            return
        }
        requestLoadMore()
    }

    private func scheduleReadingPositionCommit() {
        readingTrackingState.pendingCommitTask?.cancel()
        let commitID = UUID()
        readingTrackingState.pendingCommitID = commitID
        readingTrackingState.pendingCommitTask = Task { @MainActor in
            defer {
                if readingTrackingState.pendingCommitID == commitID {
                    readingTrackingState.pendingCommitTask = nil
                    readingTrackingState.pendingCommitID = nil
                }
            }
            do {
                try await Task.sleep(for: ThreadReadingPersistencePolicy.idleDelay)
            } catch {
                return
            }
            guard readingTrackingState.isScrollIdle else { return }
            await commitReadingStateIfNeeded()
        }
    }

    private func commitReadingStateIfNeeded(allowWhileLoading: Bool = false) async {
        guard let request = readingPersistenceRequest(
            allowWhileLoading: allowWhileLoading
        ) else { return }
        let persistenceTask = Self.enqueueReadingPositionRequest(
            request,
            threadID: threadID,
            store: localThreadLibraryStore
        )
        let didPersist = await persistenceTask.value
        guard didPersist, Task.isCancelled == false else { return }

        switch request {
        case .clear:
            savedReadingPosition = nil
            readingTrackingState.lastRecordedPostID = nil
            readingTrackingState.didMoveAwayFromTop = false
        case let .record(postID, _):
            readingTrackingState.lastRecordedPostID = postID
        }
    }

    private func readingPersistenceRequest(
        allowWhileLoading: Bool = false
    ) -> ThreadReadingPositionRequest? {
        switch ThreadReadingPersistencePolicy.intent(
            scrollRegion: readingTrackingState.scrollRegion,
            didMoveAwayFromTop: readingTrackingState.didMoveAwayFromTop
        ) {
        case .clear:
            return .clear
        case .record:
            return visibleReadingPositionRequest(allowWhileLoading: allowWhileLoading)
        case .none:
            return nil
        }
    }

    private func visibleReadingPositionRequest(
        allowWhileLoading: Bool = false
    ) -> ThreadReadingPositionRequest? {
        guard didLoad,
              allowWhileLoading || isLoading == false,
              readingTrackingState.scrollRegion == .away,
              readingTrackingState.didMoveAwayFromTop else { return nil }
        guard let postID = ThreadReadingVisibilityPolicy.bottomMostVisiblePostID(
            postIDsInDisplayOrder: posts.map(\.id),
            visiblePostIDs: readingTrackingState.visiblePostIDs,
            excludedPostID: mainPost?.id
        ),
              postID != readingTrackingState.lastRecordedPostID,
              let post = posts.first(where: { $0.id == postID }) else { return nil }
        return .record(postID: post.id, floor: post.floor)
    }

    @MainActor
    private static func enqueueReadingPositionRequest(
        _ request: ThreadReadingPositionRequest,
        threadID: Int64,
        store: LocalThreadLibraryStore
    ) -> Task<Bool, Never> {
        switch request {
        case .clear:
            return store.enqueueClearReadingPosition(threadID: threadID)
        case let .record(postID, floor):
            return store.enqueueReadingPosition(
                threadID: threadID,
                postID: postID,
                floor: floor
            )
        }
    }

    private func handleReadingScrollRegionChange(_ region: ThreadReadingScrollRegion) {
        readingTrackingState.scrollRegion = region
        if region == .away {
            readingTrackingState.didMoveAwayFromTop = true
            return
        }
        if region == .top, readingTrackingState.isScrollIdle {
            scheduleReadingPositionCommit()
        }
    }

    private func reload() async {
        loadTask?.cancel()
        // Stop the pending write before changing the request key. Keep the
        // current container snapshot: if a page-1 refresh returns the same
        // IDs, SwiftUI is not required to publish visibility again.
        readingTrackingState.cancelPendingCommit()
        readingTrackingState.pendingAutomaticPageLoad = false
        requestGeneration += 1
        isLoading = false
        nextPage = 1
        hasMore = true
        // Refreshes and filter changes can alter the server's page count.
        // Descending order must rediscover the latest page for each page-1 load.
        descendingTotalPage = nil
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
        let requestedAccount = account
        let requestedSession = requestedAccount?.sessionIdentity
        let requestedSeeLz = seeLz
        let requestedSort = sortType
        isLoading = true
        errorMessage = nil
        var continuation: LocallyFilteredPaginationDecision?
        var didCompletePage = false

        do {
            let requestedPage = nextPage
            let requestedPostID = requestedPage == 1 ? pendingInitialPostID : nil
            if requestedPage == 1, let requestedAccount {
                await environment.contentSubmissionCoordinator.waitForThreadFavoriteWrite(
                    account: requestedAccount,
                    threadID: threadID
                )
                guard Task.isCancelled == false,
                      generation == requestGeneration,
                      requestedSession == account?.sessionIdentity,
                      requestedSeeLz == seeLz,
                      requestedSort == sortType else { return }
            }
            let previousMainPost = mainPost
            let previousMainPostIsSummaryFallback = threadPage?.mainPostIsSummaryFallback ?? false
            var loaded: ThreadPage
            if requestedSort == .descending {
                var discoveryPage: ThreadPage?
                let totalPage: Int
                if requestedPage > 1, let descendingTotalPage {
                    totalPage = descendingTotalPage
                } else {
                    let discoveryTask = Task { try await environment.api.threadPage(
                        account: requestedAccount,
                        threadID: threadID,
                        page: 1,
                        forumID: forumID,
                        postID: nil,
                        seeLz: requestedSeeLz,
                        sortType: .ascending
                    ) }
                    loadTask = discoveryTask
                    let page = try await discoveryTask.value
                    guard generation == requestGeneration,
                          requestedSession == account?.sessionIdentity,
                          requestedSeeLz == seeLz,
                          requestedSort == sortType else { return }
                    discoveryPage = page
                    totalPage = max(page.totalPage, 1)
                    descendingTotalPage = totalPage
                }

                let serverPage = ThreadDescendingPaginationPolicy.serverPage(
                    logicalPage: requestedPage,
                    totalPage: totalPage
                )
                if serverPage == 1, let discoveryPage {
                    loaded = discoveryPage
                } else {
                    let pageTask = Task { try await environment.api.threadPage(
                        account: requestedAccount,
                        threadID: threadID,
                        page: serverPage,
                        forumID: forumID,
                        postID: nil,
                        seeLz: requestedSeeLz,
                        sortType: .ascending
                    ) }
                    loadTask = pageTask
                    loaded = try await pageTask.value
                }
                if loaded.mainPost == nil,
                   let discoveryMainPost = discoveryPage.flatMap(
                    ThreadPageMainPostPolicy.mainPost(in:)
                   ) {
                    loaded.mainPost = discoveryMainPost
                }
                loaded = ThreadDescendingPaginationPolicy.normalized(
                    loaded,
                    logicalPage: requestedPage
                )
            } else {
                let task = Task { try await environment.api.threadPage(
                    account: requestedAccount,
                    threadID: threadID,
                    page: requestedPage,
                    forumID: forumID,
                    postID: requestedPostID,
                    seeLz: requestedSeeLz,
                    sortType: requestedSort
                ) }
                loadTask = task
                loaded = try await task.value
            }
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity,
                  requestedSeeLz == seeLz,
                  requestedSort == sortType else { return }
            let availableMainPostFallback = mainPostFallback
                ?? ThreadMainPostFallback(thread: loaded.thread)

            if ThreadPageMainPostPolicy.needsFirstPageRecovery(
                loaded,
                requestedPage: requestedPage
            ) {
                do {
                    let recoveryTask = Task { try await environment.api.threadPage(
                        account: requestedAccount,
                        threadID: threadID,
                        page: 1,
                        forumID: forumID,
                        postID: nil,
                        seeLz: false,
                        sortType: .ascending
                    ) }
                    loadTask = recoveryTask
                    let recoveryPage = try await recoveryTask.value
                    guard generation == requestGeneration,
                          requestedSession == account?.sessionIdentity,
                          requestedSeeLz == seeLz,
                          requestedSort == sortType else { return }
                    if let recoveredMainPost = ThreadPageMainPostPolicy.mainPost(in: recoveryPage) {
                        loaded.mainPost = recoveredMainPost
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // The first request already loaded a valid thread and its
                    // replies. If Home supplied a summary, a failed enrichment
                    // request must not discard that deterministic fallback.
                    guard availableMainPostFallback != nil else { throw error }
                }
            }

            var mergedPage = ThreadPageMainPostPolicy.merging(
                loaded,
                previousMainPost: previousMainPost,
                previousMainPostIsSummaryFallback: previousMainPostIsSummaryFallback,
                requestedPage: requestedPage
            )
            if requestedPage == 1 {
                mergedPage = ThreadPageMainPostPolicy.applyingFallback(
                    availableMainPostFallback,
                    to: mergedPage,
                    threadID: threadID
                )
            }
            if ThreadPageMainPostPolicy.needsFirstPageRecovery(
                mergedPage,
                requestedPage: requestedPage
            ) {
                throw TiebaAPIError.missingMainPost
            }
            let mergedMainPost = ThreadPageMainPostPolicy.mainPost(in: mergedPage)
            isMainPostBlocked = mergedMainPost.map {
                TiebaContentFilter.shouldKeep(post: $0) == false
            } ?? false
            var visiblePage = mergedPage
            visiblePage.posts = mergedPage.posts.compactMap { post in
                postApplyingCurrentBlocklist(
                    post,
                    isMainPost: post.id == mergedMainPost?.id || post.floor == 1
                )
            }
            visiblePage.mainPost = mergedMainPost.flatMap {
                postApplyingCurrentBlocklist($0, isMainPost: true)
            }
            threadPage = visiblePage
            if requestedPage == 1 {
                posts = visiblePage.posts
                pendingInitialPostID = nil
                // The thread page reports whether this account collected the
                // thread; a tap in flight is newer than what it says.
                if isUpdatingCollection == false {
                    isCollected = loaded.isCollected
                }
                if didRecordBrowsingHistory == false {
                    let didPersistHistory = await BrowsingHistoryStore.shared.recordInBackground(
                        thread: loaded.thread,
                        forum: loaded.forum,
                        fallbackForumID: forumID
                    )
                    guard generation == requestGeneration,
                          requestedSession == account?.sessionIdentity,
                          requestedSeeLz == seeLz,
                          requestedSort == sortType else { return }
                    didRecordBrowsingHistory = didPersistHistory
                }
                if let requestedPostID {
                    let loadedPostIDs = Set(
                        visiblePage.posts.map(\.id)
                            + [visiblePage.mainPost?.id].compactMap { $0 }
                    )
                    var didResolveRequestedPost = true
                    if loadedPostIDs.contains(requestedPostID) {
                        requestScroll(to: requestedPostID)
                        if isResumingReadingPosition {
                            showRestoredReadingBanner()
                        }
                    } else if isResumingReadingPosition {
                        // The saved post no longer exists; fall back to the
                        // first page and forget the stale position.
                        didResolveRequestedPost = await localThreadLibraryStore
                            .clearReadingPositionInBackground(
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
            didCompletePage = true
        } catch is CancellationError {
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity else { return }
            loadTask = nil
            isLoading = false
            isResumingReadingPosition = false
            return
        } catch {
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity,
                  requestedSeeLz == seeLz,
                  requestedSort == sortType else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
            isResumingReadingPosition = false
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
        } else if didCompletePage {
            requestPendingAutomaticPageLoadIfPossible()
        }
    }

    private func openSubpostsIfPossible(_ post: Post) {
        guard post.subpostCount > 0 else { return }
        selectedSubpostPost = post
    }

    private func openTiebaRoute(_ route: ExternalRoute) {
        linkedRoute = route
    }

    private func toggleLike(for post: Post, objectType: TiebaLikeObjectType) {
        guard contentSubmissionSettingsStore.likesEnabled else { return }
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
                try await environment.socialMutationCoordinator.setPostLiked(
                    account: account,
                    threadID: threadID,
                    postID: post.id,
                    objectType: objectType,
                    liked: targetState
                )
                try Task.checkCancellation()
                applyPostLikeState(postID: post.id, liked: targetState)
            } catch is CancellationError {
                // The coordinator keeps an already-started write alive; this
                // page only stops applying the result to stale view state.
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

    private func postApplyingCurrentBlocklist(
        _ candidate: Post,
        isMainPost: Bool = false
    ) -> Post? {
        guard TiebaContentFilter.shouldKeep(
            post: candidate,
            asOpenedThreadMainPost: isMainPost
        ) else { return nil }
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

private enum OwnThreadDeletionNotice: Identifiable {
    case failure(message: String)
    case resultPending

    var id: String {
        switch self {
        case .failure:
            return "failure"
        case .resultPending:
            return "result-pending"
        }
    }
}

private enum ThreadDetailScrollCoordinateSpace {
    static let name = "thread-detail-refresh-scroll"
}

enum ThreadReadingScrollRegion: Equatable, Sendable {
    case top
    case nearTop
    case away

    static func resolve(distanceFromTop: CGFloat) -> Self {
        if ShortPullRefreshPolicy.isAtTop(distanceFromTop: distanceFromTop) {
            return .top
        }
        if distanceFromTop >= ThreadReadingViewportPolicy.minimumRecordingDistance {
            return .away
        }
        return .nearTop
    }
}

enum ThreadReadingPersistenceIntent: Equatable, Sendable {
    case none
    case record
    case clear
}

enum ThreadReadingPositionRequest: Equatable, Sendable {
    case clear
    case record(postID: UInt64, floor: Int)
}

enum ThreadReadingPersistencePolicy {
    // A short quiet period keeps SwiftData work out of repeated flicks while
    // still persisting promptly when the reader pauses.
    static let idleDelay: Duration = .milliseconds(250)

    static func intent(
        scrollRegion: ThreadReadingScrollRegion,
        didMoveAwayFromTop: Bool
    ) -> ThreadReadingPersistenceIntent {
        guard didMoveAwayFromTop else { return .none }
        switch scrollRegion {
        case .top:
            return .clear
        case .away:
            return .record
        case .nearTop:
            return .none
        }
    }
}

final class ThreadReadingTrackingState {
    var visiblePostIDs: Set<UInt64> = []
    var isScrollIdle = true
    var scrollRegion: ThreadReadingScrollRegion = .top
    var lastRecordedPostID: UInt64?
    var didMoveAwayFromTop = false
    var pendingCommitTask: Task<Void, Never>?
    var pendingCommitID: UUID?
    var pendingAutomaticPageLoad = false

    @discardableResult
    func postBecameVisible(_ postID: UInt64) -> Bool {
        guard postID > 0 else { return false }
        return visiblePostIDs.insert(postID).inserted
    }

    @discardableResult
    func postBecameHidden(_ postID: UInt64) -> Bool {
        visiblePostIDs.remove(postID) != nil
    }

    @discardableResult
    func replaceVisiblePostIDs(_ postIDs: Set<UInt64>) -> Bool {
        let sanitized = Set(postIDs.filter { $0 > 0 })
        guard sanitized != visiblePostIDs else { return false }
        visiblePostIDs = sanitized
        return true
    }

    func consumePendingAutomaticPageLoad(canLoad: Bool) -> Bool {
        guard canLoad, pendingAutomaticPageLoad else { return false }
        pendingAutomaticPageLoad = false
        return true
    }

    func cancelPendingCommit() {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        pendingCommitID = nil
    }

    func reset() {
        cancelPendingCommit()
        visiblePostIDs = []
        isScrollIdle = true
        scrollRegion = .top
        lastRecordedPostID = nil
        didMoveAwayFromTop = false
        pendingAutomaticPageLoad = false
    }
}

struct ThreadPreciseScrollSession: Equatable, Sendable {
    let id: UUID
    let postID: UInt64

    init(id: UUID = UUID(), postID: UInt64) {
        self.id = id
        self.postID = postID
    }
}

enum ThreadReadingVisibilityPolicy {
    static func bottomMostVisiblePostID(
        postIDsInDisplayOrder: [UInt64],
        visiblePostIDs: Set<UInt64>,
        excludedPostID: UInt64?
    ) -> UInt64? {
        postIDsInDisplayOrder.last {
            $0 > 0 && $0 != excludedPostID && visiblePostIDs.contains($0)
        }
    }
}

final class ThreadLegacyReadingViewportState {
    var entries: [UInt64: ThreadPostViewportEntry] = [:]
    var viewportSize: CGSize = .zero

    func reset() {
        entries = [:]
        viewportSize = .zero
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
    static let minimumVisibleFraction: CGFloat = 0.01

    static func visiblePostIDs(
        entries: [UInt64: ThreadPostViewportEntry],
        viewportSize: CGSize,
        eligiblePostIDs: Set<UInt64>
    ) -> Set<UInt64> {
        guard viewportSize.width > 0, viewportSize.height > 0 else { return [] }
        let viewportMinY: CGFloat = 0
        let viewportMaxY = viewportSize.height
        return Set(entries.values.compactMap { entry in
            guard eligiblePostIDs.contains(entry.postID),
                  entry.minY.isFinite,
                  entry.maxY.isFinite,
                  entry.maxY > entry.minY else { return nil }
            let visibleHeight = min(entry.maxY, viewportMaxY)
                - max(entry.minY, viewportMinY)
            let requiredHeight = max(
                (entry.maxY - entry.minY) * minimumVisibleFraction,
                1
            )
            return visibleHeight >= requiredHeight ? entry.postID : nil
        })
    }
}

private struct ThreadPostScrollRequest: Equatable {
    var id: UUID
    var postID: UInt64
}

private enum ThreadDetailScrollTarget: Hashable {
    case replies
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
    @ViewBuilder
    func threadReadingVisibility(
        post: Post,
        onVisibilityChange: @escaping (Bool) -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            onScrollVisibilityChange(threshold: 0.01) { isVisible in
                onVisibilityChange(isVisible)
            }
        } else {
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

    @ViewBuilder
    func threadPreciseScrollAnchor(post: Post, isEnabled: Bool) -> some View {
        if isEnabled {
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
        } else {
            self
        }
    }
}

private struct ThreadDetailScrollTelemetryModifier: ViewModifier {
    let onActivityChange: (_ isDirectInteraction: Bool, _ isIdle: Bool) -> Void
    let onRegionChange: (ThreadReadingScrollRegion) -> Void
    let onLegacySnapshot: (LegacyScrollTelemetrySnapshot) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollPhaseChange { _, newPhase in
                    onActivityChange(
                        newPhase == .tracking || newPhase == .interacting,
                        newPhase == .idle
                    )
                }
                .onScrollGeometryChange(for: ThreadReadingScrollRegion.self) { geometry in
                    ThreadReadingScrollRegion.resolve(
                        distanceFromTop: ShortPullRefreshPolicy.distanceFromTop(
                            contentOffsetY: geometry.contentOffset.y,
                            topInset: geometry.contentInsets.top
                        )
                    )
                } action: { _, region in
                    onRegionChange(region)
                }
        } else {
            content.legacyScrollTelemetry { snapshot in
                onLegacySnapshot(snapshot)
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
    @Environment(\.readingPreferences) private var readingPreferences
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        .frame(minHeight: controlHeight, alignment: .center)
        .background(.regularMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thread-reply-control-bar")
    }

    private var controlHeight: CGFloat {
        ReplyControlBarLayout.controlHeight(
            readerFontSize: readingPreferences.fontSize,
            dynamicTypeSize: dynamicTypeSize
        )
    }

    private var filterControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TiebaPureTheme.Spacing.md) {
                filterButton(title: "全部回复", isSelected: seeLz == false) {
                    onSeeLzChange(false)
                }
                .accessibilityIdentifier("thread-reply-controls")
                filterButton(title: "只看楼主", isSelected: seeLz) {
                    onSeeLzChange(true)
                }
            }
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                filterButton(title: "全部回复", isSelected: seeLz == false) {
                    onSeeLzChange(false)
                }
                .accessibilityIdentifier("thread-reply-controls")
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
            .frame(height: controlHeight, alignment: .center)
            .background(
                Capsule(style: .continuous)
                    .fill(TiebaPureTheme.ColorToken.readerGroupedBackground)
            )
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                ForEach(ThreadReplySort.allCases) { item in
                    sortButton(item)
                }
            }
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
                .font(Font(ReplyControlBarTypography.font(
                    textStyle: .subheadline,
                    isEmphasized: sortType == item,
                    readerFontSize: readingPreferences.fontSize,
                    dynamicTypeSize: dynamicTypeSize
                )))
                .foregroundStyle(sortType == item ? Color.primary : Color.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 48, minHeight: controlHeight, alignment: .center)
                .offset(y: ReplyControlBarLayout.opticalTextOffset)
                .background(
                    Capsule(style: .continuous)
                        .fill(sortType == item ? Color(uiColor: .systemBackground) : Color.clear)
                        .padding(3)
                )
        }
        .buttonStyle(.plain)
        .minTouchTarget()
        .accessibilityLabel("按\(item.title)排列回复")
        .accessibilityValue(sortType == item ? "已选择" : "未选择")
        .accessibilityIdentifier("thread-reply-sort-\(item.rawValue)")
        .accessibilityAddTraits(sortType == item ? [.isSelected] : [])
    }

    private func filterButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Font(ReplyControlBarTypography.font(
                    textStyle: .body,
                    isEmphasized: isSelected,
                    readerFontSize: readingPreferences.fontSize,
                    dynamicTypeSize: dynamicTypeSize
                )))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .frame(minHeight: controlHeight, alignment: .center)
                .offset(y: ReplyControlBarLayout.opticalTextOffset)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

enum ReplyControlBarLayout {
    static let minimumHeight: CGFloat = 44
    static let opticalTextOffset: CGFloat = -1

    static func controlHeight(
        readerFontSize: ReaderFontSize,
        dynamicTypeSize: DynamicTypeSize
    ) -> CGFloat {
        let bodyFont = ReplyControlBarTypography.font(
            textStyle: .body,
            isEmphasized: true,
            readerFontSize: readerFontSize,
            dynamicTypeSize: dynamicTypeSize
        )
        let sortFont = ReplyControlBarTypography.font(
            textStyle: .subheadline,
            isEmphasized: true,
            readerFontSize: readerFontSize,
            dynamicTypeSize: dynamicTypeSize
        )
        return ceil(max(minimumHeight, max(bodyFont.lineHeight, sortFont.lineHeight) + 12))
    }
}

enum ReplyControlBarTypography {
    static func font(
        textStyle: UIFont.TextStyle,
        isEmphasized: Bool,
        readerFontSize: ReaderFontSize,
        dynamicTypeSize: DynamicTypeSize = .large
    ) -> UIFont {
        ReaderTypographyPolicy.font(
            textStyle: textStyle,
            weight: isEmphasized ? .semibold : .regular,
            fontSize: readerFontSize,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: contentSizeCategory(for: dynamicTypeSize)
            )
        )
    }

    private static func contentSizeCategory(for dynamicTypeSize: DynamicTypeSize) -> UIContentSizeCategory {
        switch dynamicTypeSize {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

private struct SubpostListSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var contentSubmissionSettingsStore: ContentSubmissionSettingsStore
    @Environment(\.readingPreferences) private var readingPreferences
    @ObservedObject private var blocklistStore = BlocklistStore.shared

    // pb/floor carries no client page-size field; the server pages replies
    // ten at a time. A short or empty page therefore ends pagination, while
    // the snapshot subpostCount would freeze out replies posted after the
    // thread page loaded.
    private static let subpostsPageSize = 10

    let account: Account?
    let thread: ThreadSummary
    let forum: Forum
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
    @State private var composerRoute: ContentComposerRoute?
    @State private var contentActionError: String?
    @State private var pendingSubmittedSubpostID: UInt64?
    @State private var hasPendingSubmission = false
    @State private var pendingSubmissionAccount: Account?
    @State private var pendingSubmissionRouteID: UUID?
    @State private var submissionReloadGeneration = 0
    @State private var submissionReloadTask: Task<Void, Never>?
    @State private var linkedRoute: ExternalRoute?

    init(
        account: Account?,
        thread: ThreadSummary,
        forum: Forum,
        post: Post,
        initialSubpostID: UInt64? = nil,
        threadAuthorID: Int64?,
        onPostLikeChanged: @escaping (Post) -> Void,
        onInteractiveDismiss: @escaping () -> Void
    ) {
        self.account = account
        self.thread = thread
        self.forum = forum
        self.threadAuthorID = threadAuthorID
        self.onPostLikeChanged = onPostLikeChanged
        self.onInteractiveDismiss = onInteractiveDismiss
        _post = State(initialValue: post)
        _pendingSubmittedSubpostID = State(initialValue: initialSubpostID)
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
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: SubpostSheetScrollTopPreferenceKey.self,
                                    value: Optional(proxy.frame(
                                        in: .named(SubpostSheetScrollCoordinateSpace.name)
                                    ).minY)
                                )
                            }
                            .frame(height: 0)
                            .accessibilityHidden(true)

                            ReaderCard(
                                showsDivider: false,
                                contentBottomPadding: ThreadPostMetadataPlacement.standaloneReply.cardBottomPadding
                            ) {
                                VStack(alignment: .leading, spacing: ThreadReplyLayout.headerContentSpacing) {
                                    UserHeaderView(
                                        author: post.author,
                                        floor: post.floor,
                                        isThreadAuthor: post.author.id == threadAuthorID,
                                        trailingLikeCount: post.likeCount,
                                        isLiked: post.isLiked,
                                        isLikeUpdating: updatingLikeIDs.contains(post.id),
                                        onToggleLike: contentSubmissionSettingsStore.likesEnabled
                                            ? { togglePostLike() }
                                            : nil,
                                        likeAccessibilityIdentifier: "thread-subpost-parent-like-button",
                                        onOpenUser: { openUser(post.author) }
                                    )

                                    VStack(alignment: .leading, spacing: ThreadReplyLayout.bodyStackSpacing) {
                                        ContentBlocksView(
                                            blocks: post.blocks,
                                            textStyle: .reply,
                                            lineLimit: ThreadContentDisplayPolicy.detailLineLimit,
                                            readerFontSize: readingPreferences.fontSize,
                                            readerFontFamily: readingPreferences.fontFamily,
                                            readerLineSpacing: readingPreferences.lineSpacing,
                                            inlineAccessibilityIdentifier: "thread-subpost-parent-text",
                                            onOpenTiebaRoute: openTiebaRoute,
                                            onPlainTextTap: contentSubmissionSettingsStore.repliesEnabled
                                                ? openParentReplyComposer
                                                : nil
                                        )
                                        ThreadPostMetadataView(
                                            createdAt: post.createdAt,
                                            ipAddress: ThreadPostMetadataText.firstLocation(
                                                post.ipAddress,
                                                post.author.ipAddress
                                            ),
                                            accessibilityIdentifier: "thread-subpost-parent-metadata",
                                            replyAccessibilityLabel: "回复第\(post.floor)楼",
                                            replyAccessibilityIdentifier: "subposts-compose-reply-button",
                                            onReply: contentSubmissionSettingsStore.repliesEnabled
                                                ? openParentReplyComposer
                                                : nil
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
                                    onOpenTiebaRoute: openTiebaRoute,
                                    isLikeUpdating: updatingLikeIDs.contains(subpost.id),
                                    onToggleLike: contentSubmissionSettingsStore.likesEnabled
                                        ? { toggleSubpostLike(subpost) }
                                        : nil,
                                    onReply: contentSubmissionSettingsStore.repliesEnabled
                                        ? { openSubpostReplyComposer(subpost) }
                                        : nil
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
                                    Text("加载更多楼中楼回复")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                                .minTouchTarget()
                                .padding(.vertical, TiebaPureTheme.Spacing.xs)
                                .accessibilityIdentifier("subposts-load-more")
                            }

                            Color.clear
                                .frame(height: 24)
                                .accessibilityHidden(true)
                        }
                        .readableWidth()
                    }
                    .coordinateSpace(name: SubpostSheetScrollCoordinateSpace.name)
                    .subpostSheetLegacyScrollTelemetry()
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
                .alert("提示", isPresented: contentActionErrorIsPresented) {
                    Button("好", role: .cancel) {
                        contentActionError = nil
                    }
                } message: {
                    Text(contentActionError ?? "")
                }
                .sheet(item: $composerRoute, onDismiss: handleComposerDismissed) { route in
                    if let account {
                        let presentationGeneration = submissionReloadGeneration
                        ContentComposerPresentation(
                            account: account,
                            target: route.target,
                            onDismiss: { composerRoute = nil },
                            onSent: { receipt in
                                guard self.account?.sessionIdentity == account.sessionIdentity,
                                      composerRoute?.id == route.id,
                                      presentationGeneration == submissionReloadGeneration else { return }
                                pendingSubmittedSubpostID = receipt.postID
                                hasPendingSubmission = true
                                pendingSubmissionAccount = account
                                pendingSubmissionRouteID = route.id
                            },
                            onDraftCleanupFailure: {
                                contentActionError = "内容已发送，但本机草稿未能清除。重新打开编辑器前请先重试草稿读取。"
                            }
                        )
                        .environmentObject(environment)
                    }
                }
                // A tieba.baidu.com link tapped in the parent floor or in a
                // 楼中楼 reply opens from here: the reader behind this sheet is
                // already presenting it and cannot present a second cover.
                .fullScreenCover(item: $linkedRoute) { route in
                    ExternalRouteView(account: account, route: route) {
                        linkedRoute = nil
                    }
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
                cancelSubmissionReload()
                loadTask?.cancel()
                requestGeneration += 1
                isLoading = false
                cancelLikeTasks()
                cancelUserResolution()
                hasPendingSubmission = false
                pendingSubmissionAccount = nil
                pendingSubmissionRouteID = nil
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
        }
    }

    private func openTiebaRoute(_ route: ExternalRoute) {
        linkedRoute = route
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

    private var contentActionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { contentActionError != nil },
            set: { isPresented in
                if isPresented == false { contentActionError = nil }
            }
        )
    }

    private var threadID: Int64 { thread.id }
    private var forumID: Int64 { forum.id }

    private func handleComposerDismissed() {
        guard hasPendingSubmission,
              let submittedAccount = pendingSubmissionAccount,
              pendingSubmissionRouteID != nil else { return }
        hasPendingSubmission = false
        pendingSubmissionAccount = nil
        pendingSubmissionRouteID = nil
        guard account?.sessionIdentity == submittedAccount.sessionIdentity else { return }

        submissionReloadTask?.cancel()
        submissionReloadGeneration += 1
        let generation = submissionReloadGeneration
        submissionReloadTask = Task { @MainActor in
            guard composerRoute == nil else { return }
            await reload()
            guard Task.isCancelled == false,
                  generation == submissionReloadGeneration,
                  account?.sessionIdentity == submittedAccount.sessionIdentity,
                  composerRoute == nil else { return }
            submissionReloadTask = nil
        }
    }

    private func openParentReplyComposer() {
        guard contentSubmissionSettingsStore.repliesEnabled else {
            contentActionError = "请先在设置中开启“允许回帖”。"
            return
        }
        guard account != nil else {
            contentActionError = "登录后才能回复楼层。"
            return
        }
        cancelSubmissionReload()
        composerRoute = ContentComposerRoute(
            target: .postReply(thread: thread, forum: forum, post: post)
        )
    }

    private func openSubpostReplyComposer(_ subpost: Subpost) {
        guard contentSubmissionSettingsStore.repliesEnabled else {
            contentActionError = "请先在设置中开启“允许回帖”。"
            return
        }
        guard account != nil else {
            contentActionError = "登录后才能回复用户。"
            return
        }
        cancelSubmissionReload()
        composerRoute = ContentComposerRoute(
            target: .subpostReply(
                thread: thread,
                forum: forum,
                parentPost: post,
                subpost: subpost
            )
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

    private func cancelSubmissionReload() {
        submissionReloadTask?.cancel()
        submissionReloadTask = nil
        submissionReloadGeneration += 1
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
            let requestedSubpostID = requestedPage == 1
                ? (pendingSubmittedSubpostID ?? 0)
                : 0
            let task = Task { try await environment.api.subposts(
                account: account,
                threadID: threadID,
                postID: post.id,
                forumID: forumID,
                page: requestedPage,
                subpostID: requestedSubpostID
            ) }
            loadTask = task
            let loaded = try await task.value
            guard generation == requestGeneration else { return }
            let visibleSubposts = loaded.filter(TiebaContentFilter.shouldKeep(subpost:))
            if requestedPage == 1 {
                subposts = visibleSubposts
                pendingSubmittedSubpostID = nil
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
        guard contentSubmissionSettingsStore.likesEnabled else { return }
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
        guard contentSubmissionSettingsStore.likesEnabled else { return }
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
        guard contentSubmissionSettingsStore.likesEnabled else { return }
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
                try await environment.socialMutationCoordinator.setPostLiked(
                    account: account,
                    threadID: threadID,
                    postID: id,
                    objectType: objectType,
                    liked: targetState
                )
                try Task.checkCancellation()
                apply(targetState)
            } catch is CancellationError {
                // The coordinator keeps an already-started write alive; this
                // sheet only stops applying the result to stale view state.
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
    @Environment(\.readingPreferences) private var readingPreferences

    let subpost: Subpost
    let threadAuthorID: Int64?
    let onOpenUser: ((UserSummary) -> Void)?
    let onOpenTiebaRoute: ((ExternalRoute) -> Void)?
    let isLikeUpdating: Bool
    let onToggleLike: (() -> Void)?
    let onReply: (() -> Void)?

    var body: some View {
        ReaderCard(
            contentBottomPadding: ThreadPostMetadataPlacement.standaloneReply.cardBottomPadding
        ) {
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

                VStack(alignment: .leading, spacing: ThreadReplyLayout.bodyStackSpacing) {
                    ContentBlocksView(
                        blocks: subpost.blocks,
                        textStyle: .reply,
                        lineLimit: ThreadContentDisplayPolicy.detailLineLimit,
                        readerFontSize: readingPreferences.fontSize,
                        readerFontFamily: readingPreferences.fontFamily,
                        readerLineSpacing: readingPreferences.lineSpacing,
                        inlineAccessibilityIdentifier: "thread-subpost-text",
                        onOpenUser: onOpenUser,
                        onOpenTiebaRoute: onOpenTiebaRoute,
                        onPlainTextTap: onReply
                    )
                    ThreadPostMetadataView(
                        createdAt: subpost.createdAt,
                        ipAddress: ThreadPostMetadataText.firstLocation(
                            subpost.ipAddress,
                            subpost.author.ipAddress
                        ),
                        accessibilityIdentifier: "thread-subpost-metadata",
                        replyAccessibilityLabel: "回复用户\(subpost.author.displayNameResolved)",
                        replyAccessibilityIdentifier: "subpost-reply-button-\(subpost.id)",
                        onReply: onReply
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
