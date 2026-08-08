import SwiftUI

/// The collection Baidu keeps for the account. Collecting is an account action
/// like following a forum, so this screen shows the service's list rather than
/// a copy of it.
struct ThreadFavoritesView: View {
    let account: Account?

    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.editMode) private var editMode
    @ObservedObject private var libraryStore = LocalThreadLibraryStore.shared
    @ObservedObject private var blocklistStore = BlocklistStore.shared
    @StateObject private var loader = AccountThreadFavoritesLoader()
    @State private var activeFavorite: AccountThreadFavorite?
    @State private var searchText = ""
    @State private var progressFilter: ThreadFavoritesProgressFilter = .all
    @State private var selectedThreadIDs = Set<Int64>()
    @State private var pendingDeletionThreadIDs = Set<Int64>()
    @State private var showsClearReadingPositionsConfirmation = false
    @State private var showsDeleteSelectionConfirmation = false
    @State private var showsPersistenceError = false
    @State private var removalError: String?
    @State private var removalTasks: [UUID: Task<Void, Never>] = [:]
    @State private var removalOperations = ThreadFavoritesRemovalOperationState()
    @State private var pendingRemoteRemovalThreadIDs = Set<Int64>()

    var body: some View {
        dialogs
            .task {
                guard let account, loader.didLoad == false else { return }
                await reloadAfterPendingFavoriteWrites(account: account)
            }
            .onAppear {
                libraryStore.reload()
                // Collecting happens on the thread screen, so coming back here
                // has to re-read the list instead of trusting what it had.
                guard let account, loader.didLoad else { return }
                Task { await reloadAfterPendingFavoriteWrites(account: account) }
            }
            .onChangeCompat(of: account?.sessionIdentity) { _, _ in
                cancelRemovalPresentation()
                loader.reset()
                guard let account else { return }
                Task { await reloadAfterPendingFavoriteWrites(account: account) }
            }
            .onDisappear {
                loader.cancel()
                cancelRemovalPresentation()
            }
            .onChangeCompat(of: visibleThreadIDs) { _, _ in
                synchronizeSelection()
            }
            .onChangeCompat(of: isEditing) { _, editing in
                if editing == false {
                    selectedThreadIDs.removeAll()
                }
            }
            .onChangeCompat(of: blocklistStore.entries) { _, _ in
                guard let activeFavorite,
                      ThreadFavoritesListPolicy.shouldKeep(
                        activeFavorite,
                        blocklist: currentBlocklist
                      ) == false else { return }
                self.activeFavorite = nil
            }
            .fullScreenInteractiveNavigationPop()
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            if loader.favorites.isEmpty == false {
                progressFilterPicker
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .navigationTitle("帖子收藏")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "搜索标题、作者或贴吧"
        )
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            selectionBar
        }
        .navigationDestinationCompat(isPresented: favoriteIsActive) {
            if let activeFavorite {
                ThreadDetailView(
                    account: account,
                    threadID: activeFavorite.threadID,
                    forumID: activeFavorite.forumID > 0 ? activeFavorite.forumID : nil,
                    initialPostID: initialPostID(for: activeFavorite)
                )
                .interactiveNavigationPopStateSync {
                    self.activeFavorite = nil
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(allVisibleFavoritesAreSelected ? "取消全选" : "全选") {
                    selectedThreadIDs = LocalThreadListSelectionPolicy
                        .selectionByTogglingAll(
                            selectedThreadIDs,
                            visibleThreadIDs: visibleThreadIDs
                        )
                }
                .disabled(visibleFavorites.isEmpty)
                .accessibilityIdentifier("thread-favorites-select-all")
            }
        }

        if isEditing == false, libraryStore.readingPositions.isEmpty == false {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showsClearReadingPositionsConfirmation = true
                    } label: {
                        Label("清除阅读位置", systemImage: "bookmark.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .minTouchTarget()
                .accessibilityLabel("管理本机帖子记录")
                .accessibilityHint("清除本机保存的阅读位置")
                .accessibilityIdentifier("thread-library-manage")
            }
        }

        if visibleFavorites.isEmpty == false || isEditing {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
                    .minTouchTarget()
                    .accessibilityIdentifier("thread-favorites-edit")
            }
        }
    }

    private var dialogs: some View {
        chrome
            .confirmationDialog(
                "清除全部帖子阅读位置？",
                isPresented: $showsClearReadingPositionsConfirmation,
                titleVisibility: .visible
            ) {
                Button("清除", role: .destructive) {
                    if libraryStore.clearReadingPositions() == false {
                        showsPersistenceError = true
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("只删除本机记住的阅读位置，不会取消收藏。")
            }
            .confirmationDialog(
                "取消收藏选中的 \(pendingDeletionThreadIDs.count) 条帖子？",
                isPresented: $showsDeleteSelectionConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    removeFavorites(threadIDs: pendingDeletionThreadIDs)
                    pendingDeletionThreadIDs.removeAll()
                }
                Button("取消", role: .cancel) {
                    pendingDeletionThreadIDs.removeAll()
                }
            } message: {
                Text("收藏会从贴吧账号里移除，已有阅读位置会继续保留。")
            }
            .alert("操作失败", isPresented: $showsPersistenceError) {
                Button("好", role: .cancel) {}
            } message: {
                Text("未能保存本机帖子记录，请稍后重试。")
            }
            .alert("取消收藏失败", isPresented: removalErrorIsPresented) {
                Button("好", role: .cancel) { removalError = nil }
            } message: {
                Text(removalError ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if account == nil {
            ScrollView {
                ReaderStateView.empty(
                    title: "未登录",
                    message: "收藏保存在贴吧账号里，登录后可以查看。"
                )
                .frame(maxWidth: .infinity)
                .padding(.top, TiebaPureTheme.Spacing.lg)
            }
            .accessibilityIdentifier("thread-favorites-empty")
        } else if loader.didLoad == false {
            ReaderStateView.loading("正在加载帖子收藏")
        } else if let errorMessage = loader.errorMessage, loader.favorites.isEmpty {
            ReaderStateScrollView(refresh: { await reload() }) {
                ReaderStateView.error(message: errorMessage) {
                    Task { await reload() }
                }
            }
        } else if visibleFavorites.isEmpty, loader.canLoadMore == false {
            ScrollView {
                ReaderStateView.empty(
                    title: emptyState.title,
                    message: emptyState.message
                )
                .frame(maxWidth: .infinity)
                .padding(.top, TiebaPureTheme.Spacing.lg)
            }
            .accessibilityIdentifier("thread-favorites-empty")
        } else {
            list
        }
    }

    private var list: some View {
        List(selection: $selectedThreadIDs) {
            ForEach(Array(visibleFavorites.enumerated()), id: \.element.id) { index, favorite in
                Group {
                    if isEditing {
                        ThreadFavoriteRow(
                            favorite: favorite,
                            readingPosition: libraryStore.position(for: favorite.threadID),
                            showsDisclosureIndicator: false
                        )
                    } else {
                        Button {
                            activeFavorite = favorite
                        } label: {
                            ThreadFavoriteRow(
                                favorite: favorite,
                                readingPosition: libraryStore.position(for: favorite.threadID)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .tag(favorite.threadID)
                .contentShape(Rectangle())
                .accessibilityIdentifier("thread-favorite-row-\(favorite.threadID)")
                .accessibilityHint(isEditing ? "选择或取消选择" : "打开收藏的帖子")
                .onAppear {
                    guard PaginationPrefetchPolicy.shouldLoadMore(
                        currentIndex: index,
                        totalCount: visibleFavorites.count
                    ) else { return }
                    Task { await loadMore() }
                }
            }
            .onDelete(perform: removeFavorites)

            listFooter
        }
        .listStyle(.plain)
        .refreshable {
            libraryStore.reload()
            await reload()
        }
        .accessibilityIdentifier("thread-favorites-list")
    }

    @ViewBuilder
    private var listFooter: some View {
        if loader.isLoading, loader.didLoad {
            ProgressView()
                .frame(maxWidth: .infinity)
                .accessibilityLabel("正在加载更多收藏")
        } else if let errorMessage = loader.errorMessage {
            InlineLoadErrorView(message: errorMessage) {
                Task { await loadMore() }
            }
        } else if loader.canLoadMore {
            // Search and the progress filter only see what is already loaded,
            // so the list keeps a way to pull the next page even when the
            // current filter leaves nothing on screen.
            Button("加载更多收藏") {
                Task { await loadMore() }
            }
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("thread-favorites-load-more")
        }
    }

    private var progressFilterPicker: some View {
        Picker("阅读进度", selection: $progressFilter) {
            ForEach(ThreadFavoritesProgressFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 360)
        .frame(minHeight: 44)
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.vertical, TiebaPureTheme.Spacing.xs)
        .accessibilityIdentifier("thread-favorites-progress-filter")
    }

    @ViewBuilder
    private var selectionBar: some View {
        if isEditing {
            HStack(spacing: TiebaPureTheme.Spacing.md) {
                Text("已选 \(selectedThreadIDs.count) 项")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("thread-favorites-selection-count")

                Spacer(minLength: TiebaPureTheme.Spacing.sm)

                Button(role: .destructive) {
                    pendingDeletionThreadIDs = selectedThreadIDs
                    showsDeleteSelectionConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedThreadIDs.isEmpty)
                .minTouchTarget()
                .accessibilityLabel("取消收藏选中的帖子")
                .accessibilityIdentifier("thread-favorites-delete-selected")
            }
            .frame(minHeight: 50)
            .padding(.horizontal, TiebaPureTheme.Spacing.md)
            .background(.bar)
            .overlay(alignment: .top) {
                Divider()
            }
        }
    }

    private var currentBlocklist: BlocklistSnapshot {
        BlocklistSnapshot(entries: blocklistStore.entries)
    }

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    private var visibleFavorites: [AccountThreadFavorite] {
        ThreadFavoritesListPolicy.visibleFavorites(
            loader.favorites,
            blocklist: currentBlocklist,
            searchText: searchText,
            progressFilter: progressFilter,
            readingPositions: libraryStore.readingPositions
        )
    }

    private var visibleThreadIDs: [Int64] {
        visibleFavorites.map(\.threadID)
    }

    private var allVisibleFavoritesAreSelected: Bool {
        visibleThreadIDs.isEmpty == false
            && selectedThreadIDs == Set(visibleThreadIDs)
    }

    private var emptyState: (title: String, message: String) {
        if loader.favorites.isEmpty {
            return (
                "暂无帖子收藏",
                "在帖子页点击右上角的收藏按钮后，会显示在这里。"
            )
        }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || progressFilter != .all {
            return ("没有匹配的帖子收藏", "尝试调整搜索内容或阅读进度筛选。")
        }
        return ("没有可显示的帖子收藏", "已按你的屏蔽设置隐藏相关收藏。")
    }

    private var favoriteIsActive: Binding<Bool> {
        Binding(
            get: { activeFavorite != nil },
            set: { isPresented in
                if isPresented == false {
                    activeFavorite = nil
                }
            }
        )
    }

    private var removalErrorIsPresented: Binding<Bool> {
        Binding(
            get: { removalError != nil },
            set: { isPresented in
                if isPresented == false {
                    removalError = nil
                }
            }
        )
    }

    /// Baidu remembers the floor a thread was collected at, which is where the
    /// thread should open — unless this device remembers a later reading
    /// position, which the thread screen restores on its own.
    private func initialPostID(for favorite: AccountThreadFavorite) -> UInt64? {
        guard libraryStore.position(for: favorite.threadID) == nil else { return nil }
        return favorite.markedPostID
    }

    private func reload() async {
        guard let account else { return }
        await reloadAfterPendingFavoriteWrites(account: account)
    }

    private func loadMore() async {
        await loader.loadMore(account: account, api: environment.api)
        loader.remove(threadIDs: pendingRemoteRemovalThreadIDs)
    }

    private func reloadAfterPendingFavoriteWrites(account: Account) async {
        let session = account.sessionIdentity
        await environment.contentSubmissionCoordinator.waitForThreadFavoriteWrites(
            account: account
        )
        guard Task.isCancelled == false,
              self.account?.sessionIdentity == session else { return }
        await loader.reload(account: account, api: environment.api)
        guard self.account?.sessionIdentity == session else { return }
        loader.remove(threadIDs: pendingRemoteRemovalThreadIDs)
    }

    private func removeFavorites(at offsets: IndexSet) {
        removeFavorites(
            threadIDs: ThreadFavoritesListPolicy.threadIDs(
                at: offsets,
                in: visibleFavorites
            )
        )
    }

    private func removeFavorites(threadIDs: Set<Int64>) {
        guard let account, threadIDs.isEmpty == false else { return }
        let targets = loader.favorites.filter { threadIDs.contains($0.threadID) }
        guard targets.isEmpty == false else { return }
        // The rows leave right away and come back only if the service refuses.
        loader.remove(threadIDs: threadIDs)
        selectedThreadIDs.subtract(threadIDs)
        if visibleFavorites.isEmpty {
            editMode?.wrappedValue = .inactive
        }

        let api = environment.api
        let coordinator = environment.contentSubmissionCoordinator
        let submittedSession = account.sessionIdentity
        let operation = removalOperations.begin()
        pendingRemoteRemovalThreadIDs.formUnion(threadIDs)
        let task = Task {
            var failure: Error?
            do {
                for target in targets {
                    try await coordinator.performAccountWrite(
                        account: account,
                        target: .threadFavorite(target.threadID)
                    ) {
                        try await api.setAccountThreadFavorite(
                            account: account,
                            threadID: target.threadID,
                            postID: target.markedPostID ?? 0,
                            favorited: false
                        )
                    }
                    try Task.checkCancellation()
                }
            } catch is CancellationError {
                // The registered write survives a view dismissal; account
                // replacement additionally cancels it through the write barrier.
            } catch {
                failure = error
            }

            guard removalIsCurrent(operation: operation, session: submittedSession) else {
                return
            }
            pendingRemoteRemovalThreadIDs.subtract(threadIDs)

            if let failure {
                removalError = ReaderErrorMessage.message(for: failure)
                await loader.reload(account: account, api: api)
                guard removalIsCurrent(operation: operation, session: submittedSession) else {
                    return
                }
                // Another independent batch may still be in flight while the
                // authoritative reload completes. Keep those rows optimistic.
                loader.remove(threadIDs: pendingRemoteRemovalThreadIDs)
            }
            removalOperations.finish(operation)
            removalTasks[operation.id] = nil
        }
        removalTasks[operation.id] = task
    }

    private func removalIsCurrent(
        operation: ThreadFavoritesRemovalOperationState.Operation,
        session: AccountSessionIdentity
    ) -> Bool {
        removalOperations.isCurrent(operation)
            && account?.sessionIdentity == session
    }

    private func cancelRemovalPresentation() {
        removalOperations.invalidate()
        removalTasks.values.forEach { $0.cancel() }
        removalTasks.removeAll()
        pendingRemoteRemovalThreadIDs.removeAll()
    }

    private func synchronizeSelection() {
        selectedThreadIDs = LocalThreadListSelectionPolicy.retainedSelection(
            selectedThreadIDs,
            visibleThreadIDs: visibleThreadIDs
        )
        if isEditing, visibleFavorites.isEmpty {
            editMode?.wrappedValue = .inactive
        }
    }
}

struct ThreadFavoritesRemovalOperationState {
    struct Operation: Hashable, Sendable {
        let id: UUID
        let generation: Int
    }

    private(set) var generation = 0
    private(set) var activeOperationIDs = Set<UUID>()

    mutating func begin(id: UUID = UUID()) -> Operation {
        activeOperationIDs.insert(id)
        return Operation(id: id, generation: generation)
    }

    func isCurrent(_ operation: Operation) -> Bool {
        operation.generation == generation && activeOperationIDs.contains(operation.id)
    }

    mutating func finish(_ operation: Operation) {
        guard operation.generation == generation else { return }
        activeOperationIDs.remove(operation.id)
    }

    mutating func invalidate() {
        generation &+= 1
        activeOperationIDs.removeAll()
    }
}

enum ThreadFavoritesProgressFilter: String, CaseIterable, Identifiable {
    case all
    case hasReadingPosition
    case withoutReadingPosition

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .hasReadingPosition:
            return "有进度"
        case .withoutReadingPosition:
            return "无进度"
        }
    }
}

enum ThreadFavoritesListPolicy {
    static func visibleFavorites(
        _ favorites: [AccountThreadFavorite],
        blocklist: BlocklistSnapshot,
        searchText: String = "",
        progressFilter: ThreadFavoritesProgressFilter = .all,
        readingPositions: [ThreadReadingPosition] = []
    ) -> [AccountThreadFavorite] {
        let threadsWithReadingPositions = Set(readingPositions.map(\.threadID))
        return favorites.filter { favorite in
            shouldKeep(favorite, blocklist: blocklist)
                && LocalThreadListSearchPolicy.matches(
                    query: searchText,
                    fields: [
                        favorite.title,
                        favorite.authorDisplayName,
                        favorite.forumName,
                        String(favorite.threadID)
                    ]
                )
                && progressFilter.includes(
                    favorite.threadID,
                    threadsWithReadingPositions: threadsWithReadingPositions
                )
        }
    }

    static func shouldKeep(
        _ favorite: AccountThreadFavorite,
        blocklist: BlocklistSnapshot
    ) -> Bool {
        if TiebaContentFilter.shouldKeep(
            forum: Forum(
                id: favorite.forumID,
                name: favorite.forumName,
                displayName: favorite.forumName,
                avatarURL: nil,
                memberCount: 0,
                threadCount: 0
            )
        ) == false {
            return false
        }
        if blocklist.blocksUser(id: 0, names: [favorite.authorDisplayName]) {
            return false
        }
        if blocklist.containsKeyword(in: favorite.title) {
            return false
        }
        if blocklist.blocksForum(
            id: favorite.forumID > 0 ? favorite.forumID : nil,
            names: favorite.forumName.isEmpty ? [] : [favorite.forumName]
        ) {
            return false
        }
        return true
    }

    static func threadIDs(
        at offsets: IndexSet,
        in visibleFavorites: [AccountThreadFavorite]
    ) -> Set<Int64> {
        Set(offsets.compactMap { index in
            visibleFavorites.indices.contains(index)
                ? visibleFavorites[index].threadID
                : nil
        })
    }
}

private extension ThreadFavoritesProgressFilter {
    func includes(
        _ threadID: Int64,
        threadsWithReadingPositions: Set<Int64>
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .hasReadingPosition:
            return threadsWithReadingPositions.contains(threadID)
        case .withoutReadingPosition:
            return threadsWithReadingPositions.contains(threadID) == false
        }
    }
}

private struct ThreadFavoriteRow: View {
    let favorite: AccountThreadFavorite
    let readingPosition: ThreadReadingPosition?
    var showsDisclosureIndicator = true

    var body: some View {
        HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
                Text(favorite.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                MetadataLine(metadataItems, systemImage: "star")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDisclosureIndicator {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .padding(.vertical, TiebaPureTheme.Spacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var metadataItems: [String] {
        [
            favorite.forumName.isEmpty ? nil : "\(favorite.forumName)吧",
            favorite.authorDisplayName,
            readingPosition.map { "上次读到 \($0.floor)楼" },
            favorite.replyCount > 0 ? "\(favorite.replyCount)条回复" : nil,
            favorite.lastReplyAt.map { "最后回复 \(ReaderDateText.string(from: $0))" }
        ].compactMap { $0 }.filter { $0.isEmpty == false }
    }

    private var accessibilityText: String {
        ([favorite.title] + metadataItems).joined(separator: "，")
    }
}
