import SwiftUI

enum SearchScope: Equatable {
    case global
    case forum(Forum)

    var title: String {
        switch self {
        case .global:
            return "搜索"
        case let .forum(forum):
            return "\(forum.displayName)搜索"
        }
    }

    var prompt: String {
        switch self {
        case .global:
            return "搜索帖子或回复"
        case .forum:
            return "搜索本吧帖子或回复"
        }
    }

    var forumName: String? {
        if case let .forum(forum) = self {
            return forum.name
        }
        return nil
    }
}

struct SearchResultsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.readingPreferences) private var readingPreferences
    @ObservedObject private var historyStore = SearchHistoryStore.shared
    @ObservedObject private var blocklistStore = BlocklistStore.shared
    let account: Account?
    let scope: SearchScope
    let initialKeyword: String
    private let openThreadInParent: ((SearchThreadRoute) -> Void)?
    private let openForumInParent: ((Forum) -> Void)?
    private let openUserInParent: ((UserSummary) -> Void)?

    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchText: String
    @State private var submittedKeyword: String
    @State private var results: [SearchResult] = []
    @State private var page = 1
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var filterType = 2
    @State private var sortType = 5
    @State private var activeThread: SearchThreadRoute?
    @State private var activeForum: Forum?
    @State private var selectedUser: UserSummary?
    @State private var requestGeneration = 0
    @State private var loadTask: Task<SearchResultsPage, Error>?
    @State private var showsHistoryPersistenceError = false

    init(
        account: Account?,
        scope: SearchScope,
        initialKeyword: String,
        openThreadInParent: ((SearchThreadRoute) -> Void)? = nil,
        openForumInParent: ((Forum) -> Void)? = nil,
        openUserInParent: ((UserSummary) -> Void)? = nil
    ) {
        self.account = account
        self.scope = scope
        self.initialKeyword = initialKeyword
        self.openThreadInParent = openThreadInParent
        self.openForumInParent = openForumInParent
        self.openUserInParent = openUserInParent
        _searchText = State(initialValue: initialKeyword)
        _submittedKeyword = State(initialValue: initialKeyword)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .readableWidth()

            Divider()

            if submittedKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchHistory
            } else {
                searchResults
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .contentShape(Rectangle())
        .navigationTitle(scope.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestinationCompat(isPresented: threadIsActive) {
            if let activeThread {
                ThreadDetailView(
                    account: account,
                    threadID: activeThread.threadID,
                    forumID: activeThread.forumID,
                    initialPostID: activeThread.postID
                )
                .interactiveNavigationPopStateSync {
                    self.activeThread = nil
                }
            }
        }
        .navigationDestinationCompat(isPresented: forumIsActive) {
            if let activeForum {
                ForumThreadsView(account: account, forum: activeForum)
                    .interactiveNavigationPopStateSync {
                        self.activeForum = nil
                    }
            }
        }
        .navigationDestinationCompat(isPresented: userIsActive) {
            if let selectedUser {
                UserProfileView(account: account, user: selectedUser)
                    .interactiveNavigationPopStateSync {
                        self.selectedUser = nil
                    }
            }
        }
        .task {
            guard didLoad == false else { return }
            if submittedKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isSearchFieldFocused = true
                return
            }
            await reload()
        }
        .onChange(of: account?.sessionIdentity) { _ in
            requestGeneration += 1
            loadTask?.cancel()
            results = []
            page = 1
            hasMore = true
            didLoad = false
            isLoading = false
            errorMessage = nil
            Task { await reload() }
        }
        .onChange(of: blocklistStore.entries) { _ in
            results.removeAll { TiebaContentFilter.shouldKeep(searchResult: $0) == false }
        }
        .onDisappear {
            loadTask?.cancel()
            requestGeneration += 1
            isLoading = false
        }
        .alert("操作失败", isPresented: $showsHistoryPersistenceError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("未能保存搜索历史更改，请稍后重试。")
        }
        .fullScreenInteractiveNavigationPop()
    }

    private var searchBar: some View {
        HStack(spacing: TiebaPureTheme.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(scope.prompt, text: $searchText)
                .focused($isSearchFieldFocused)
                .frame(minHeight: 44)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(submitSearch)
                .accessibilityLabel(scope.prompt)
                .accessibilityIdentifier("search-input")

            if searchText.isEmpty == false {
                Button(action: clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("清空搜索内容")
                .accessibilityHint("留在当前搜索页面")
                .accessibilityIdentifier("search-clear-button")
            }
        }
        .padding(.leading, TiebaPureTheme.Spacing.md)
        .padding(.trailing, searchText.isEmpty ? TiebaPureTheme.Spacing.md : 0)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFieldFocused = true
        }
        .background(
            RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.card, style: .continuous)
                .fill(TiebaPureTheme.ColorToken.readerSecondarySurface)
        )
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.vertical, TiebaPureTheme.Spacing.xs)
    }

    private var searchHistory: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                HStack(spacing: TiebaPureTheme.Spacing.sm) {
                    Label("搜索历史", systemImage: "clock.arrow.circlepath")
                        .font(.headline)

                    Spacer(minLength: TiebaPureTheme.Spacing.sm)

                    if historyStore.items.isEmpty == false {
                        Button("清空") {
                            if historyStore.clear() == false {
                                showsHistoryPersistenceError = true
                            }
                        }
                        .font(.subheadline)
                        .minTouchTarget()
                        .accessibilityLabel("清空全部搜索历史")
                        .accessibilityIdentifier("search-history-clear-all")
                    }
                }
                .padding(.bottom, TiebaPureTheme.Spacing.xs)

                if historyStore.items.isEmpty {
                    Text("暂无搜索历史")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
                        .accessibilityIdentifier("search-history-empty")
                } else {
                    ForEach(Array(historyStore.items.enumerated()), id: \.element) { index, keyword in
                        HStack(spacing: TiebaPureTheme.Spacing.xs) {
                            Button {
                                searchFromHistory(keyword)
                            } label: {
                                HStack(spacing: TiebaPureTheme.Spacing.sm) {
                                    Image(systemName: "clock")
                                        .foregroundStyle(.secondary)
                                    Text(keyword)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("搜索历史：\(keyword)")
                            .accessibilityIdentifier("search-history-item-\(index)")

                            Button {
                                if historyStore.remove(keyword) == false {
                                    showsHistoryPersistenceError = true
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .accessibilityLabel("删除搜索历史：\(keyword)")
                        }

                        if index < historyStore.items.count - 1 {
                            Divider()
                        }
                    }
                }
            }
            .padding(.horizontal, TiebaPureTheme.Spacing.md)
            .padding(.vertical, TiebaPureTheme.Spacing.sm)
            .readableWidth()
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
    }

    private var searchResults: some View {
        VStack(spacing: 0) {
            controls
                .readableWidth()

            Group {
                if isLoading && didLoad == false {
                    ReaderStateView.loading("正在搜索")
                } else if let errorMessage, results.isEmpty {
                    ReaderStateScrollView(refresh: { await reload() }) {
                        ReaderStateView.error(message: errorMessage) {
                            Task { await reload() }
                        }
                    }
                } else if results.isEmpty {
                    ReaderStateScrollView(refresh: { await reload() }) {
                        ReaderStateView.empty(
                            title: "没有结果",
                            message: "可调整范围或排序后重试。",
                            actionTitle: hasMore && didLoad ? "继续加载" : nil,
                            action: hasMore && didLoad ? { Task { await loadMore() } } : nil
                        )
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: TiebaPureTheme.Spacing.sm) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                let thread = result.threadSummary
                                ForumThreadRow(
                                    thread: thread,
                                    presentation: .homeFeed,
                                    highlightKeyword: submittedKeyword,
                                    onOpenThread: {
                                        openThread(
                                            SearchThreadRoute(
                                                threadID: result.threadID,
                                                forumID: result.forumID,
                                                postID: result.postID
                                            )
                                        )
                                    },
                                    onOpenForum: { forum in
                                        RecentForumStore.shared.save(forum)
                                        openForum(forum)
                                    },
                                    onOpenUser: openUser,
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
                                            openThread(
                                                SearchThreadRoute(
                                                    threadID: result.threadID,
                                                    forumID: result.forumID,
                                                    postID: result.postID
                                                )
                                            )
                                        }
                                    }
                                )
                                .onAppear {
                                    guard PaginationPrefetchPolicy.shouldLoadMore(
                                        currentIndex: index,
                                        totalCount: results.count
                                    ) else { return }
                                    Task { await loadMore() }
                                }
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("thread-row")
                            }

                            if isLoading, didLoad {
                                ProgressView()
                                    .padding(TiebaPureTheme.Spacing.md)
                                    .accessibilityLabel("正在加载更多搜索结果")
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
                                    Label("加载更多搜索结果", systemImage: "arrow.down.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .minTouchTarget()
                                .padding(.horizontal, TiebaPureTheme.Spacing.md)
                                .accessibilityIdentifier("search-results-load-more")
                            }

                            Color.clear
                                .frame(height: 48)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, TiebaPureTheme.Spacing.sm)
                        .padding(.vertical, TiebaPureTheme.Spacing.sm)
                        .readableWidth()
                    }
                    .shortPullRefresh(
                        isEnabled: didLoad && isLoading == false,
                        surface: .grouped,
                        accessibilityIdentifier: "search-refresh-animation"
                    ) {
                        await reload()
                    }
                    .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
    }

    private var threadIsActive: Binding<Bool> {
        Binding(
            get: { activeThread != nil },
            set: { isActive in
                if isActive == false {
                    activeThread = nil
                }
            }
        )
    }

    private var forumIsActive: Binding<Bool> {
        Binding(
            get: { activeForum != nil },
            set: { isActive in
                if isActive == false {
                    activeForum = nil
                }
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

    private func openThread(_ route: SearchThreadRoute) {
        if let openThreadInParent {
            openThreadInParent(route)
        } else {
            activeThread = route
        }
    }

    private func openForum(_ forum: Forum) {
        if let openForumInParent {
            openForumInParent(forum)
        } else {
            activeForum = forum
        }
    }

    private func openUser(_ user: UserSummary) {
        if let openUserInParent {
            openUserInParent(user)
        } else {
            selectedUser = user
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TiebaPureTheme.Spacing.sm) {
                filterPicker
                sortMenu
            }
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
                filterPicker
                sortMenu
            }
        }
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.vertical, TiebaPureTheme.Spacing.sm)
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
    }

    private var filterPicker: some View {
            Picker("范围", selection: $filterType) {
                Text("全部").tag(2)
                Text("主题").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .onChange(of: filterType) { _ in
                Task { await reload() }
            }
    }

    private var sortMenu: some View {
            Menu {
                Button("最新") { updateSortType(5) }
                Button("相关") { updateSortType(2) }
                Button("最旧") { updateSortType(0) }
            } label: {
                Label(sortTitle, systemImage: "arrow.up.arrow.down")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .accessibilityLabel("排序：\(sortTitle)")
    }

    private var sortTitle: String {
        switch sortType {
        case 0:
            return "最旧"
        case 2:
            return "相关"
        default:
            return "最新"
        }
    }

    private func submitSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        searchText = trimmed
        submittedKeyword = trimmed
        historyStore.record(trimmed)
        isSearchFieldFocused = false
        Task { await reload() }
    }

    private func searchFromHistory(_ keyword: String) {
        searchText = keyword
        submittedKeyword = keyword
        historyStore.record(keyword)
        isSearchFieldFocused = false
        Task { await reload() }
    }

    private func clearSearch() {
        loadTask?.cancel()
        requestGeneration += 1
        searchText = ""
        submittedKeyword = ""
        results = []
        page = 1
        hasMore = true
        isLoading = false
        didLoad = false
        errorMessage = nil
        isSearchFieldFocused = true
    }

    private func updateSortType(_ newValue: Int) {
        guard sortType != newValue else { return }
        sortType = newValue
        Task { await reload() }
    }

    private func reload() async {
        loadTask?.cancel()
        requestGeneration += 1
        isLoading = false
        page = 1
        hasMore = true
        errorMessage = nil
        if results.isEmpty {
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
        let keyword = submittedKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard keyword.isEmpty == false, isLoading == false, hasMore else { return }
        let requestedPage = page
        let key = SearchRequestKey(
            accountID: account?.id,
            keyword: keyword,
            forumName: scope.forumName,
            filterType: filterType,
            sortType: sortType,
            page: requestedPage
        )
        let requestedSession = account?.sessionIdentity
        isLoading = true
        errorMessage = nil
        var continuation: LocallyFilteredPaginationDecision?

        do {
            let task = Task { try await environment.api.searchThreads(
                keyword: keyword,
                page: requestedPage,
                sortType: key.sortType,
                filterType: key.filterType,
                forumName: scope.forumName
            ) }
            loadTask = task
            let pageResult = try await task.value
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity,
                  key == currentRequestKey(page: requestedPage) else { return }
            let visibleResults = pageResult.results
                .filter(TiebaContentFilter.shouldKeep(searchResult:))
            if requestedPage == 1 {
                results = visibleResults
            } else {
                let known = Set(results.map(\.id))
                results.append(contentsOf: visibleResults.filter { known.contains($0.id) == false })
            }
            // Search responses carry an explicit service-side continuation
            // bit. A locally hidden page must not override it.
            hasMore = pageResult.hasMore
            if let followingPage = TiebaPaginationPolicy.nextPage(
                requestedPage: requestedPage,
                responseCurrentPage: pageResult.currentPage
            ) {
                page = followingPage
            } else {
                hasMore = false
            }
            continuation = LocallyFilteredPaginationPolicy.decision(
                visibleItemCount: visibleResults.count,
                serverHasMore: hasMore,
                consecutiveHiddenPageCount: consecutiveHiddenPageCount
            )
        } catch is CancellationError {
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity else { return }
            loadTask = nil
            isLoading = false
            return
        } catch {
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity,
                  key == currentRequestKey(page: requestedPage) else { return }
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
        }
    }

    private func currentRequestKey(page: Int) -> SearchRequestKey {
        SearchRequestKey(
            accountID: account?.id,
            keyword: submittedKeyword.trimmingCharacters(in: .whitespacesAndNewlines),
            forumName: scope.forumName,
            filterType: filterType,
            sortType: sortType,
            page: page
        )
    }
}

struct SearchThreadRoute: Equatable {
    let threadID: Int64
    let forumID: Int64?
    let postID: UInt64?
}

struct SearchRequestKey: Equatable {
    let accountID: String?
    let keyword: String
    let forumName: String?
    let filterType: Int
    let sortType: Int
    let page: Int
}

enum SearchHistoryPolicy {
    static let maximumStoredEntries = 20
    private static let maximumKeywordLength = 200

    static func normalizedKeyword(_ keyword: String) -> String {
        String(
            keyword
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(maximumKeywordLength)
        )
    }

    static func adding(_ keyword: String, to items: [String], limit: Int) -> [String] {
        let effectiveLimit = min(max(limit, 0), maximumStoredEntries)
        let normalized = normalizedKeyword(keyword)
        guard normalized.isEmpty == false, effectiveLimit > 0 else {
            return Array(items.prefix(effectiveLimit))
        }
        var updated = items.filter { isSameKeyword($0, normalized) == false }
        updated.insert(normalized, at: 0)
        return Array(updated.prefix(effectiveLimit))
    }

    static func removing(_ keyword: String, from items: [String]) -> [String] {
        let normalized = normalizedKeyword(keyword)
        return items.filter { isSameKeyword($0, normalized) == false }
    }

    static func sanitized(_ items: [String], limit: Int) -> [String] {
        let effectiveLimit = min(max(limit, 0), maximumStoredEntries)
        guard effectiveLimit > 0 else { return [] }
        var result: [String] = []
        for item in items {
            let normalized = normalizedKeyword(item)
            guard normalized.isEmpty == false,
                  result.contains(where: { isSameKeyword($0, normalized) }) == false else {
                continue
            }
            result.append(normalized)
            if result.count == effectiveLimit { break }
        }
        return result
    }

    private static func isSameKeyword(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

@MainActor
final class SearchHistoryStore: ObservableObject {
    static let shared = SearchHistoryStore()

    private let defaults: UserDefaults
    private let key: String
    private let limit: Int
    private let persistentBackendIsAvailable: Bool
    private let faultInjector: PersistenceFaultInjector
    @Published private(set) var items: [String]
    @Published private(set) var persistenceAvailability: PersistenceAvailability

    init(
        defaults: UserDefaults = .standard,
        key: String = "dev.infinityf4p.tiebapure.searchHistory",
        limit: Int = 20,
        persistenceAvailability: PersistenceAvailability? = nil,
        faultInjector: PersistenceFaultInjector = .none
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = max(limit, 0)
        self.faultInjector = faultInjector
        let initial = persistenceAvailability ?? .available
        persistentBackendIsAvailable = initial.canPersist
        self.persistenceAvailability = initial
        var legacyFallback: [String]?
        var migrationFailed = false
        do {
            try Self.migrateLegacyStorage(
                defaults: defaults,
                key: key,
                limit: self.limit,
                destinationIsDurable: initial.canPersist,
                legacyFallback: &legacyFallback,
                faultInjector: faultInjector
            )
        } catch {
            PersistenceDiagnostics.report(error, operation: "migrate search history")
            self.persistenceAvailability = .unavailable
            migrationFailed = true
        }
        do {
            let result = try Self.loadAndRepairItems(
                limit: self.limit,
                canRepair: persistentBackendIsAvailable,
                faultInjector: faultInjector
            )
            items = result.value
            if let error = result.repairError {
                PersistenceDiagnostics.report(error, operation: "repair search history")
                self.persistenceAvailability = .unavailable
            }
        } catch {
            PersistenceDiagnostics.report(error, operation: "load search history")
            items = migrationFailed ? (legacyFallback ?? []) : []
            self.persistenceAvailability = .unavailable
        }
        if migrationFailed, items.isEmpty, let legacyFallback {
            items = legacyFallback
        }
    }

    @discardableResult
    func reload() -> Bool {
        do {
            let result = try Self.loadAndRepairItems(
                limit: limit,
                canRepair: persistentBackendIsAvailable,
                faultInjector: faultInjector
            )
            items = result.value
            if let error = result.repairError {
                PersistenceDiagnostics.report(error, operation: "repair search history")
                persistenceAvailability = .unavailable
                return false
            }
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "reload search history")
            persistenceAvailability = .unavailable
            return false
        }
    }

    @discardableResult
    func record(_ keyword: String) -> Bool {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return false }
        var updated = items.filter { Self.isSameKeyword($0, trimmed) == false }
        updated.insert(trimmed, at: 0)
        if updated.count > limit {
            updated = Array(updated.prefix(limit))
        }
        return persist(updated)
    }

    @discardableResult
    func remove(_ keyword: String) -> Bool {
        let updated = items.filter { Self.isSameKeyword($0, keyword) == false }
        guard updated.count != items.count else { return true }
        return persist(updated)
    }

    @discardableResult
    func clear() -> Bool {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            try PersistedRecordStore.saveSearchHistory([])
            defaults.removeObject(forKey: key)
            items = []
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "clear search history")
            persistenceAvailability = .unavailable
            return false
        }
    }

    private func persist(_ updated: [String]) -> Bool {
        guard persistentBackendIsAvailable else {
            persistenceAvailability = .unavailable
            return false
        }
        do {
            try PersistedRecordStore.saveSearchHistory(updated)
            items = updated
            markPersistenceSucceeded()
            return true
        } catch {
            PersistenceDiagnostics.report(error, operation: "save search history")
            persistenceAvailability = .unavailable
            return false
        }
    }

    private func markPersistenceSucceeded() {
        guard persistentBackendIsAvailable else { return }
        persistenceAvailability = .available
    }

    private static func isSameKeyword(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame
    }

    private static func loadAndRepairItems(
        limit: Int,
        canRepair: Bool,
        faultInjector: PersistenceFaultInjector = .none
    ) throws -> PersistenceLoadResult<[String]> {
        let raw = try PersistedRecordStore.loadSearchHistory()
        var seen = Set<String>()
        var sanitized: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            sanitized.append(trimmed)
            if sanitized.count == limit { break }
        }
        if canRepair, raw != sanitized {
            do {
                try faultInjector.check(.repair)
                try PersistedRecordStore.saveSearchHistory(sanitized)
            } catch {
                return PersistenceLoadResult(value: sanitized, repairError: error)
            }
        }
        return PersistenceLoadResult(value: sanitized, repairError: nil)
    }

    private static func migrateLegacyStorage(
        defaults: UserDefaults,
        key: String,
        limit: Int,
        destinationIsDurable: Bool,
        legacyFallback: inout [String]?,
        faultInjector: PersistenceFaultInjector
    ) throws {
        // legacy may be string array or data
        let existing = try PersistedRecordStore.loadSearchHistory()
        if existing.isEmpty == false { return }
        let source: [String]
        if let arr = defaults.stringArray(forKey: key) {
            source = arr
            legacyFallback = arr
        } else if let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([String].self, from: data) {
            source = decoded
            legacyFallback = decoded
        } else {
            return
        }
        var seen = Set<String>()
        var sanitized: [String] = []
        for item in source {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            let id = trimmed.lowercased()
            guard seen.insert(id).inserted else { continue }
            sanitized.append(trimmed)
            if sanitized.count == limit { break }
        }
        try LegacyStorageMigration.persistThenRemoveLegacyValue(
            defaults: defaults,
            key: key,
            destinationIsDurable: destinationIsDurable
        ) {
            try faultInjector.check(.legacyMigration)
            try PersistedRecordStore.saveSearchHistory(sanitized)
        }
    }
}
