import SwiftUI

/// The thread feed behind one 话题榜 row.
///
/// The service pages this feed by cursor, so "load more" carries the previous
/// page's last feed id instead of a page number — asking with a bare page number
/// answers error 300000.
struct TopicDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @ObservedObject private var blocklistStore = BlocklistStore.shared

    let account: Account?
    let topicID: Int64
    let topicName: String
    let openThread: (ThreadSummary) -> Void
    let openComments: (ThreadSummary) -> Void
    let openForum: (Forum) -> Void
    let openUser: (UserSummary) -> Void

    @State private var info: TopicInfo?
    @State private var threads: [ThreadSummary] = []
    @State private var nextCursor = ""
    @State private var page = 1
    @State private var hasMore = false
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var requestGeneration = 0
    @State private var loadTask: Task<TopicThreadPage, Error>?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: TiebaPureTheme.Spacing.sm, pinnedViews: []) {
                if let info {
                    header(info)
                }

                ForEach(threads) { thread in
                    ForumThreadRow(
                        thread: thread,
                        presentation: .homeFeed,
                        onOpenThread: { openThread(thread) },
                        onOpenForum: openForum,
                        onOpenUser: { openUser($0) },
                        onBlockForum: { blockedThread in
                            blocklistStore.addForum(
                                id: blockedThread.forumID,
                                named: blockedThread.forumName
                            )
                        },
                        // The topic payload carries images but no video payload,
                        // so a media tap opens the thread rather than a viewer.
                        onOpenMedia: { _, _, _, _, _ in openThread(thread) },
                        onOpenComments: { openComments(thread) },
                        commentsAccessibilityIdentifier: "topic-comments-button-\(thread.id)"
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("topic-thread-row")
                }

                if hasMore, errorMessage == nil {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task { await loadMore() }
                        }
                        .accessibilityHidden(true)
                }

                if let errorMessage {
                    InlineLoadErrorView(message: errorMessage) {
                        Task { await loadMore() }
                    }
                }

                Color.clear
                    .frame(height: 64)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, TiebaPureTheme.Spacing.sm)
            .padding(.vertical, TiebaPureTheme.Spacing.sm)
            .readableWidth()
        }
        .accessibilityIdentifier("topic-thread-scroll-view")
        .overlay {
            if threads.isEmpty, isLoading {
                ReaderStateView.loading("正在加载话题")
            } else if threads.isEmpty, let errorMessage {
                ReaderStateView.error(message: errorMessage) {
                    Task { await refresh() }
                }
            } else if threads.isEmpty, didLoad {
                ReaderStateView.empty(
                    title: "这个话题还没有帖子",
                    message: "下拉即可刷新。"
                )
            }
        }
        .shortPullRefresh(
            isEnabled: isLoading == false,
            surface: .grouped,
            accessibilityIdentifier: "topic-refresh-animation"
        ) {
            await refresh()
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard didLoad == false else { return }
            await load(cursor: "", page: 1, replacing: true)
        }
        .onChange(of: account?.sessionIdentity) { _ in
            requestGeneration += 1
            loadTask?.cancel()
            info = nil
            threads = []
            nextCursor = ""
            page = 1
            hasMore = false
            errorMessage = nil
            didLoad = false
            isLoading = false
        }
        .onDisappear {
            loadTask?.cancel()
            requestGeneration += 1
            isLoading = false
        }
    }

    private var navigationTitle: String {
        let name = info?.name.isEmpty == false ? info?.name : topicName
        guard let name, name.isEmpty == false else { return "话题" }
        return "#\(name)"
    }

    private func header(_ info: TopicInfo) -> some View {
        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
            Text("#\(info.name)")
                .font(.headline)
                .foregroundStyle(.primary)

            if info.summary.isEmpty == false {
                Text(info.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: TiebaPureTheme.Spacing.md) {
                Text("讨论 \(info.discussCountText)")
                Text("浏览 \(info.browseCountText)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(TiebaPureTheme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.card, style: .continuous)
                .fill(TiebaPureTheme.ColorToken.readerSecondarySurface)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("topic-header")
    }

    private func refresh() async {
        await load(cursor: "", page: 1, replacing: true)
    }

    private func loadMore() async {
        guard hasMore, isLoading == false, didLoad, nextCursor.isEmpty == false else { return }
        await load(cursor: nextCursor, page: page + 1, replacing: false)
    }

    private func load(cursor: String, page requestedPage: Int, replacing: Bool) async {
        loadTask?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        let requestedSession = account?.sessionIdentity
        isLoading = true
        errorMessage = nil

        do {
            let task = Task {
                try await environment.api.topicThreads(
                    account: account,
                    topicID: topicID,
                    topicName: topicName,
                    cursor: cursor,
                    page: requestedPage,
                    pageSize: TopicPagePolicy.pageSize
                )
            }
            loadTask = task
            let pageResult = try await task.value
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity else { return }
            if let header = pageResult.info {
                info = header
            }
            if replacing {
                threads = pageResult.threads
            } else {
                // A cursor page can repeat a row the previous page already
                // showed, and duplicate identities break list diffing.
                let existing = Set(threads.map(\.id))
                threads.append(contentsOf: pageResult.threads.filter { existing.contains($0.id) == false })
            }
            hasMore = pageResult.hasMore
            nextCursor = pageResult.nextCursor
            page = requestedPage
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            loadTask = nil
            isLoading = false
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
    }
}
