import SwiftUI

struct MessagesView: View {
    @EnvironmentObject private var environment: AppEnvironment

    let account: Account?

    @ObservedObject private var blocklistStore = BlocklistStore.shared
    @State private var kind: MessageKind = .reply
    @State private var items: [MessageItem] = []
    @State private var nextPage = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var requestGeneration = 0
    @State private var loadTask: Task<MessagesPage, Error>?
    @State private var activeMessage: MessageItem?

    var body: some View {
        VStack(spacing: 0) {
            if account != nil {
                kindPicker
                    .readableWidth()
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .navigationTitle("消息")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestinationCompat(isPresented: messageIsActive) {
            if let activeMessage {
                ThreadDetailView(
                    account: account,
                    threadID: activeMessage.threadID,
                    initialPostID: activeMessage.postID
                )
                .interactiveNavigationPopStateSync {
                    self.activeMessage = nil
                }
            }
        }
        .task {
            guard didLoad == false else { return }
            await reload()
        }
        .onChange(of: kind) { _ in
            resetForNewRequestScope()
            Task { await reload() }
        }
        .onChange(of: account?.sessionIdentity) { _ in
            activeMessage = nil
            resetForNewRequestScope()
            Task { await reload() }
        }
        .onChange(of: blocklistStore.entries) { _ in
            items.removeAll { TiebaContentFilter.shouldKeep(message: $0) == false }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
            requestGeneration += 1
            isLoading = false
        }
        .accessibilityIdentifier("messages-screen")
        .fullScreenInteractiveNavigationPop()
    }

    private var kindPicker: some View {
        Picker("消息类型", selection: $kind) {
            Text("回复我的").tag(MessageKind.reply)
            Text("@我的").tag(MessageKind.at)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 320)
        .frame(minHeight: 44)
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.vertical, TiebaPureTheme.Spacing.xs)
        .accessibilityIdentifier("messages-kind-picker")
    }

    @ViewBuilder
    private var content: some View {
        if account == nil {
            ReaderStateView(
                kind: .empty,
                title: "登录后查看消息",
                message: "登录后可以在这里查看回复我的和@我的消息。",
                systemImage: "person.crop.circle.badge.exclamationmark"
            )
            .accessibilityIdentifier("messages-login-prompt")
        } else if isLoading, didLoad == false {
            ReaderStateView.loading("正在加载消息")
        } else if let errorMessage, items.isEmpty {
            ReaderStateScrollView(refresh: { await reload() }) {
                ReaderStateView.error(message: errorMessage) {
                    Task { await reload() }
                }
            }
        } else if items.isEmpty {
            ReaderStateScrollView(refresh: { await reload() }) {
                ReaderStateView.empty(
                    title: emptyTitle,
                    message: emptyMessage,
                    actionTitle: hasMore ? "继续加载" : nil,
                    action: hasMore ? { Task { await loadMore() } } : nil
                )
            }
        } else {
            messageList
        }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, message in
                    ReaderCard(action: { activeMessage = message }) {
                        MessageRow(message: message)
                    }
                    .accessibilityHint("打开该帖子并定位到相关楼层")
                    .accessibilityIdentifier("message-row-\(message.id)")
                    .onAppear {
                        guard PaginationPrefetchPolicy.shouldLoadMore(
                            currentIndex: index,
                            totalCount: items.count
                        ) else { return }
                        Task { await loadMore() }
                    }
                }

                if isLoading, didLoad {
                    ProgressView()
                        .padding(TiebaPureTheme.Spacing.md)
                        .accessibilityLabel("正在加载更多消息")
                }

                if let errorMessage {
                    InlineLoadErrorView(message: errorMessage) {
                        Task { await loadMore() }
                    }
                } else if hasMore, isLoading == false, didLoad {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        Label("加载更多消息", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .minTouchTarget()
                    .padding(.horizontal, TiebaPureTheme.Spacing.md)
                    .accessibilityIdentifier("messages-load-more")
                } else if hasMore == false {
                    Text("已显示全部消息")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(TiebaPureTheme.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityLabel("已显示全部消息")
                }

                Color.clear
                    .frame(height: 32)
                    .accessibilityHidden(true)
            }
            .readableWidth()
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .accessibilityIdentifier("messages-list")
        .shortPullRefresh(
            isEnabled: didLoad && isLoading == false,
            surface: .grouped,
            accessibilityIdentifier: "messages-refresh-animation"
        ) {
            await reload()
        }
    }

    private var emptyTitle: String {
        kind == .reply ? "还没有收到回复" : "还没有人@我"
    }

    private var emptyMessage: String {
        kind == .reply
            ? "别人回复你的帖子或楼层后会显示在这里。"
            : "别人在帖子里@你后会显示在这里。"
    }

    private var messageIsActive: Binding<Bool> {
        Binding(
            get: { activeMessage != nil },
            set: { isActive in
                if isActive == false {
                    activeMessage = nil
                }
            }
        )
    }

    private func resetForNewRequestScope() {
        loadTask?.cancel()
        loadTask = nil
        requestGeneration += 1
        items = []
        nextPage = 1
        hasMore = true
        isLoading = false
        didLoad = false
        errorMessage = nil
    }

    private func reload() async {
        guard account != nil else { return }
        loadTask?.cancel()
        requestGeneration += 1
        isLoading = false
        nextPage = 1
        hasMore = true
        errorMessage = nil
        await loadMore(generation: requestGeneration, replacing: true)
    }

    private func loadMore() async {
        await loadMore(generation: requestGeneration, replacing: false)
    }

    private func loadMore(
        generation: Int,
        replacing: Bool,
        consecutiveHiddenPageCount: Int = 0
    ) async {
        guard let account else { return }
        guard isLoading == false, hasMore || replacing else { return }
        let requestedSession = account.sessionIdentity
        let requestedKind = kind
        let requestedPage = replacing ? 1 : nextPage
        isLoading = true
        errorMessage = nil
        var continuation: LocallyFilteredPaginationDecision?

        do {
            let task = Task {
                try await environment.api.messages(
                    account: account,
                    kind: requestedKind,
                    page: requestedPage
                )
            }
            loadTask = task
            let page = try await task.value
            guard generation == requestGeneration,
                  requestedSession == self.account?.sessionIdentity else { return }
            let visibleItems = page.items.filter(TiebaContentFilter.shouldKeep(message:))
            if replacing {
                items = deduplicated(visibleItems)
            } else {
                items = deduplicated(items + visibleItems)
            }
            // Pagination is deliberately derived from the unfiltered service
            // page, so a locally muted page never becomes a false end-of-feed.
            let pagination = MessagePaginationPolicy.state(
                after: page,
                requestedPage: requestedPage
            )
            hasMore = pagination.hasMore
            nextPage = pagination.nextPage
            continuation = LocallyFilteredPaginationPolicy.decision(
                visibleItemCount: visibleItems.count,
                serverHasMore: hasMore,
                consecutiveHiddenPageCount: consecutiveHiddenPageCount
            )
        } catch is CancellationError {
            guard generation == requestGeneration,
                  requestedSession == self.account?.sessionIdentity else { return }
            loadTask = nil
            isLoading = false
            return
        } catch {
            guard generation == requestGeneration,
                  requestedSession == self.account?.sessionIdentity else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
        }

        guard generation == requestGeneration,
              requestedSession == self.account?.sessionIdentity else { return }
        loadTask = nil
        isLoading = false
        didLoad = true
        if let continuation, continuation.shouldAutomaticallyLoadNextPage {
            await loadMore(
                generation: generation,
                replacing: false,
                consecutiveHiddenPageCount: continuation.consecutiveHiddenPageCount
            )
        }
    }

    private func deduplicated(_ candidates: [MessageItem]) -> [MessageItem] {
        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }
    }
}

private struct MessageRow: View {
    let message: MessageItem

    var body: some View {
        HStack(alignment: .top, spacing: TiebaPureTheme.Spacing.sm) {
            AvatarView(
                url: message.author.portraitURL,
                title: message.author.displayNameResolved,
                size: TiebaPureTheme.AvatarSize.medium
            )

            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: TiebaPureTheme.Spacing.xs) {
                    Text(message.author.displayNameResolved)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(kindDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)

                    Spacer(minLength: TiebaPureTheme.Spacing.xs)

                    if let createdAt = message.createdAt {
                        Text(ReaderDateText.string(from: createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .layoutPriority(1)
                    }
                }

                if message.content.isEmpty == false {
                    Text(message.content)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if sourceLine.isEmpty == false {
                    Text(sourceLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var kindDescription: String {
        switch message.kind {
        case .reply:
            return message.isFloorReply ? "在楼中楼回复了我" : "回复了我"
        case .at:
            return "@了我"
        }
    }

    private var sourceLine: String {
        var parts: [String] = []
        let title = message.threadTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty == false {
            parts.append("原帖：\(title)")
        }
        if let forumName = message.forumName?.trimmingCharacters(in: .whitespacesAndNewlines),
           forumName.isEmpty == false {
            parts.append(forumName.hasSuffix("吧") ? forumName : "\(forumName)吧")
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var parts = ["\(message.author.displayNameResolved)\(kindDescription)"]
        if message.content.isEmpty == false {
            parts.append(message.content)
        }
        if sourceLine.isEmpty == false {
            parts.append(sourceLine)
        }
        if let createdAt = message.createdAt {
            parts.append(ReaderDateText.string(from: createdAt))
        }
        return parts.joined(separator: "，")
    }
}
