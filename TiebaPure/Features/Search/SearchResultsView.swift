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
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var historyStore = SearchHistoryStore.shared
    let account: Account?
    let scope: SearchScope
    let initialKeyword: String

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
    @State private var selectedImagePreview: ImagePreviewSession?
    @State private var selectedVideoPreview: HomeVideoPreview?
    @State private var requestGeneration = 0
    @State private var loadTask: Task<SearchResultsPage, Error>?

    init(account: Account?, scope: SearchScope, initialKeyword: String) {
        self.account = account
        self.scope = scope
        self.initialKeyword = initialKeyword
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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: dismissSearchPage) {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .minTouchTarget()
                .accessibilityLabel("返回")
                .accessibilityHint("直接返回上一页面")
                .accessibilityIdentifier("search-back-button")
            }
        }
        .navigationDestination(isPresented: threadIsActive) {
            if let activeThread {
                ThreadDetailView(
                    account: account,
                    threadID: activeThread.threadID,
                    forumID: activeThread.forumID,
                    initialPostID: activeThread.postID
                )
            }
        }
        .navigationDestination(isPresented: forumIsActive) {
            if let activeForum {
                ForumThreadsView(account: account, forum: activeForum)
            }
        }
        .navigationDestination(isPresented: userIsActive) {
            if let selectedUser {
                UserProfileView(account: account, user: selectedUser)
            }
        }
        .refreshable { await reload() }
        .task {
            guard didLoad == false else { return }
            if submittedKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                isSearchFieldFocused = true
                return
            }
            await reload()
        }
        .onChange(of: account?.id) { _ in
            loadTask?.cancel()
            requestGeneration += 1
            results = []
            page = 1
            hasMore = true
            didLoad = false
            isLoading = false
            errorMessage = nil
            Task { await reload() }
        }
        .onDisappear {
            loadTask?.cancel()
            requestGeneration += 1
            isLoading = false
        }
        .fullScreenCover(item: $selectedImagePreview) { preview in
            FullScreenImageView(session: preview)
        }
        .fullScreenCover(item: $selectedVideoPreview) { preview in
            DirectVideoPlaybackView(video: preview.video)
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
                            historyStore.clear()
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
                                historyStore.remove(keyword)
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
                        ReaderStateView.empty(title: "没有结果", message: "可调整范围或排序后重试。")
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
                                        activeThread = SearchThreadRoute(threadID: result.threadID, forumID: result.forumID, postID: result.postID)
                                    },
                                    onOpenForum: { forum in
                                        RecentForumStore.shared.save(forum)
                                        activeForum = forum
                                    },
                                    onOpenUser: { selectedUser = $0 },
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
                                            activeThread = SearchThreadRoute(threadID: result.threadID, forumID: result.forumID, postID: result.postID)
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
                            }

                            Color.clear
                                .frame(height: 48)
                                .accessibilityHidden(true)
                        }
                        .padding(.horizontal, TiebaPureTheme.Spacing.sm)
                        .padding(.vertical, TiebaPureTheme.Spacing.sm)
                        .readableWidth()
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

    private func dismissSearchPage() {
        isSearchFieldFocused = false
        dismiss()
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

    private func loadMore(generation: Int) async {
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
        isLoading = true
        errorMessage = nil

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
                  key == currentRequestKey(page: requestedPage) else { return }
            if requestedPage == 1 {
                results = pageResult.results
            } else {
                let known = Set(results.map(\.id))
                results.append(contentsOf: pageResult.results.filter { known.contains($0.id) == false })
            }
            hasMore = pageResult.hasMore && pageResult.results.isEmpty == false
            if let followingPage = TiebaPaginationPolicy.nextPage(
                requestedPage: requestedPage,
                responseCurrentPage: pageResult.currentPage
            ) {
                page = followingPage
            } else {
                hasMore = false
            }
        } catch is CancellationError {
            guard generation == requestGeneration else { return }
            loadTask = nil
            isLoading = false
            return
        } catch {
            guard generation == requestGeneration, key == currentRequestKey(page: requestedPage) else { return }
            errorMessage = ReaderErrorMessage.message(for: error)
        }
        guard generation == requestGeneration else { return }
        loadTask = nil
        isLoading = false
        didLoad = true
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
    static func normalizedKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func adding(_ keyword: String, to items: [String], limit: Int) -> [String] {
        let normalized = normalizedKeyword(keyword)
        guard normalized.isEmpty == false, limit > 0 else {
            return Array(items.prefix(max(limit, 0)))
        }
        var updated = items.filter { isSameKeyword($0, normalized) == false }
        updated.insert(normalized, at: 0)
        return Array(updated.prefix(limit))
    }

    static func removing(_ keyword: String, from items: [String]) -> [String] {
        let normalized = normalizedKeyword(keyword)
        return items.filter { isSameKeyword($0, normalized) == false }
    }

    static func sanitized(_ items: [String], limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var result: [String] = []
        for item in items {
            let normalized = normalizedKeyword(item)
            guard normalized.isEmpty == false,
                  result.contains(where: { isSameKeyword($0, normalized) }) == false else {
                continue
            }
            result.append(normalized)
            if result.count == limit { break }
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
    @Published private(set) var items: [String]

    init(
        defaults: UserDefaults = .standard,
        key: String = "dev.infinityf4p.tiebapure.searchHistory",
        limit: Int = 20
    ) {
        self.defaults = defaults
        self.key = key
        self.limit = max(limit, 0)
        items = SearchHistoryPolicy.sanitized(
            defaults.stringArray(forKey: key) ?? [],
            limit: max(limit, 0)
        )
    }

    func reload() {
        items = SearchHistoryPolicy.sanitized(
            defaults.stringArray(forKey: key) ?? [],
            limit: limit
        )
    }

    func record(_ keyword: String) {
        persist(SearchHistoryPolicy.adding(keyword, to: items, limit: limit))
    }

    func remove(_ keyword: String) {
        persist(SearchHistoryPolicy.removing(keyword, from: items))
    }

    func clear() {
        defaults.removeObject(forKey: key)
        items = []
    }

    private func persist(_ updated: [String]) {
        defaults.set(updated, forKey: key)
        items = updated
    }
}
