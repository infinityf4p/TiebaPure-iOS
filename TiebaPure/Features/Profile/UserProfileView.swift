import SwiftUI

private enum UserProfileTab: String, CaseIterable {
    case threads
    case followedForums
}

private struct UserProfileThreadRoute {
    let threadID: Int64
    let forumID: Int64?
    let deletionTarget: OwnThreadDeletionTarget?
}

struct UserProfileView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readingPreferences) private var readingPreferences

    let account: Account?
    let user: UserSummary
    let sourceThreadID: Int64?
    let onReturnToSourceThread: (() -> Void)?
    private let openThreadInParent: ((ReaderSplitThreadRoute) -> Void)?
    private let openForumInParent: ((Forum) -> Void)?

    init(
        account: Account?,
        user: UserSummary,
        sourceThreadID: Int64? = nil,
        onReturnToSourceThread: (() -> Void)? = nil,
        openThreadInParent: ((ReaderSplitThreadRoute) -> Void)? = nil,
        openForumInParent: ((Forum) -> Void)? = nil
    ) {
        self.account = account
        self.user = user
        self.sourceThreadID = sourceThreadID
        self.onReturnToSourceThread = onReturnToSourceThread
        self.openThreadInParent = openThreadInParent
        self.openForumInParent = openForumInParent
    }

    @ObservedObject private var blocklistStore = BlocklistStore.shared
    @State private var profile: UserProfile?
    @State private var threads: [ThreadSummary] = []
    @State private var deletionTargetsByThreadID: [Int64: OwnThreadDeletionTarget] = [:]
    @State private var selectedTab: UserProfileTab = .threads
    @State private var nextPage = 1
    @State private var hasMoreThreads = true
    @State private var threadsVisibility: UserContentVisibility = .visible
    @State private var isLoadingProfile = false
    @State private var isLoadingThreads = false
    @State private var profileError: String?
    @State private var threadsError: String?
    @State private var didLoad = false
    @State private var requestGeneration = 0
    @State private var profileTask: Task<UserProfile, Error>?
    @State private var threadsTask: Task<UserThreadsPage, Error>?
    @State private var followTask: Task<Void, Never>?
    @State private var isUpdatingFollow = false
    @State private var userActionError: String?
    @State private var selectedThread: UserProfileThreadRoute?
    @State private var selectedForum: Forum?
    @State private var selectedRelationshipKind: UserRelationshipKind?
    @State private var showsProfileEditor = false
    @State private var pendingProfileEditRequest: UserProfileEditRequest?

    var body: some View {
        Group {
            if isLoadingProfile, profile == nil {
                ReaderStateView.loading("正在加载用户资料")
            } else if let profileError, profile == nil {
                ReaderStateScrollView(refresh: { await reload() }) {
                    ReaderStateView.error(message: profileError) {
                        Task { await reload() }
                    }
                }
            } else if let profile {
                profileScrollView(profile)
            } else {
                ReaderStateView.empty(title: "无法显示用户资料", message: "请稍后重试。")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .navigationTitle("用户主页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Do not expose the destructive block action while identity is
            // still unknown; a fast tap used to allow blocking oneself.
            if let profile, profile.isCurrentUser == false {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        blockToggleButton
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("更多")
                }
            }
        }
        .alert("提示", isPresented: userActionErrorIsPresented) {
            Button("好", role: .cancel) {
                userActionError = nil
            }
        } message: {
            Text(userActionError ?? "")
        }
        .sheet(isPresented: $showsProfileEditor) {
            if let account,
               let profile,
               pendingProfileEditRequest == nil,
               UserProfileManagementPolicy.canEdit(profile: profile, account: account) {
                UserProfileEditSheet(
                    account: account,
                    profile: profile,
                    onApplied: applyProfileEdit,
                    onNeedsRefresh: requestReadOnlyProfileRefresh
                )
                .environmentObject(environment)
            }
        }
        .navigationDestinationCompat(isPresented: threadIsActive) {
            if let selectedThread {
                ThreadDetailView(
                    account: account,
                    threadID: selectedThread.threadID,
                    forumID: selectedThread.forumID,
                    ownThreadDeletionTarget: selectedThread.deletionTarget,
                    onOwnThreadDeleted: removeDeletedThread,
                    onOwnThreadDeletionNeedsRefresh: requestReadOnlyThreadRefresh
                )
                .interactiveNavigationPopStateSync {
                    self.selectedThread = nil
                }
            }
        }
        .navigationDestinationCompat(isPresented: forumIsActive) {
            if let selectedForum {
                ForumThreadsView(account: account, forum: selectedForum)
                    .interactiveNavigationPopStateSync {
                        self.selectedForum = nil
                    }
            }
        }
        .navigationDestinationCompat(isPresented: relationshipIsActive) {
            if let selectedRelationshipKind, let profile {
                UserRelationshipsView(
                    account: account,
                    user: profile.user,
                    kind: selectedRelationshipKind
                )
                .interactiveNavigationPopStateSync {
                    self.selectedRelationshipKind = nil
                }
            }
        }
        .task {
            guard didLoad == false else { return }
            await reload()
        }
        .onChange(of: account?.sessionIdentity) { _ in
            cancelRequests()
            requestGeneration += 1
            profile = nil
            threads = []
            deletionTargetsByThreadID = [:]
            nextPage = 1
            hasMoreThreads = true
            threadsVisibility = .visible
            isLoadingProfile = false
            isLoadingThreads = false
            profileError = nil
            threadsError = nil
            userActionError = nil
            isUpdatingFollow = false
            didLoad = false
            selectedThread = nil
            selectedForum = nil
            selectedRelationshipKind = nil
            showsProfileEditor = false
            pendingProfileEditRequest = nil
            Task { await reload() }
        }
        .onChange(of: blocklistStore.entries) { _ in
            threads.removeAll { TiebaContentFilter.shouldKeep(thread: $0) == false }
            if var currentProfile = profile {
                currentProfile.followedForums.removeAll {
                    TiebaContentFilter.shouldKeep(forum: $0) == false
                }
                profile = currentProfile
            }
        }
        .onReceive(environment.socialRelationshipState.userFollowDidChange) { change in
            guard change.accountID == account?.id, let currentProfile = profile else { return }
            if SocialRelationshipState.sameUser(currentProfile.user, change.user) {
                applyFollowState(change.isFollowed)
            } else if currentProfile.isCurrentUser {
                profile?.followingCount = max(
                    currentProfile.followingCount + (change.isFollowed ? 1 : -1),
                    0
                )
            }
        }
        .onReceive(environment.socialRelationshipState.forumFollowDidChange) { change in
            guard change.accountID == account?.id, profile?.isCurrentUser == true else { return }
            applyForumFollowChange(change)
        }
        .onReceive(environment.socialRelationshipState.userMutationActivityDidChange) { change in
            guard change.accountID == account?.id,
                  let profile,
                  SocialRelationshipState.sameUser(profile.user, change.user) else { return }
            isUpdatingFollow = change.isPending
        }
        .onReceive(environment.ownThreadMutationState.didChange) { event in
            guard event.accountID == account?.id else { return }
            switch event.outcome {
            case .deleted:
                removeDeletedThread(event.threadID)
            case .needsRefresh:
                requestReadOnlyThreadRefresh()
            }
        }
        .onDisappear {
            cancelRequests()
            requestGeneration += 1
            isLoadingProfile = false
            isLoadingThreads = false
        }
        .accessibilityIdentifier("user-profile-screen")
        .fullScreenInteractiveNavigationPop()
    }

    private func profileScrollView(_ profile: UserProfile) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                UserProfileHeader(
                    profile: profile,
                    onOpenRelationship: { selectedRelationshipKind = $0 },
                    onEditProfile: UserProfileManagementPolicy.canEdit(
                        profile: profile,
                        account: account
                    ) && pendingProfileEditRequest == nil ? { showsProfileEditor = true } : nil
                )
                    .environment(\.userProfileFollowAction, UserProfileFollowAction(
                        isUpdating: isUpdatingFollow,
                        toggle: { toggleFollow(profile) }
                    ))

                if pendingProfileEditRequest != nil {
                    InlineLoadErrorView(
                        message: "资料修改请求已发出，但结果仍待确认。请只刷新资料，不要重复提交。"
                    ) {
                        Task { await reload() }
                    }
                    .padding(.horizontal, TiebaPureTheme.Spacing.md)
                    .padding(.vertical, TiebaPureTheme.Spacing.sm)
                    .background(Color(uiColor: .systemBackground))
                    .accessibilityIdentifier("user-profile-edit-result-pending-inline")
                }

                if let profileError {
                    InlineLoadErrorView(message: profileError) {
                        Task { await reload() }
                    }
                    .padding(.horizontal, TiebaPureTheme.Spacing.md)
                    .padding(.vertical, TiebaPureTheme.Spacing.sm)
                    .background(Color(uiColor: .systemBackground))
                    .accessibilityIdentifier("user-profile-inline-error")
                }

                Section {
                    selectedTabContent(profile)
                } header: {
                    UserProfileTabBar(
                        selectedTab: $selectedTab,
                        threadCount: profile.threadCount,
                        followedForumCount: profile.followedForumCount
                    )
                }
            }
            .readableWidth()
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .shortPullRefresh(
            isEnabled: isLoadingProfile == false && isLoadingThreads == false,
            surface: .grouped,
            accessibilityIdentifier: "user-profile-refresh-animation"
        ) {
            await reload()
        }
    }

    @ViewBuilder
    private func selectedTabContent(_ profile: UserProfile) -> some View {
        switch selectedTab {
        case .threads:
            threadsContent
        case .followedForums:
            followedForumsContent(profile)
        }
    }

    @ViewBuilder
    private var threadsContent: some View {
        if threadsVisibility == .privateContent {
            UserProfilePrivateState(
                title: "该用户已隐藏帖子动态",
                message: "对方没有公开个人帖子，当前无法查看。"
            )
            .accessibilityIdentifier("user-profile-private-posts")
        } else if isLoadingThreads, threads.isEmpty {
            ReaderStateView.loading("正在加载帖子")
                .frame(minHeight: 220)
                .background(Color(uiColor: .systemBackground))
        } else if let threadsError, threads.isEmpty {
            ReaderStateView.error(message: threadsError) {
                Task { await reloadThreads() }
            }
            .frame(minHeight: 220)
            .background(Color(uiColor: .systemBackground))
        } else if threads.isEmpty {
            ReaderStateView.empty(
                title: "暂未发布帖子",
                message: "这里还没有可公开查看的帖子。",
                actionTitle: hasMoreThreads ? "继续加载" : nil,
                action: hasMoreThreads ? { Task { await loadMoreThreads() } } : nil
            )
                .frame(minHeight: 220)
                .background(Color(uiColor: .systemBackground))
        } else {
            LazyVStack(spacing: TiebaPureTheme.Spacing.xs) {
                ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                    ForumThreadRow(
                        thread: thread,
                        presentation: .userProfile,
                        onOpenThread: {
                            openThread(thread)
                        },
                        onOpenForum: { forum in
                            RecentForumStore.shared.save(forum)
                            openForum(forum)
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
                                openThread(thread)
                            }
                        },
                        threadOpenAccessibilityIdentifier: "user-profile-thread-row-\(thread.id)"
                    )
                    .onAppear {
                        guard PaginationPrefetchPolicy.shouldLoadMore(
                            currentIndex: index,
                            totalCount: threads.count
                        ) else { return }
                        Task { await loadMoreThreads() }
                    }
                }

                if isLoadingThreads {
                    ProgressView()
                        .padding(TiebaPureTheme.Spacing.md)
                        .accessibilityLabel("正在加载更多用户帖子")
                }

                if let threadsError {
                    InlineLoadErrorView(message: threadsError) {
                        Task {
                            if nextPage <= 1 { await reloadThreads() }
                            else { await loadMoreThreads() }
                        }
                    }
                } else if hasMoreThreads, isLoadingThreads == false {
                    Button {
                        Task { await loadMoreThreads() }
                    } label: {
                        Label("加载更多用户帖子", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .minTouchTarget()
                    .accessibilityIdentifier("user-profile-threads-load-more")
                }
            }
            .padding(.horizontal, TiebaPureTheme.Spacing.sm)
            .padding(.vertical, TiebaPureTheme.Spacing.sm)
        }
    }

    private func openThread(_ thread: ThreadSummary) {
        if thread.id == sourceThreadID {
            if let onReturnToSourceThread {
                onReturnToSourceThread()
            } else {
                dismiss()
            }
            return
        }
        let deletionTarget = UserProfileManagementPolicy.deletionTarget(
            profile: profile,
            account: account,
            threadID: thread.id,
            targetsByThreadID: deletionTargetsByThreadID
        )
        if let openThreadInParent {
            openThreadInParent(
                ReaderSplitThreadRoute(
                    threadID: thread.id,
                    forumID: thread.forumID,
                    ownThreadDeletionTarget: deletionTarget
                )
            )
        } else {
            selectedThread = UserProfileThreadRoute(
                threadID: thread.id,
                forumID: thread.forumID,
                deletionTarget: deletionTarget
            )
        }
    }

    @ViewBuilder
    private func followedForumsContent(_ profile: UserProfile) -> some View {
        if profile.followedForumsVisibility == .privateContent {
            UserProfilePrivateState(
                title: "该用户已隐藏关注的吧",
                message: "对方没有公开关注列表，当前无法查看。"
            )
            .accessibilityIdentifier("user-profile-private-forums")
        } else if profile.followedForums.isEmpty {
            ReaderStateView.empty(title: "暂未关注贴吧", message: "这里还没有可公开查看的关注吧。")
                .frame(minHeight: 220)
                .background(Color(uiColor: .systemBackground))
                .accessibilityIdentifier("user-profile-empty-forums")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(profile.followedForums.enumerated()), id: \.element.id) { index, forum in
                    Button {
                        RecentForumStore.shared.save(forum)
                        openForum(forum)
                    } label: {
                        HStack(spacing: TiebaPureTheme.Spacing.sm) {
                            AvatarView(
                                url: forum.avatarURL,
                                title: forum.displayName,
                                size: TiebaPureTheme.AvatarSize.medium
                            )

                            Text(forum.displayName)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: TiebaPureTheme.Spacing.sm)

                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                        .padding(.horizontal, TiebaPureTheme.Spacing.md)
                        .padding(.vertical, TiebaPureTheme.Spacing.xs)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("进入\(forum.displayName)")
                    .accessibilityIdentifier("user-profile-forum-row-\(index)")

                    if index < profile.followedForums.count - 1 {
                        Divider()
                            .padding(.leading, TiebaPureTheme.Spacing.md + TiebaPureTheme.AvatarSize.medium + TiebaPureTheme.Spacing.sm)
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
        }
    }

    // The loaded profile carries the authoritative user id; before it arrives
    // the passed-in summary is enough to block by name.
    private var blockTargetUser: UserSummary {
        profile?.user ?? user
    }

    private var isTargetUserBlocked: Bool {
        blocklistStore.isUserBlocked(
            id: blockTargetUser.id,
            displayName: blockTargetUser.displayNameResolved
        )
    }

    private var blockToggleButton: some View {
        Button {
            blocklistStore.toggleUser(
                id: blockTargetUser.id,
                displayName: blockTargetUser.displayNameResolved
            )
        } label: {
            if isTargetUserBlocked {
                Label("取消屏蔽", systemImage: "eye")
            } else {
                Label("屏蔽此用户", systemImage: "eye.slash")
            }
        }
        .accessibilityHint(isTargetUserBlocked ? "恢复显示该用户的内容" : "在本机隐藏该用户的内容")
        .accessibilityIdentifier("profile-block-toggle")
    }

    private var threadIsActive: Binding<Bool> {
        Binding(
            get: { selectedThread != nil },
            set: { isActive in
                if isActive == false { selectedThread = nil }
            }
        )
    }

    private var forumIsActive: Binding<Bool> {
        Binding(
            get: { selectedForum != nil },
            set: { isActive in
                if isActive == false { selectedForum = nil }
            }
        )
    }

    private var relationshipIsActive: Binding<Bool> {
        Binding(
            get: { selectedRelationshipKind != nil },
            set: { isActive in
                if isActive == false { selectedRelationshipKind = nil }
            }
        )
    }

    private func openForum(_ forum: Forum) {
        if let openForumInParent {
            openForumInParent(forum)
        } else {
            selectedForum = forum
        }
    }

    private var userActionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { userActionError != nil },
            set: { isPresented in
                if isPresented == false { userActionError = nil }
            }
        )
    }

    private func reload() async {
        cancelRequests()
        requestGeneration += 1
        let generation = requestGeneration
        let requestedSession = account?.sessionIdentity
        isLoadingProfile = true
        // Cancelled loads from older generations exit without clearing the
        // flag, so each generation bump must reset it before loading again.
        isLoadingThreads = false
        profileError = nil
        threadsError = nil

        do {
            let task = Task {
                try await environment.api.userProfile(account: account, user: user)
            }
            profileTask = task
            let loadedProfile = try await task.value
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity else { return }
            var resolvedProfile = loadedProfile
            if let account {
                if let override = environment.socialRelationshipState.userFollowOverride(
                    accountID: account.id,
                    user: loadedProfile.user
                ) {
                    resolvedProfile.isFollowed = override
                } else {
                    environment.socialRelationshipState.seedUserFollow(
                        accountID: account.id,
                        user: loadedProfile.user,
                        isFollowed: loadedProfile.isFollowed
                    )
                }
                if loadedProfile.isCurrentUser {
                    environment.socialRelationshipState.seedFollowedForums(
                        accountID: account.id,
                        forums: loadedProfile.followedForums
                    )
                }
                isUpdatingFollow = environment.socialRelationshipState.isUserMutationPending(
                    accountID: account.id,
                    user: loadedProfile.user
                )
            }
            let displayedProfile = profileApplyingCurrentBlocklist(resolvedProfile)
            profile = displayedProfile
            if let pendingRequest = pendingProfileEditRequest,
               UserProfileManagementPolicy.profile(
                   displayedProfile,
                   confirms: pendingRequest
               ) {
                pendingProfileEditRequest = nil
            }
            await synchronizeStoredAccountDisplayName(
                from: displayedProfile,
                expectedSession: requestedSession
            )
            profileTask = nil
            isLoadingProfile = false
            await reloadThreads(generation: generation, userID: loadedProfile.user.id)
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            profileTask = nil
            isLoadingProfile = false
        } catch {
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity else { return }
            profileTask = nil
            isLoadingProfile = false
            profileError = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration else { return }
        didLoad = true
    }

    private func reloadThreads() async {
        guard let userID = profile?.user.id, userID > 0 else { return }
        threadsTask?.cancel()
        requestGeneration += 1
        isLoadingThreads = false
        await reloadThreads(generation: requestGeneration, userID: userID)
    }

    private func reloadThreads(generation: Int, userID: Int64) async {
        threadsTask?.cancel()
        nextPage = 1
        hasMoreThreads = true
        threadsVisibility = .visible
        threadsError = nil
        await loadThreads(generation: generation, userID: userID, replacing: true)
    }

    private func loadMoreThreads() async {
        guard let userID = profile?.user.id, userID > 0 else { return }
        await loadThreads(generation: requestGeneration, userID: userID, replacing: false)
    }

    private func loadThreads(
        generation: Int,
        userID: Int64,
        replacing: Bool,
        consecutiveHiddenPageCount: Int = 0
    ) async {
        guard isLoadingThreads == false, hasMoreThreads else { return }
        let requestedSession = account?.sessionIdentity
        let requestedPage = replacing ? 1 : nextPage
        isLoadingThreads = true
        threadsError = nil
        var continuation: LocallyFilteredPaginationDecision?

        do {
            let task = Task {
                try await environment.api.userThreads(
                    account: account,
                    userID: userID,
                    page: requestedPage
                )
            }
            threadsTask = task
            let page = try await task.value
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity else { return }
            threadsVisibility = page.visibility
            let visibleThreads = page.threads.filter(TiebaContentFilter.shouldKeep(thread:))
            let visibleThreadIDs = Set(visibleThreads.map(\.id))
            let visibleDeletionTargets = page.deletionTargetsByThreadID.filter {
                visibleThreadIDs.contains($0.key)
            }
            if replacing {
                threads = visibleThreads
                deletionTargetsByThreadID = visibleDeletionTargets
            } else {
                threads = HomeFeedMerge.append(existing: threads, incoming: visibleThreads)
                deletionTargetsByThreadID.merge(visibleDeletionTargets) { _, incoming in incoming }
            }
            hasMoreThreads = page.visibility == .visible && page.hasMore
            nextPage = page.currentPage + 1
            continuation = LocallyFilteredPaginationPolicy.decision(
                visibleItemCount: visibleThreads.count,
                serverHasMore: hasMoreThreads,
                consecutiveHiddenPageCount: consecutiveHiddenPageCount
            )
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            threadsTask = nil
            isLoadingThreads = false
            return
        } catch {
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity else { return }
            threadsError = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration else { return }
        threadsTask = nil
        isLoadingThreads = false
        if let continuation, continuation.shouldAutomaticallyLoadNextPage {
            await loadThreads(
                generation: generation,
                userID: userID,
                replacing: false,
                consecutiveHiddenPageCount: continuation.consecutiveHiddenPageCount
            )
        }
    }

    private func toggleFollow(_ displayedProfile: UserProfile) {
        guard displayedProfile.isCurrentUser == false, isUpdatingFollow == false else { return }
        guard let account else {
            userActionError = "登录后才能关注用户。"
            return
        }

        let targetState = displayedProfile.isFollowed == false
        let generation = requestGeneration
        isUpdatingFollow = true
        userActionError = nil
        followTask?.cancel()

        let task = Task {
            do {
                try await environment.socialMutationCoordinator.setUserFollowed(
                    account: account,
                    user: displayedProfile.user,
                    followed: targetState
                )
                try Task.checkCancellation()
                guard generation == requestGeneration else { return }
                applyFollowState(targetState)
            } catch is CancellationError {
                // The coordinator keeps an already-started write alive and
                // publishes the eventual state independently of this page.
            } catch {
                guard generation == requestGeneration else { return }
                userActionError = ReaderErrorMessage.message(for: error)
            }
            guard generation == requestGeneration else { return }
            followTask = nil
            isUpdatingFollow = environment.socialRelationshipState.isUserMutationPending(
                accountID: account.id,
                user: displayedProfile.user
            )
        }
        followTask = task
    }

    private func applyFollowState(_ followed: Bool) {
        guard profile?.isFollowed != followed else { return }
        profile?.isFollowed = followed
        let delta = followed ? 1 : -1
        profile?.followerCount = max((profile?.followerCount ?? 0) + delta, 0)
    }

    private func applyForumFollowChange(_ change: ForumFollowChange) {
        guard var currentProfile = profile else { return }
        let existingIndex = currentProfile.followedForums.firstIndex {
            SocialRelationshipState.sameForum($0, change.forum)
        }
        if change.isFollowed {
            if let existingIndex {
                currentProfile.followedForums[existingIndex] = change.forum
            } else {
                currentProfile.followedForums.insert(change.forum, at: 0)
            }
            currentProfile.followedForumCount += 1
        } else {
            if let existingIndex {
                currentProfile.followedForums.remove(at: existingIndex)
            }
            currentProfile.followedForumCount = max(currentProfile.followedForumCount - 1, 0)
        }
        profile = currentProfile
    }

    private func profileApplyingCurrentBlocklist(_ candidate: UserProfile) -> UserProfile {
        var filtered = candidate
        filtered.followedForums.removeAll {
            TiebaContentFilter.shouldKeep(forum: $0) == false
        }
        return filtered
    }

    private func applyProfileEdit(_ request: UserProfileEditRequest) {
        guard let currentProfile = profile else { return }
        profile = UserProfileManagementPolicy.updatedProfile(currentProfile, applying: request)
    }

    private func requestReadOnlyProfileRefresh(_ request: UserProfileEditRequest) {
        pendingProfileEditRequest = request
        Task { await reload() }
    }

    private func synchronizeStoredAccountDisplayName(
        from loadedProfile: UserProfile,
        expectedSession: AccountSessionIdentity?
    ) async {
        guard loadedProfile.isCurrentUser,
              let account,
              let expectedSession,
              account.sessionIdentity == expectedSession,
              loadedProfile.user.displayNameResolved.isEmpty == false,
              account.displayName != loadedProfile.user.displayNameResolved else {
            return
        }
        var updatedAccount = account
        updatedAccount.displayName = loadedProfile.user.displayNameResolved
        do {
            try await environment.accountStore.updateDisplayName(
                updatedAccount.displayName,
                forSession: expectedSession
            )
        } catch let error as AccountStoreError where error == .sessionChanged {
            // A newer login or completed logout owns the store now.
        } catch {
            profileError = "资料已刷新，但本机账号昵称暂时无法同步。"
        }
    }

    private func removeDeletedThread(_ threadID: Int64) {
        guard threads.contains(where: { $0.id == threadID }) else { return }
        threads.removeAll { $0.id == threadID }
        deletionTargetsByThreadID[threadID] = nil
        profile?.threadCount = max((profile?.threadCount ?? 0) - 1, 0)
    }

    private func requestReadOnlyThreadRefresh() {
        Task { await reloadThreads() }
    }

    private func cancelRequests() {
        profileTask?.cancel()
        threadsTask?.cancel()
        followTask?.cancel()
        profileTask = nil
        threadsTask = nil
        followTask = nil
        isUpdatingFollow = false
    }
}

private struct UserProfileFollowAction {
    var isUpdating = false
    var toggle: () -> Void = {}
}

private struct UserProfileFollowActionKey: EnvironmentKey {
    static let defaultValue = UserProfileFollowAction()
}

private extension EnvironmentValues {
    var userProfileFollowAction: UserProfileFollowAction {
        get { self[UserProfileFollowActionKey.self] }
        set { self[UserProfileFollowActionKey.self] = newValue }
    }
}

enum UserProfileMutationPresentationPolicy {
    enum Failure: Equatable {
        case resultPending
        case retryable(message: String)
    }

    static func failure(for error: Error) -> Failure {
        if let mutationError = error as? UserProfileMutationError {
            if mutationError == .outcomeUnknown {
                return .resultPending
            }
            return .retryable(message: mutationError.description)
        }
        return .retryable(message: ReaderErrorMessage.message(for: error))
    }
}

private struct UserProfileEditSheet: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let account: Account
    let profile: UserProfile
    let onApplied: (UserProfileEditRequest) -> Void
    let onNeedsRefresh: (UserProfileEditRequest) -> Void

    @State private var nickname: String
    @State private var introduction: String
    @State private var sex: UserProfileSex
    @State private var isSaving = false
    @State private var didSave = false
    @State private var resultPending = false
    @State private var pendingResultRequest: UserProfileEditRequest?
    @State private var errorMessage: String?
    @State private var pendingAccountSave: Account?

    init(
        account: Account,
        profile: UserProfile,
        onApplied: @escaping (UserProfileEditRequest) -> Void,
        onNeedsRefresh: @escaping (UserProfileEditRequest) -> Void
    ) {
        self.account = account
        self.profile = profile
        self.onApplied = onApplied
        self.onNeedsRefresh = onNeedsRefresh
        _nickname = State(initialValue: profile.user.displayNameResolved)
        _introduction = State(initialValue: profile.intro)
        _sex = State(initialValue: profile.sex)
    }

    var body: some View {
        NavigationStack {
            Group {
                if didSave {
                    successContent
                } else {
                    editForm
                }
            }
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { editorToolbar }
        }
        .interactiveDismissDisabled(isSaving)
        .accessibilityIdentifier("user-profile-edit-sheet")
    }

    private var editForm: some View {
        Form {
            Section("昵称") {
                TextField("请输入昵称", text: $nickname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("昵称")
                    .accessibilityIdentifier("user-profile-edit-nickname")
            }

            Section("个人简介") {
                TextEditor(text: $introduction)
                    .frame(minHeight: 112)
                    .accessibilityLabel("个人简介")
                    .accessibilityIdentifier("user-profile-edit-introduction")
            }

            Section("性别") {
                Picker("性别", selection: $sex) {
                    if profile.sex == .unspecified {
                        Text("未设置").tag(UserProfileSex.unspecified)
                    }
                    Text("男").tag(UserProfileSex.male)
                    Text("女").tag(UserProfileSex.female)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("user-profile-edit-sex")
            }

            if resultPending {
                Section {
                    Label(
                        "请求已经发出，但暂时无法确认是否修改成功。关闭后将只刷新资料，不会再次提交。",
                        systemImage: "questionmark.circle"
                    )
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("user-profile-edit-result-pending")
                }
            } else if let pendingAccountSave {
                Section {
                    Text(errorMessage ?? "贴吧资料已修改，但本机账号显示尚未更新。")
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await retryAccountSave(pendingAccountSave) }
                    } label: {
                        Label("重试本机保存", systemImage: "arrow.clockwise")
                    }
                    .disabled(isSaving)
                    .accessibilityHint("只更新本机账号显示，不会再次提交贴吧资料")
                    .accessibilityIdentifier("user-profile-edit-retry-local-save")
                }
            } else if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("user-profile-edit-error")
                }
            }

            if isSaving {
                Section {
                    HStack(spacing: TiebaPureTheme.Spacing.sm) {
                        ProgressView()
                        Text(pendingAccountSave == nil ? "正在保存资料" : "正在更新本机账号")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("正在保存个人资料")
                    .accessibilityIdentifier("user-profile-edit-loading")
                }
            }
        }
    }

    private var successContent: some View {
        CompatibleContentUnavailableView {
            Label("资料已更新", systemImage: "checkmark.circle.fill")
        } description: {
            Text("昵称、简介和性别已保存。")
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("user-profile-edit-success")
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if didSave == false {
                Button("取消", action: close)
                    .disabled(isSaving)
                    .accessibilityIdentifier("user-profile-edit-cancel")
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            if didSave {
                Button("完成", action: close)
                    .accessibilityIdentifier("user-profile-edit-done")
            } else if resultPending {
                Button("关闭并刷新", action: close)
                    .accessibilityIdentifier("user-profile-edit-refresh")
            } else if pendingAccountSave == nil {
                Button("保存") {
                    Task { await submit() }
                }
                .disabled(canSubmit == false)
                .accessibilityHint("提交昵称、简介和性别修改")
                .accessibilityIdentifier("user-profile-edit-save")
            }
        }
    }

    private var request: UserProfileEditRequest {
        UserProfileEditRequest(
            nickname: nickname,
            introduction: introduction,
            sex: sex
        )
    }

    private var canSubmit: Bool {
        guard isSaving == false,
              resultPending == false,
              pendingAccountSave == nil,
              request.normalizedNickname.isEmpty == false else {
            return false
        }
        return request != UserProfileEditRequest(
            nickname: profile.user.displayNameResolved,
            introduction: profile.intro,
            sex: profile.sex
        )
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        let submittedRequest = request
        isSaving = true
        errorMessage = nil

        do {
            try await environment.contentSubmissionCoordinator.performAccountWrite(
                account: account,
                target: .profile
            ) {
                try await environment.api.updateOwnProfile(
                    account: account,
                    request: submittedRequest
                )
            }
            try Task.checkCancellation()
            let updatedAccount = UserProfileManagementPolicy.updatedAccount(
                account,
                applying: submittedRequest
            )
            onApplied(submittedRequest)
            do {
                try await environment.accountStore.updateDisplayName(
                    updatedAccount.displayName,
                    forSession: account.sessionIdentity
                )
                didSave = true
            } catch let error as AccountStoreError where error == .sessionChanged {
                errorMessage = "账号状态已经变化，本机账号信息不会被旧页面覆盖。"
            } catch {
                pendingAccountSave = updatedAccount
                errorMessage = "贴吧资料已修改，但本机账号显示更新失败。可只重试本机保存。"
            }
        } catch {
            switch UserProfileMutationPresentationPolicy.failure(for: error) {
            case .resultPending:
                resultPending = true
                pendingResultRequest = submittedRequest
            case let .retryable(message):
                errorMessage = message
            }
        }
        isSaving = false
    }

    @MainActor
    private func retryAccountSave(_ updatedAccount: Account) async {
        guard isSaving == false else { return }
        isSaving = true
        errorMessage = nil
        do {
            try await environment.accountStore.updateDisplayName(
                updatedAccount.displayName,
                forSession: account.sessionIdentity
            )
            pendingAccountSave = nil
            didSave = true
        } catch let error as AccountStoreError where error == .sessionChanged {
            pendingAccountSave = nil
            errorMessage = "账号状态已经变化，本机账号信息不会被旧页面覆盖。"
        } catch {
            errorMessage = "本机账号显示仍未能更新，请稍后再试。贴吧资料不会重复提交。"
        }
        isSaving = false
    }

    private func close() {
        if let pendingResultRequest {
            onNeedsRefresh(pendingResultRequest)
        }
        dismiss()
    }
}

private struct UserProfileHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Environment(\.userProfileFollowAction) private var followAction

    let profile: UserProfile
    let onOpenRelationship: (UserRelationshipKind) -> Void
    let onEditProfile: (() -> Void)?

    private enum Layout {
        static let avatarSize: CGFloat = 56
        static let actionMinWidth: CGFloat = 80
    }

    private var identityMetadataItems: [String] {
        UserProfileMetadataText.items(for: profile, group: .identity)
    }

    private var detailMetadataItems: [String] {
        UserProfileMetadataText.items(for: profile, group: .details)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identityAndAction

            if profile.intro.isEmpty == false {
                Text(profile.intro)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityLabel("个人简介：\(profile.intro)")
                    .padding(.top, TiebaPureTheme.Spacing.sm)
            }

            if detailMetadataItems.isEmpty == false {
                ProfileMetadataView(
                    items: detailMetadataItems,
                    accessibilityIdentifier: "user-profile-secondary-metadata"
                )
                .padding(.top, profile.intro.isEmpty ? TiebaPureTheme.Spacing.sm : TiebaPureTheme.Spacing.xxs)
            }

            Divider()
                .padding(.top, TiebaPureTheme.Spacing.sm)

            profileStats
        }
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.top, TiebaPureTheme.Spacing.sm)
        .padding(.bottom, TiebaPureTheme.Spacing.xxs)
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private var identityAndAction: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
                HStack(alignment: .top, spacing: TiebaPureTheme.Spacing.sm) {
                    profileAvatar
                    identitySummary
                }

                if showsProfileAction {
                    profileAction
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        } else {
            HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.sm) {
                profileAvatar
                identitySummary
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                if showsProfileAction {
                    profileAction
                }
            }
        }
    }

    private var profileAvatar: some View {
        AvatarView(
            url: profile.user.portraitURL,
            title: profile.user.displayNameResolved,
            size: Layout.avatarSize
        )
        .accessibilityIdentifier("user-profile-avatar")
    }

    private var identitySummary: some View {
        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.xs) {
                    profileName
                    levelBadge
                }
                VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                    profileName
                    levelBadge
                }
            }

            if identityMetadataItems.isEmpty == false {
                ProfileMetadataView(
                    items: identityMetadataItems,
                    accessibilityIdentifier: "user-profile-metadata"
                )
            }
        }
    }

    private var showsProfileAction: Bool {
        onEditProfile != nil || profile.isCurrentUser == false
    }

    @ViewBuilder
    private var profileStats: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TiebaPureTheme.Spacing.md) {
                profileStatViews
            }
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                profileStatViews
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var profileStatViews: some View {
        ProfileStat(value: profile.agreeCount, label: "获赞")
        ProfileStat(value: profile.followingCount, label: "关注") {
            onOpenRelationship(.following)
        }
        ProfileStat(value: profile.followerCount, label: "粉丝") {
            onOpenRelationship(.followers)
        }
    }

    @ViewBuilder
    private var profileAction: some View {
        if let onEditProfile {
            editProfileButton(action: onEditProfile)
        } else if profile.isCurrentUser == false {
            followButton
        }
    }

    private var profileName: some View {
        Text(profile.user.displayNameResolved)
            .font(.title2.weight(.bold))
            .foregroundStyle(.primary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .textSelection(.enabled)
            .accessibilityIdentifier("user-profile-name")
    }

    private var followButton: some View {
        Button {
            followAction.toggle()
        } label: {
            Group {
                if followAction.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    if profile.isFollowed {
                        Label("已关注", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        HStack(spacing: TiebaPureTheme.Spacing.xxs) {
                            Image(systemName: "plus")
                                .foregroundStyle(TiebaPureTheme.ColorToken.primaryAccent)
                            Text("关注")
                                .foregroundStyle(.primary)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .frame(minWidth: Layout.actionMinWidth, minHeight: 44)
            .padding(.horizontal, TiebaPureTheme.Spacing.xxs)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
        .background(
            profile.isFollowed
                ? TiebaPureTheme.ColorToken.readerSecondarySurface
                : TiebaPureTheme.ColorToken.primaryAccent.opacity(0.12),
            in: RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.card, style: .continuous)
        )
        .disabled(followAction.isUpdating)
        .opacity(followAction.isUpdating ? 0.65 : 1)
        .accessibilityLabel(profile.isFollowed ? "取消关注" : "关注用户")
        .accessibilityHint(profile.isFollowed ? "停止关注该用户" : "关注该用户")
        .accessibilityIdentifier("user-profile-follow-button")
    }

    private func editProfileButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: TiebaPureTheme.Spacing.xxs) {
                Image(systemName: "pencil")
                    .foregroundStyle(TiebaPureTheme.ColorToken.primaryAccent)
                Text("编辑资料")
                    .foregroundStyle(.primary)
            }
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 96, minHeight: 44)
                .padding(.horizontal, TiebaPureTheme.Spacing.xxs)
        }
        .buttonStyle(.plain)
        .background(
            TiebaPureTheme.ColorToken.primaryAccent.opacity(0.12),
            in: RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.card, style: .continuous)
        )
        .accessibilityLabel("编辑个人资料")
        .accessibilityHint("修改昵称、简介和性别")
        .accessibilityIdentifier("user-profile-edit-button")
    }

    @ViewBuilder
    private var levelBadge: some View {
        if let level = profile.user.level, level > 0 {
            Text("Lv.\(level)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.orange.opacity(0.18))
                )
                .accessibilityLabel("用户等级\(level)")
        }
    }
}

enum UserProfileMetadataGroup {
    case identity
    case details
}

enum UserProfileMetadataText {
    static func items(for profile: UserProfile, group: UserProfileMetadataGroup) -> [String] {
        var result: [String] = []
        switch group {
        case .identity:
            if profile.sex != .unspecified {
                result.append(profile.sex.accessibilityText)
            }
            if profile.tiebaID.isEmpty == false {
                result.append("ID \(profile.tiebaID)")
            }
        case .details:
            if profile.tiebaAge.isEmpty == false {
                result.append("吧龄 \(profile.tiebaAge)")
            }
            if let location = ThreadPostMetadataText.normalizedLocation(profile.location) {
                result.append("IP属地 \(location)")
            }
        }
        return result
    }
}

private struct ProfileMetadataView: View {
    let items: [String]
    let accessibilityIdentifier: String

    var body: some View {
        Text(items.joined(separator: "  ·  "))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(items.joined(separator: "，"))
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct ProfileStat: View {
    let value: Int
    let label: String
    var action: (() -> Void)?

    init(value: Int, label: String, action: (() -> Void)? = nil) {
        self.value = value
        self.label = label
        self.action = action
    }

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .accessibilityLabel("\(label)\(value)")
                .accessibilityHint("查看用户列表")
                .accessibilityIdentifier("user-profile-\(identifierComponent)-stat")
        } else {
            content
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(label)\(value)")
                .accessibilityIdentifier("user-profile-\(identifierComponent)-stat")
        }
    }

    private var content: some View {
        HStack(alignment: .firstTextBaseline, spacing: TiebaPureTheme.Spacing.xxs) {
            Text(UserProfileCountText.string(value))
                .font(.body.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var identifierComponent: String {
        switch label {
        case "关注": "following"
        case "粉丝": "followers"
        default: "agree"
        }
    }
}

private struct UserProfileTabBar: View {
    @Binding var selectedTab: UserProfileTab
    let threadCount: Int
    let followedForumCount: Int

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.threads, title: "帖子 \(threadCount)")
            tabButton(.followedForums, title: "关注的吧 \(followedForumCount)")
        }
        .background(TiebaPureTheme.ColorToken.readerSectionBand)
        .overlay(alignment: .bottom) { Divider() }
    }

    private func tabButton(_ tab: UserProfileTab, title: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 0) {
                Text(title)
                    .font(.body.weight(selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? Color.primary : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)

                Capsule()
                    .fill(selectedTab == tab ? TiebaPureTheme.ColorToken.primaryAccent : Color.clear)
                    .frame(width: 38, height: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityIdentifier(tab == .threads ? "user-profile-posts-tab" : "user-profile-forums-tab")
    }
}

private struct UserProfilePrivateState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: TiebaPureTheme.Spacing.sm) {
            Image(systemName: "lock.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(TiebaPureTheme.Spacing.lg)
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .combine)
    }
}

enum UserProfileCountText {
    static func string(_ value: Int) -> String {
        let safeValue = max(value, 0)
        guard safeValue >= 10_000 else { return "\(safeValue)" }
        let integerPart = safeValue / 10_000
        let decimalPart = safeValue % 10_000 / 1_000
        return decimalPart == 0 ? "\(integerPart)万" : "\(integerPart).\(decimalPart)万"
    }
}
