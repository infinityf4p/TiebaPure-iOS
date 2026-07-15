import SwiftUI

struct BrowsingHistoryView: View {
    let account: Account?

    @ObservedObject private var historyStore = BrowsingHistoryStore.shared
    @State private var activeEntry: BrowsingHistoryEntry?
    @State private var showsClearConfirmation = false

    var body: some View {
        Group {
            if historyStore.items.isEmpty {
                ScrollView {
                    ReaderStateView.empty(
                        title: "暂无浏览历史",
                        message: "成功打开过的帖子会显示在这里。"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, TiebaPureTheme.Spacing.lg)
                }
                .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
                .accessibilityIdentifier("browsing-history-empty")
            } else {
                List {
                    ForEach(historyStore.items) { entry in
                        Button {
                            activeEntry = entry
                        } label: {
                            BrowsingHistoryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("browsing-history-row-\(entry.threadID)")
                        .accessibilityHint("打开该帖子")
                    }
                    .onDelete(perform: deleteEntries)
                }
                .listStyle(.plain)
                .accessibilityIdentifier("browsing-history-list")
            }
        }
        .navigationTitle("浏览历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if historyStore.items.isEmpty == false {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空") {
                        showsClearConfirmation = true
                    }
                    .minTouchTarget()
                    .accessibilityLabel("清空全部浏览历史")
                    .accessibilityIdentifier("browsing-history-clear-all")
                }
            }
        }
        .navigationDestination(isPresented: entryIsActive) {
            if let activeEntry {
                ThreadDetailView(
                    account: account,
                    threadID: activeEntry.threadID,
                    forumID: activeEntry.forumID
                )
            }
        }
        .confirmationDialog(
            "清空全部浏览历史？",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                historyStore.clear()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只会删除本机保存的帖子浏览记录。")
        }
        .onAppear {
            historyStore.reload()
        }
        .fullScreenInteractiveNavigationPop()
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
        let threadIDs = Set(offsets.compactMap { index in
            historyStore.items.indices.contains(index)
                ? historyStore.items[index].threadID
                : nil
        })
        historyStore.remove(threadIDs: threadIDs)
    }
}

private struct BrowsingHistoryRow: View {
    let entry: BrowsingHistoryEntry

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

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
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
