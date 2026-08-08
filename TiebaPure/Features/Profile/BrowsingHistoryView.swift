import Foundation
import SwiftUI

struct BrowsingHistoryView: View {
    let account: Account?

    @Environment(\.editMode) private var editMode
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var historyStore = BrowsingHistoryStore.shared
    @ObservedObject private var blocklistStore = BlocklistStore.shared
    @State private var activeEntry: BrowsingHistoryEntry?
    @State private var searchText = ""
    @State private var dateFilter: BrowsingHistoryDateFilter = .all
    @State private var dateFilterReferenceDate = Date()
    @State private var selectedThreadIDs = Set<Int64>()
    @State private var pendingDeletionThreadIDs = Set<Int64>()
    @State private var showsClearConfirmation = false
    @State private var showsDeleteSelectionConfirmation = false
    @State private var showsPersistenceError = false

    var body: some View {
        VStack(spacing: 0) {
            if historyStore.items.isEmpty == false {
                dateFilterPicker
            }

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .navigationTitle("浏览历史")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "搜索标题、作者或贴吧"
        )
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(allVisibleEntriesAreSelected ? "取消全选" : "全选") {
                        selectedThreadIDs = LocalThreadListSelectionPolicy
                            .selectionByTogglingAll(
                                selectedThreadIDs,
                                visibleThreadIDs: visibleThreadIDs
                            )
                    }
                    .disabled(visibleEntries.isEmpty)
                    .accessibilityIdentifier("browsing-history-select-all")
                }
            }

            if isEditing == false, historyStore.items.isEmpty == false {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("清空") {
                        showsClearConfirmation = true
                    }
                    .minTouchTarget()
                    .accessibilityLabel("清空全部浏览历史")
                    .accessibilityIdentifier("browsing-history-clear-all")
                }
            }

            if visibleEntries.isEmpty == false || isEditing {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                        .minTouchTarget()
                        .accessibilityIdentifier("browsing-history-edit")
                }
            }

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            selectionBar
        }
        .navigationDestinationCompat(isPresented: entryIsActive) {
            if let activeEntry {
                ThreadDetailView(
                    account: account,
                    threadID: activeEntry.threadID,
                    forumID: activeEntry.forumID
                )
                .interactiveNavigationPopStateSync {
                    self.activeEntry = nil
                }
            }
        }
        .confirmationDialog(
            "清空全部浏览历史？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                Task {
                    if await historyStore.clearInBackground() == false {
                        showsPersistenceError = true
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会删除本机保存的帖子浏览记录。")
        }
        .confirmationDialog(
            "删除选中的 \(pendingDeletionThreadIDs.count) 条浏览历史？",
            isPresented: $showsDeleteSelectionConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                deleteSelectedEntries(threadIDs: pendingDeletionThreadIDs)
                pendingDeletionThreadIDs.removeAll()
            }
            Button("取消", role: .cancel) {
                pendingDeletionThreadIDs.removeAll()
            }
        } message: {
            Text("删除后无法恢复。")
        }
        .alert("操作失败", isPresented: $showsPersistenceError) {
            Button("好", role: .cancel) {}
        } message: {
            Text("未能保存浏览历史更改，请稍后重试。")
        }
        .task {
            await historyStore.waitForPendingMutations()
            guard Task.isCancelled == false else { return }
            historyStore.reload()
            dateFilterReferenceDate = Date()
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
            guard let activeEntry,
                  BrowsingHistoryListPolicy.shouldKeep(
                    activeEntry,
                    blocklist: currentBlocklist
                  ) == false else { return }
            self.activeEntry = nil
        }
        .onChangeCompat(of: scenePhase) { _, phase in
            if phase == .active {
                dateFilterReferenceDate = Date()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            dateFilterReferenceDate = Date()
        }
        .fullScreenInteractiveNavigationPop()
    }

    @ViewBuilder
    private var content: some View {
        if visibleEntries.isEmpty {
            ScrollView {
                ReaderStateView.empty(
                    title: emptyState.title,
                    message: emptyState.message
                )
                .frame(maxWidth: .infinity)
                .padding(.top, TiebaPureTheme.Spacing.lg)
            }
            .accessibilityIdentifier("browsing-history-empty")
        } else {
            List(selection: $selectedThreadIDs) {
                ForEach(visibleEntries) { entry in
                    Group {
                        if isEditing {
                            BrowsingHistoryRow(
                                entry: entry,
                                showsDisclosureIndicator: false
                            )
                        } else {
                            Button {
                                activeEntry = entry
                            } label: {
                                BrowsingHistoryRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .tag(entry.threadID)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("browsing-history-row-\(entry.threadID)")
                    .accessibilityHint(isEditing ? "选择或取消选择" : "打开该帖子")
                }
                .onDelete(perform: deleteEntries)
            }
            .listStyle(.plain)
            .accessibilityIdentifier("browsing-history-list")
        }
    }

    private var dateFilterPicker: some View {
        Picker("时间范围", selection: $dateFilter) {
            ForEach(BrowsingHistoryDateFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 360)
        .frame(minHeight: 44)
        .padding(.horizontal, TiebaPureTheme.Spacing.md)
        .padding(.vertical, TiebaPureTheme.Spacing.xs)
        .accessibilityIdentifier("browsing-history-date-filter")
    }

    @ViewBuilder
    private var selectionBar: some View {
        if isEditing {
            HStack(spacing: TiebaPureTheme.Spacing.md) {
                Text("已选 \(selectedThreadIDs.count) 项")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("browsing-history-selection-count")

                Spacer(minLength: TiebaPureTheme.Spacing.sm)

                Button(role: .destructive) {
                    pendingDeletionThreadIDs = selectedThreadIDs
                    showsDeleteSelectionConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedThreadIDs.isEmpty)
                .minTouchTarget()
                .accessibilityLabel("删除选中的浏览历史")
                .accessibilityIdentifier("browsing-history-delete-selected")
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

    private var visibleEntries: [BrowsingHistoryEntry] {
        BrowsingHistoryListPolicy.visibleEntries(
            historyStore.items,
            blocklist: currentBlocklist,
            searchText: searchText,
            dateFilter: dateFilter,
            referenceDate: dateFilterReferenceDate
        )
    }

    private var visibleThreadIDs: [Int64] {
        visibleEntries.map(\.threadID)
    }

    private var allVisibleEntriesAreSelected: Bool {
        visibleThreadIDs.isEmpty == false
            && selectedThreadIDs == Set(visibleThreadIDs)
    }

    private var emptyState: (title: String, message: String) {
        if historyStore.items.isEmpty {
            return ("暂无浏览历史", "成功打开过的帖子会显示在这里。")
        }
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            || dateFilter != .all {
            return ("没有匹配的浏览历史", "尝试调整搜索内容或时间范围。")
        }
        return ("没有可显示的浏览历史", "已按你的屏蔽设置隐藏相关记录。")
    }

    private var entryIsActive: Binding<Bool> {
        Binding(
            get: { activeEntry != nil },
            set: { isPresented in
                if isPresented == false {
                    activeEntry = nil
                }
            }
        )
    }

    private func deleteEntries(at offsets: IndexSet) {
        let threadIDs = BrowsingHistoryListPolicy.threadIDs(
            at: offsets,
            in: visibleEntries
        )
        Task {
            if await historyStore.removeInBackground(threadIDs: threadIDs) == false {
                showsPersistenceError = true
            }
        }
    }

    private func deleteSelectedEntries(threadIDs: Set<Int64>) {
        guard threadIDs.isEmpty == false else { return }
        Task {
            guard await historyStore.removeInBackground(threadIDs: threadIDs) else {
                showsPersistenceError = true
                return
            }
            selectedThreadIDs.subtract(threadIDs)
            if visibleEntries.isEmpty {
                editMode?.wrappedValue = .inactive
            }
        }
    }

    private func synchronizeSelection() {
        selectedThreadIDs = LocalThreadListSelectionPolicy.retainedSelection(
            selectedThreadIDs,
            visibleThreadIDs: visibleThreadIDs
        )
        if isEditing, visibleEntries.isEmpty {
            editMode?.wrappedValue = .inactive
        }
    }
}

enum BrowsingHistoryDateFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case lastSevenDays

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            return "全部"
        case .today:
            return "今天"
        case .lastSevenDays:
            return "近 7 天"
        }
    }
}

enum BrowsingHistoryListPolicy {
    static func visibleEntries(
        _ entries: [BrowsingHistoryEntry],
        blocklist: BlocklistSnapshot,
        searchText: String = "",
        dateFilter: BrowsingHistoryDateFilter = .all,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [BrowsingHistoryEntry] {
        entries.filter { entry in
            shouldKeep(entry, blocklist: blocklist)
                && LocalThreadListSearchPolicy.matches(
                    query: searchText,
                    fields: [
                        entry.title,
                        entry.authorDisplayName,
                        entry.forumDisplayName,
                        String(entry.threadID)
                    ]
                )
                && dateFilter.includes(
                    entry.visitedAt,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
        }
    }

    static func shouldKeep(
        _ entry: BrowsingHistoryEntry,
        blocklist: BlocklistSnapshot
    ) -> Bool {
        if blocklist.blocksUser(id: 0, names: [entry.authorDisplayName]) {
            return false
        }
        if blocklist.containsKeyword(in: entry.title) {
            return false
        }
        if blocklist.blocksForum(
            id: entry.forumID,
            names: entry.forumDisplayName.map { [$0] } ?? []
        ) {
            return false
        }
        return true
    }

    static func threadIDs(
        at offsets: IndexSet,
        in visibleEntries: [BrowsingHistoryEntry]
    ) -> Set<Int64> {
        Set(offsets.compactMap { index in
            visibleEntries.indices.contains(index)
                ? visibleEntries[index].threadID
                : nil
        })
    }
}

private extension BrowsingHistoryDateFilter {
    func includes(
        _ date: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            guard let interval = calendar.dateInterval(of: .day, for: referenceDate) else {
                return false
            }
            return date >= interval.start && date < interval.end
        case .lastSevenDays:
            guard let today = calendar.dateInterval(of: .day, for: referenceDate),
                  let lowerBound = calendar.date(byAdding: .day, value: -6, to: today.start)
            else { return false }
            return date >= lowerBound && date < today.end
        }
    }
}

private struct BrowsingHistoryRow: View {
    let entry: BrowsingHistoryEntry
    var showsDisclosureIndicator = true

    var body: some View {
        HStack(alignment: .center, spacing: TiebaPureTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
                Text(entry.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                MetadataLine(metadataItems, systemImage: "clock")
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
            entry.forumDisplayName,
            entry.authorDisplayName,
            "浏览于 \(ReaderDateText.string(from: entry.visitedAt))"
        ].compactMap { $0 }.filter { $0.isEmpty == false }
    }

    private var accessibilityText: String {
        ([entry.title] + metadataItems).joined(separator: "，")
    }
}
