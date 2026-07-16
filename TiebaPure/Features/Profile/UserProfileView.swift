import SwiftUI

private enum UserProfileTab: String, CaseIterable {
    case threads
    case followedForums
}

private struct UserProfileThreadRoute {
    let threadID: Int64
    let forumID: Int64?
}

struct UserProfileView: View {
    @EnvironmentObject private var environment: AppEnvironment

    let account: Account?
    let user: UserSummary

    @State private var profile: UserProfile?
    @State private var threads: [ThreadSummary] = []
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
    @State private var followTask: Task<Void, Error>?
    @State private var isUpdatingFollow = false
    @State private var userActionError: String?
    @State private var selectedThread: UserProfileThreadRoute?
    @State private var selectedForum: Forum?
    @State private var selectedImagePreview: ImagePreviewSession?
    @State private var selectedVideoPreview: HomeVideoPreview?

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
        .alert("提示", isPresented: userActionErrorIsPresented) {
            Button("好", role: .cancel) {
                userActionError = nil
            }
        } message: {
            Text(userActionError ?? "")
        }
        .navigationDestination(isPresented: threadIsActive) {
            if let selectedThread {
                ThreadDetailView(
                    account: account,
                    threadID: selectedThread.threadID,
                    forumID: selectedThread.forumID
                )
            }
        }
        .navigationDestination(isPresented: forumIsActive) {
            if let selectedForum {
                ForumThreadsView(account: account, forum: selectedForum)
            }
        }
        .task {
            guard didLoad == false else { return }
            await reload()
        }
        .onChange(of: account?.id) { _ in
            cancelRequests()
            requestGeneration += 1
            profile = nil
            threads = []
            nextPage = 1
            hasMoreThreads = true
            threadsVisibility = .visible
            profileError = nil
            threadsError = nil
            userActionError = nil
            isUpdatingFollow = false
            didLoad = false
            selectedThread = nil
            selectedForum = nil
            Task { await reload() }
        }
        .onDisappear {
            cancelRequests()
            requestGeneration += 1
            isLoadingProfile = false
            isLoadingThreads = false
        }
        .fullScreenCover(item: $selectedImagePreview) { preview in
            FullScreenImageView(session: preview)
        }
        .fullScreenCover(item: $selectedVideoPreview) { preview in
            DirectVideoPlaybackView(video: preview.video)
        }
        .accessibilityIdentifier("user-profile-screen")
        .fullScreenInteractiveNavigationPop()
    }

    private func profileScrollView(_ profile: UserProfile) -> some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                UserProfileHeader(profile: profile)
                    .environment(\.userProfileFollowAction, UserProfileFollowAction(
                        isUpdating: isUpdatingFollow,
                        toggle: { toggleFollow(profile) }
                    ))

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
        .refreshable { await reload() }
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
            ReaderStateView.empty(title: "暂未发布帖子", message: "这里还没有可公开查看的帖子。")
                .frame(minHeight: 220)
                .background(Color(uiColor: .systemBackground))
        } else {
            LazyVStack(spacing: TiebaPureTheme.Spacing.sm) {
                ForEach(Array(threads.enumerated()), id: \.element.id) { index, thread in
                    ForumThreadRow(
                        thread: thread,
                        presentation: .userProfile,
                        onOpenThread: {
                            selectedThread = UserProfileThreadRoute(
                                threadID: thread.id,
                                forumID: thread.forumID
                            )
                        },
                        onOpenForum: { forum in
                            RecentForumStore.shared.save(forum)
                            selectedForum = forum
                        },
                        onOpenMedia: { item, mediaItems in
                            switch HomeMediaActionPolicy.action(for: item, in: mediaItems) {
                            case let .previewImages(images, index):
                                selectedImagePreview = ImagePreviewSession(images: images, initialIndex: index)
                            case let .playVideo(video):
                                selectedVideoPreview = HomeVideoPreview(video: video)
                            case .openThread:
                                selectedThread = UserProfileThreadRoute(
                                    threadID: thread.id,
                                    forumID: thread.forumID
                                )
                            }
                        }
                    )
                    .onAppear {
                        guard PaginationPrefetchPolicy.shouldLoadMore(
                            currentIndex: index,
                            totalCount: threads.count
                        ) else { return }
                        Task { await loadMoreThreads() }
                    }
                    .accessibilityIdentifier("user-profile-thread-row")
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
                }
            }
            .padding(.horizontal, TiebaPureTheme.Spacing.sm)
            .padding(.vertical, TiebaPureTheme.Spacing.sm)
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
                        selectedForum = forum
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
        let requestedAccountID = account?.id
        isLoadingProfile = true
        profileError = nil
        threadsError = nil

        do {
            let task = Task {
                try await environment.api.userProfile(account: account, user: user)
            }
            profileTask = task
            let loadedProfile = try await task.value
            guard generation == requestGeneration, requestedAccountID == account?.id else { return }
            profile = loadedProfile
            profileTask = nil
            isLoadingProfile = false
            await reloadThreads(generation: generation, userID: loadedProfile.user.id)
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            profileTask = nil
            isLoadingProfile = false
        } catch {
            guard generation == requestGeneration, requestedAccountID == account?.id else { return }
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

    private func loadThreads(generation: Int, userID: Int64, replacing: Bool) async {
        guard isLoadingThreads == false, hasMoreThreads else { return }
        let requestedAccountID = account?.id
        let requestedPage = replacing ? 1 : nextPage
        isLoadingThreads = true
        threadsError = nil

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
            guard generation == requestGeneration, requestedAccountID == account?.id else { return }
            threadsVisibility = page.visibility
            if replacing {
                threads = page.threads
            } else {
                threads = HomeFeedMerge.append(existing: threads, incoming: page.threads)
            }
            hasMoreThreads = page.visibility == .visible && page.hasMore
            nextPage = page.currentPage + 1
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            threadsTask = nil
            isLoadingThreads = false
            return
        } catch {
            guard generation == requestGeneration, requestedAccountID == account?.id else { return }
            threadsError = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration else { return }
        threadsTask = nil
        isLoadingThreads = false
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
            try await environment.api.setUserFollowed(
                account: account,
                user: displayedProfile.user,
                followed: targetState
            )
        }
        followTask = task

        Task {
            do {
                try await task.value
                guard generation == requestGeneration else { return }
                if profile?.isFollowed != targetState {
                    profile?.isFollowed = targetState
                    let delta = targetState ? 1 : -1
                    profile?.followerCount = max((profile?.followerCount ?? 0) + delta, 0)
                }
                followTask = nil
                isUpdatingFollow = false
            } catch is CancellationError {
                guard generation == requestGeneration else { return }
                followTask = nil
                isUpdatingFollow = false
            } catch {
                guard generation == requestGeneration else { return }
                followTask = nil
                isUpdatingFollow = false
                userActionError = ReaderErrorMessage.message(for: error)
            }
        }
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

private struct UserProfileHeader: View {
    @Environment(\.userProfileFollowAction) private var followAction

    let profile: UserProfile

    private enum Layout {
        static let coverHeight: CGFloat = 112
        static let avatarSize: CGFloat = 96
        static let overlap: CGFloat = 44
        static let actionBandHeight = overlap + TiebaPureTheme.Spacing.sm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                profileBackground
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.coverHeight)
                    .clipped()
                    .overlay(alignment: .bottom) {
                        LinearGradient(
                            colors: [.clear, Color.black.opacity(0.12)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .allowsHitTesting(false)
                    }
                    .accessibilityHidden(true)

                AvatarView(
                    url: profile.user.portraitURL,
                    title: profile.user.displayNameResolved,
                    size: Layout.avatarSize
                )
                .overlay {
                    Circle()
                        .stroke(Color(uiColor: .systemBackground), lineWidth: 4)
                }
                .padding(.leading, TiebaPureTheme.Spacing.md)
                .offset(y: Layout.overlap)

            }
            .frame(height: Layout.coverHeight)

            HStack {
                Spacer(minLength: Layout.avatarSize + TiebaPureTheme.Spacing.lg)
                if profile.isCurrentUser == false {
                    followButton
                }
            }
            .frame(maxWidth: .infinity, minHeight: Layout.actionBandHeight)
            .padding(.horizontal, TiebaPureTheme.Spacing.md)

            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.xs) {
                        profileName
                        levelBadge
                    }
                    VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
                        profileName
                        levelBadge
                    }
                }

                ProfileMetadataView(profile: profile)

                if profile.intro.isEmpty == false {
                    Text(profile.intro)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .accessibilityLabel("个人简介：\(profile.intro)")
                }

                HStack(spacing: 0) {
                    ProfileStat(value: profile.agreeCount, label: "获赞")
                    ProfileStat(value: profile.followingCount, label: "关注")
                    ProfileStat(value: profile.followerCount, label: "粉丝")
                }
                .padding(.top, TiebaPureTheme.Spacing.xs)
            }
            .padding(.horizontal, TiebaPureTheme.Spacing.md)
            .padding(.bottom, TiebaPureTheme.Spacing.sm)
        }
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder
    private var profileBackground: some View {
        if let backgroundURL = profile.backgroundURL {
            TiebaRemoteImage(
                primaryURL: backgroundURL,
                contentMode: .fill,
                showsProgress: false,
                showsRetryButton: false
            )
        } else {
            ZStack {
                TiebaPureTheme.ColorToken.readerSecondarySurface
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
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
            HStack(spacing: TiebaPureTheme.Spacing.xs) {
                if followAction.isUpdating {
                    ProgressView()
                        .controlSize(.small)
                        .tint(profile.isFollowed ? .primary : .white)
                } else if profile.isFollowed == false {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .accessibilityHidden(true)
                }

                Text(profile.isFollowed ? "已关注" : "关注")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(profile.isFollowed ? Color.primary : Color.white)
            .frame(minWidth: 96, minHeight: 44)
            .padding(.horizontal, TiebaPureTheme.Spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(profile.isFollowed
                        ? TiebaPureTheme.ColorToken.readerSecondarySurface
                        : TiebaPureTheme.ColorToken.primaryAccent)
            )
            .overlay {
                if profile.isFollowed {
                    Capsule(style: .continuous)
                        .stroke(TiebaPureTheme.ColorToken.readerSeparator, lineWidth: 0.5)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(followAction.isUpdating)
        .accessibilityLabel(profile.isFollowed ? "取消关注" : "关注用户")
        .accessibilityHint(profile.isFollowed ? "停止关注该用户" : "关注该用户")
        .accessibilityIdentifier("user-profile-follow-button")
    }

    @ViewBuilder
    private var levelBadge: some View {
        if let level = profile.user.level, level > 0 {
            Text("Lv.\(level)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
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

private struct ProfileMetadataView: View {
    let profile: UserProfile

    private var items: [String] {
        var result: [String] = []
        if profile.sex != .unspecified {
            result.append(profile.sex.accessibilityText)
        }
        if profile.tiebaID.isEmpty == false {
            result.append("ID \(profile.tiebaID)")
        }
        if profile.tiebaAge.isEmpty == false {
            result.append("吧龄 \(profile.tiebaAge)")
        }
        if let location = ThreadPostMetadataText.normalizedLocation(profile.location) {
            result.append("IP属地 \(location)")
        }
        return result
    }

    var body: some View {
        Text(items.joined(separator: "  ·  "))
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(items.joined(separator: "，"))
        .accessibilityIdentifier("user-profile-metadata")
    }
}

private struct ProfileStat: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
            Text(UserProfileCountText.string(value))
                .font(.title3.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label)\(value)")
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
        .background(Color(uiColor: .systemBackground))
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
