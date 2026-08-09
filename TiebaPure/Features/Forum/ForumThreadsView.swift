import SwiftUI

struct ForumThreadsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var contentSubmissionSettingsStore: ContentSubmissionSettingsStore
    @Environment(\.readerSplitOpenThread) private var readerSplitOpenThread
    @Environment(\.dismiss) private var dismiss
    let account: Account?
    let forum: Forum
    private let sortPreferenceStore: ForumThreadSortPreferenceStore
    private let openThreadInParent: ((ReaderSplitThreadRoute) -> Void)?
    private let openSearchInParent: ((ForumSearchLaunchRoute) -> Void)?
    private let openUserInParent: ((UserSummary) -> Void)?

    @Environment(\.readingPreferences) private var readingPreferences
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
    @State private var forumMembership: ForumMembership?
    @State private var isUpdatingForumFollow = false
    @State private var forumActionError: String?
    @State private var socialGeneration = 0
    @State private var membershipTask: Task<ForumMembership, Error>?
    @State private var forumFollowTask: Task<Void, Never>?
    @State private var composerRoute: ContentComposerRoute?
    @State private var pendingSubmissionReceipt: ContentSubmissionReceipt?
    @State private var pendingSubmissionForumID: Int64?
    @State private var pendingSubmissionAccount: Account?
    @State private var pendingSubmissionRouteID: UUID?
    @State private var submissionNavigationGeneration = 0
    @State private var submissionNavigationTask: Task<Void, Never>?

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
        .task(id: account?.sessionIdentity) {
            await loadForumMembership()
        }
        .onChange(of: account?.sessionIdentity) { _ in
            cancelSubmissionNavigation()
            requestGeneration += 1
            loadTask?.cancel()
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
            composerRoute = nil
            pendingSubmissionReceipt = nil
            pendingSubmissionForumID = nil
            pendingSubmissionAccount = nil
            pendingSubmissionRouteID = nil
            cancelSocialRequests()
            forumMembership = nil
            forumActionError = nil
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
                    if account != nil, forumMembership == nil {
                        Task { await loadForumMembership() }
                    } else {
                        toggleForumFollow()
                    }
                } label: {
                    if isUpdatingForumFollow || membershipTask != nil {
                        ProgressView()
                            .controlSize(.small)
                    } else if account != nil, forumMembership == nil {
                        Image(systemName: "arrow.clockwise")
                    } else {
                        Image(systemName: forumMembership?.isFollowed == true ? "star.fill" : "star")
                    }
                }
                .minTouchTarget()
                .disabled(isUpdatingForumFollow || membershipTask != nil)
                .accessibilityLabel(forumFollowAccessibilityLabel)
                .accessibilityHint(account == nil ? "登录后可以关注贴吧" : "切换当前贴吧的关注状态")
                .accessibilityIdentifier("forum-follow-button")

                if contentSubmissionSettingsStore.newThreadsEnabled {
                    Button {
                        openNewThreadComposer()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .minTouchTarget()
                    .accessibilityLabel("发布新帖")
                    .accessibilityHint(newThreadAccessibilityHint)
                    .accessibilityIdentifier("forum-new-thread-button")
                    .disabled(account != nil && resolvedPostingForum == nil)
                }

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
        .alert("提示", isPresented: forumActionErrorIsPresented) {
            Button("好", role: .cancel) { forumActionError = nil }
        } message: {
            Text(forumActionError ?? "")
        }
        .sheet(item: $composerRoute, onDismiss: handleComposerDismissed) { route in
            if let account {
                let presentationGeneration = submissionNavigationGeneration
                ContentComposerPresentation(
                    account: account,
                    target: route.target,
                    onDismiss: { composerRoute = nil },
                    onSent: { receipt in
                        guard self.account?.sessionIdentity == account.sessionIdentity,
                              composerRoute?.id == route.id,
                              presentationGeneration == submissionNavigationGeneration else { return }
                        pendingSubmissionReceipt = receipt
                        pendingSubmissionForumID = route.target.forumID
                        pendingSubmissionAccount = account
                        pendingSubmissionRouteID = route.id
                    },
                    onDraftCleanupFailure: {
                        forumActionError = "内容已发送，但本机草稿未能清除。重新打开编辑器前请先重试草稿读取。"
                    }
                )
                .environmentObject(environment)
            }
        }
        .onReceive(environment.socialRelationshipState.forumFollowDidChange) { change in
            guard change.accountID == account?.id,
                  SocialRelationshipState.sameForum(change.forum, forum) else { return }
            forumMembership = ForumMembership(
                forumID: change.forum.id > 0 ? change.forum.id : forum.id,
                isFollowed: change.isFollowed
            )
        }
        .onReceive(environment.socialRelationshipState.forumMutationActivityDidChange) { change in
            guard change.accountID == account?.id,
                  SocialRelationshipState.sameForum(change.forum, forum) else { return }
            isUpdatingForumFollow = change.isPending
        }
        .onDisappear {
            cancelSubmissionNavigation()
            loadTask?.cancel()
            requestGeneration += 1
            isLoading = false
            cancelSocialRequests()
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
            let presentation = ForumPinnedPresentationPolicy.presentation(
                threads: threads,
                showsPinnedThreads: showsPinnedThreads
            )
            ScrollView {
                VStack(spacing: 0) {
                    categoryPicker

                    Divider()

                    forumThreadsContent(presentation: presentation)
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
                surface: .grouped,
                accessibilityIdentifier: "forum-refresh-animation"
            ) {
                guard isLoading == false else { return }
                await reload()
            }
            .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        }
    }

    @ViewBuilder
    private func forumThreadsContent(
        presentation: ForumPinnedPresentation
    ) -> some View {
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
                if presentation.pinnedThreads.isEmpty == false {
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
                            Text("\(presentation.pinnedThreads.count)")
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
                            ? "收起\(presentation.pinnedThreads.count)条置顶内容"
                            : "展开\(presentation.pinnedThreads.count)条置顶内容"
                    )
                    .accessibilityIdentifier("forum-pinned-threads-toggle")

                    Divider()
                }

                ForEach(Array(presentation.visibleThreads.enumerated()), id: \.element.id) { index, thread in
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
                        onOpenUser: openUser,
                        onOpenMedia: { item, mediaItems, sourceFrame, sourceImage, sourceAnchor in
                            openMedia(
                                item,
                                in: mediaItems,
                                sourceFrame: sourceFrame,
                                sourceImage: sourceImage,
                                sourceAnchor: sourceAnchor,
                                fallbackThread: thread
                            )
                        }
                    )
                    .onAppear {
                        guard PaginationPrefetchPolicy.shouldLoadMore(
                            currentIndex: index,
                            totalCount: presentation.visibleThreads.count
                        ) else { return }
                        Task { await loadMore() }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("thread-row")

                    if index == presentation.visibleThreads.count - 1, isLoading, didLoad {
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

    private var forumActionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { forumActionError != nil },
            set: { isPresented in
                if isPresented == false { forumActionError = nil }
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
        let requestedSession = account?.sessionIdentity
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
                  requestedSession == account?.sessionIdentity,
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
                  requestKey == activeRequestKey,
                  requestedSession == account?.sessionIdentity else { return }
            loadTask = nil
            activeRequestKey = nil
            isLoading = false
            return
        } catch {
            guard generation == requestGeneration,
                  requestKey == activeRequestKey,
                  requestedSession == account?.sessionIdentity,
                  requestKey.category == selectedCategory else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration,
              requestKey == activeRequestKey,
              requestedSession == account?.sessionIdentity else { return }
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

    private func openNewThreadComposer() {
        guard contentSubmissionSettingsStore.newThreadsEnabled else {
            forumActionError = "请先在设置中开启“允许发帖”。"
            return
        }
        guard account != nil else {
            forumActionError = "登录后才能发布新帖。"
            return
        }
        guard let resolvedPostingForum else {
            forumActionError = "正在获取贴吧信息，请稍后重试。"
            return
        }
        cancelSubmissionNavigation()
        composerRoute = ContentComposerRoute(target: .newThread(in: resolvedPostingForum))
    }

    private func handleComposerDismissed() {
        guard let receipt = pendingSubmissionReceipt,
              let submittedAccount = pendingSubmissionAccount,
              pendingSubmissionRouteID != nil else { return }
        let submittedForumID = pendingSubmissionForumID
        pendingSubmissionReceipt = nil
        pendingSubmissionForumID = nil
        pendingSubmissionAccount = nil
        pendingSubmissionRouteID = nil
        guard account?.sessionIdentity == submittedAccount.sessionIdentity else { return }

        submissionNavigationTask?.cancel()
        submissionNavigationGeneration += 1
        let generation = submissionNavigationGeneration
        submissionNavigationTask = Task { @MainActor in
            guard composerRoute == nil else { return }
            await reload()
            guard Task.isCancelled == false,
                  generation == submissionNavigationGeneration,
                  account?.sessionIdentity == submittedAccount.sessionIdentity,
                  composerRoute == nil else { return }
            openThread(threadID: receipt.threadID, forumID: submittedForumID ?? forum.id)
            submissionNavigationTask = nil
        }
    }

    private func cancelSubmissionNavigation() {
        submissionNavigationTask?.cancel()
        submissionNavigationTask = nil
        submissionNavigationGeneration += 1
    }

    private var resolvedPostingForum: Forum? {
        ContentSubmissionForumResolver.resolve(
            forum,
            fallbackID: forumMembership?.forumID
        )
    }

    private var newThreadAccessibilityHint: String {
        guard account != nil else { return "登录后可以在本吧发布新帖" }
        return resolvedPostingForum == nil ? "正在获取贴吧信息" : "打开新帖编辑器"
    }

    /// Media in the list opens the picture or the video, the same as the home
    /// feed; only media that carries neither falls back to the thread.
    private func openMedia(
        _ item: ReaderMediaItem,
        in mediaItems: [ReaderMediaItem],
        sourceFrame: CGRect?,
        sourceImage: UIImage?,
        sourceAnchor: ImagePreviewSourceAnchor?,
        fallbackThread: ThreadSummary
    ) {
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
            openThread(
                threadID: fallbackThread.id,
                forumID: fallbackThread.forumID ?? forum.id
            )
        }
    }

    private func openUser(_ user: UserSummary) {
        if let openUserInParent {
            openUserInParent(user)
        } else {
            selectedUser = user
        }
    }

    private func loadForumMembership() async {
        membershipTask?.cancel()
        membershipTask = nil
        socialGeneration += 1
        guard let account else {
            forumMembership = nil
            isUpdatingForumFollow = false
            return
        }
        socialGeneration += 1
        let generation = socialGeneration
        let requestedSession = account.sessionIdentity
        if let known = environment.socialRelationshipState.forumFollowState(
            accountID: account.id,
            forum: forum
        ) {
            forumMembership = ForumMembership(forumID: forum.id, isFollowed: known)
        }
        isUpdatingForumFollow = environment.socialRelationshipState.isForumMutationPending(
            accountID: account.id,
            forum: forum
        )

        do {
            let task = Task { try await environment.api.forumMembership(account: account, forum: forum) }
            membershipTask = task
            let membership = try await task.value
            guard generation == socialGeneration,
                  requestedSession == self.account?.sessionIdentity else { return }
            let followed = environment.socialRelationshipState.forumFollowOverride(
                accountID: account.id,
                forum: forum
            ) ?? membership.isFollowed
            forumMembership = ForumMembership(forumID: membership.forumID, isFollowed: followed)
            var resolvedForum = forum
            resolvedForum.id = membership.forumID
            environment.socialRelationshipState.seedForumFollow(
                accountID: account.id,
                forum: resolvedForum,
                isFollowed: membership.isFollowed
            )
            membershipTask = nil
        } catch is CancellationError {
            guard generation == socialGeneration,
                  requestedSession == self.account?.sessionIdentity else { return }
            membershipTask = nil
        } catch {
            guard generation == socialGeneration,
                  requestedSession == self.account?.sessionIdentity else { return }
            membershipTask = nil
            if forumMembership == nil {
                forumActionError = ReaderErrorMessage.message(for: error)
            }
        }
    }

    private func toggleForumFollow() {
        guard isUpdatingForumFollow == false else { return }
        guard let account else {
            forumActionError = "登录后才能关注贴吧。"
            return
        }
        guard forumMembership != nil else {
            Task { await loadForumMembership() }
            return
        }
        let targetState = forumMembership?.isFollowed != true
        socialGeneration += 1
        let generation = socialGeneration
        let requestedSession = account.sessionIdentity
        isUpdatingForumFollow = true
        forumActionError = nil
        membershipTask?.cancel()
        forumFollowTask?.cancel()

        let task = Task {
            do {
                let membership = try await environment.socialMutationCoordinator.setForumFollowed(
                    account: account,
                    forum: forum,
                    followed: targetState
                )
                try Task.checkCancellation()
                guard generation == socialGeneration,
                      requestedSession == self.account?.sessionIdentity else { return }
                forumMembership = membership
            } catch is CancellationError {
                // The coordinator owns the write and its read-only
                // reconciliation after this page disappears.
            } catch {
                guard generation == socialGeneration,
                      requestedSession == self.account?.sessionIdentity else { return }
                forumActionError = ReaderErrorMessage.message(for: error)
            }
            guard generation == socialGeneration,
                  requestedSession == self.account?.sessionIdentity else { return }
            forumFollowTask = nil
            isUpdatingForumFollow = environment.socialRelationshipState.isForumMutationPending(
                accountID: account.id,
                forum: forum
            )
        }
        forumFollowTask = task
    }

    private func cancelSocialRequests() {
        membershipTask?.cancel()
        forumFollowTask?.cancel()
        membershipTask = nil
        forumFollowTask = nil
        socialGeneration += 1
        isUpdatingForumFollow = false
    }

    private var forumFollowAccessibilityLabel: String {
        if membershipTask != nil { return "正在读取关注状态" }
        if account != nil, forumMembership == nil { return "重新读取关注状态" }
        return forumMembership?.isFollowed == true ? "取消关注本吧" : "关注本吧"
    }

    private func blockCurrentForum() {
        blocklistStore.addForum(id: forum.id, named: forum.name)
        dismiss()
    }
}

enum ContentSubmissionForumResolver {
    static func resolve(_ forum: Forum, fallbackID: Int64?) -> Forum? {
        let forumID = forum.id > 0 ? forum.id : fallbackID
        guard let forumID, forumID > 0,
              forum.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        var resolved = forum
        resolved.id = forumID
        return resolved
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
    @Environment(\.isReaderSplitListColumn) private var isReaderSplitListColumn

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
            case .list, .userProfile:
                return 0
            case .homeFeed:
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
                    MediaGridView(
                        items: previewMedia,
                        maxItemHeight: presentation.mediaMaxHeight(itemCount: previewMedia.count),
                        totalItemCount: allMedia.count,
                        usesCompactFeedLayout: presentation.usesCompactFeedLayout,
                        isInteractive: onOpenMedia != nil || onOpenThread != nil,
                        destinationAccessibilityLabel: onOpenMedia == nil ? "打开帖子" : nil,
                        destinationAccessibilityHint: onOpenMedia == nil ? "进入帖子详情" : nil,
                        onTap: { item, sourceFrame, sourceImage, sourceAnchor in
                            if let onOpenMedia {
                                guard ForumThreadTapPolicy.destination(for: .media) == .media else { return }
                                onOpenMedia(item, allMedia, sourceFrame, sourceImage, sourceAnchor)
                            } else {
                                onOpenThread?()
                            }
                        }
                    )
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
                        lineLimit: primaryTextLineLimit
                    )
                } else if inlinePreviewBlocks.isEmpty == false {
                    InlineContentText(
                        blocks: inlinePreviewBlocks,
                        style: .body,
                        lineLimit: primaryTextLineLimit,
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
            case .text, .link, .mention, .emoticon, .voice:
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

    private var primaryTextLineLimit: Int {
        ForumThreadRowTextPolicy.primaryLineLimit(
            isReaderSplitListColumn: isReaderSplitListColumn
        )
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

enum ForumThreadRowTextPolicy {
    static func primaryLineLimit(isReaderSplitListColumn: Bool) -> Int {
        isReaderSplitListColumn ? 3 : ThreadContentDisplayPolicy.summaryLineLimit
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
