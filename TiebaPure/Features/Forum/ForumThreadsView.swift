import SwiftUI

struct ForumThreadsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let account: Account?
    let forum: Forum

    @State private var threads: [ThreadSummary] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var activeSearch: ForumSearchLaunchRoute?
    @State private var requestGeneration = 0
    @State private var loadTask: Task<[ThreadSummary], Error>?

    private var visibleThreads: [ThreadSummary] {
        threads
    }

    var body: some View {
        Group {
            if isLoading && didLoad == false {
                ReaderStateView.loading("正在加载帖子")
            } else if let errorMessage, threads.isEmpty {
                ReaderStateView.error(message: errorMessage) {
                    Task { await reload() }
                }
            } else if visibleThreads.isEmpty {
                ReaderStateView.empty(
                    title: searchText.isEmpty ? "暂无帖子" : "没有匹配结果",
                    message: searchText.isEmpty ? "下拉即可刷新本吧帖子。" : nil
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleThreads.enumerated()), id: \.element.id) { index, thread in
                            NavigationLink {
                                ThreadDetailView(
                                    account: account,
                                    threadID: thread.id,
                                    forumID: thread.forumID ?? forum.id
                                )
                            } label: {
                                ForumThreadRow(thread: thread, showsForumInfo: false)
                            }
                            .buttonStyle(.plain)
                                .onAppear {
                                    guard searchText.isEmpty,
                                          PaginationPrefetchPolicy.shouldLoadMore(
                                            currentIndex: index,
                                            totalCount: threads.count
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
        .navigationTitle(forum.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "搜索本吧帖子或回复")
        .onSubmit(of: .search) {
            launchSearch(.keyboardSubmit)
        }
        .navigationDestination(isPresented: searchIsActive) {
            if let activeSearch {
                SearchResultsView(account: account, scope: activeSearch.scope, initialKeyword: activeSearch.keyword)
            }
        }
        .refreshable { await reload() }
        .task {
            RecentForumStore.shared.save(forum)
            guard didLoad == false else { return }
            await reload()
        }
        .onChange(of: account?.id) { _ in
            loadTask?.cancel()
            requestGeneration += 1
            threads = []
            page = 1
            hasMore = true
            isLoading = false
            didLoad = false
            errorMessage = nil
            Task { await reload() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    launchSearch(.toolbarButton)
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("搜索本吧")

                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityLabel("刷新")
            }
        }
        .onDisappear {
            loadTask?.cancel()
            requestGeneration += 1
            isLoading = false
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

    private func reload() async {
        loadTask?.cancel()
        requestGeneration += 1
        isLoading = false
        page = 1
        hasMore = true
        errorMessage = nil
        if threads.isEmpty {
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
        isLoading = true
        errorMessage = nil

        do {
            let requestedPage = page
            let task = Task {
                try await environment.api.forumThreads(account: account, forumName: forum.name, page: requestedPage)
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
    }

    private func launchSearch(_ trigger: ForumSearchLaunchTrigger) {
        activeSearch = ForumSearchLaunchPolicy.route(
            for: trigger,
            currentText: searchText,
            forum: forum
        )
    }
}

struct ForumSearchLaunchRoute: Equatable {
    let keyword: String
    let scope: SearchScope
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

        var showsDivider: Bool {
            switch self {
            case .list:
                return true
            case .homeFeed:
                return false
            }
        }

        var cardRadius: CGFloat {
            switch self {
            case .list:
                return 0
            case .homeFeed:
                return TiebaPureTheme.Radius.card
            }
        }

        func mediaLimit(totalCount: Int) -> Int? {
            switch self {
            case .list, .homeFeed:
                return TiebaLiteMediaLayoutPolicy.visibleItemCount(totalCount: totalCount)
            }
        }

        var usesTiebaLiteMediaLayout: Bool {
            switch self {
            case .list, .homeFeed:
                return true
            }
        }

        func mediaMaxHeight(itemCount: Int) -> CGFloat? {
            switch self {
            case .list:
                return nil
            case .homeFeed:
                return itemCount == 1 ? 180 : 118
            }
        }

    }

    let thread: ThreadSummary
    var showsForumInfo = true
    var presentation: Presentation = .list
    var highlightKeyword: String?
    var onOpenThread: (() -> Void)?
    var onOpenForum: ((Forum) -> Void)?
    var onOpenMedia: ((ReaderMediaItem, [ReaderMediaItem]) -> Void)?

    var body: some View {
        ReaderCard(showsDivider: presentation.showsDivider, cornerRadius: presentation.cardRadius) {
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
                if showsForumInfo, let forum = thread.forumRoute {
                    ForumInfoHeader(thread: thread, forum: forum, onOpenForum: onOpenForum)
                } else {
                    AuthorHeader(thread: thread)
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
                        usesTiebaLiteLayout: presentation.usesTiebaLiteMediaLayout,
                        isInteractive: onOpenMedia != nil,
                        onTap: { item in
                            guard ForumThreadTapPolicy.destination(for: .media) == .media else { return }
                            onOpenMedia?(item, allMedia)
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
                        lineLimit: 2
                    )
                } else if inlinePreviewBlocks.isEmpty == false {
                    InlineContentText(
                        blocks: inlinePreviewBlocks,
                        style: .body,
                        lineLimit: 2,
                        highlightKeyword: highlightKeyword,
                        allowsLinkInteraction: false
                    )
                }

                if thread.title.isEmpty == false, inlinePreviewBlocks.isEmpty == false {
                    InlineContentText(
                        blocks: inlinePreviewBlocks,
                        style: .preview,
                        lineLimit: 2,
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
                .accessibilityIdentifier("thread-open-area")
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

    private func mediaPreviewItems(from mediaItems: [ReaderMediaItem]) -> [ReaderMediaItem] {
        guard let limit = presentation.mediaLimit(totalCount: mediaItems.count) else {
            return mediaItems
        }
        return Array(mediaItems.prefix(limit))
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
    case threadBody
    case media
    case stats
}

enum ForumThreadTapDestination: Equatable {
    case forum
    case thread
    case media
    case none
}

enum ForumThreadTapPolicy {
    static func destination(for target: ForumThreadTapTarget) -> ForumThreadTapDestination {
        switch target {
        case .forumIdentity:
            return .forum
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

    var body: some View {
        if let onOpenForum {
            Button {
                guard ForumThreadTapPolicy.destination(for: .forumIdentity) == .forum else { return }
                onOpenForum(forum)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .frame(minHeight: 44)
            .accessibilityLabel("进入\(forum.displayName)")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.sm) {
            AvatarView(url: forum.avatarURL, title: forum.displayName, size: TiebaPureTheme.AvatarSize.small)

            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                Text(forum.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                MetadataLine(
                    [
                        thread.author.displayNameResolved,
                        thread.lastReplyAt.map { ReaderDateText.string(from: $0) } ?? ""
                    ],
                    systemImage: nil
                )
            }
        }
    }
}

private struct AuthorHeader: View {
    let thread: ThreadSummary

    var body: some View {
        HStack(alignment: .top, spacing: TiebaPureTheme.Spacing.sm) {
            AvatarView(url: thread.author.portraitURL, title: thread.author.displayNameResolved, size: TiebaPureTheme.AvatarSize.small)

            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                Text(thread.author.displayNameResolved)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)

                MetadataLine(
                    [
                        thread.lastReplyAt.map { ReaderDateText.string(from: $0) } ?? ""
                    ],
                    systemImage: "bubble.left.and.text.bubble.right"
                )
            }
        }
    }
}
