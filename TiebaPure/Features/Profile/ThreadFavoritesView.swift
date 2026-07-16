import SwiftUI

struct ThreadFavoritesView: View {
    let account: Account?

    @ObservedObject private var libraryStore = LocalThreadLibraryStore.shared
    @State private var activeFavorite: ThreadFavoriteEntry?
    @State private var showsClearFavoritesConfirmation = false
    @State private var showsClearReadingPositionsConfirmation = false

    var body: some View {
        Group {
            if libraryStore.favorites.isEmpty {
                ScrollView {
                    ReaderStateView.empty(
                        title: "暂无帖子收藏",
                        message: "在帖子页点击右上角的收藏按钮后，会显示在这里。"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, TiebaPureTheme.Spacing.lg)
                }
                .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
                .accessibilityIdentifier("thread-favorites-empty")
            } else {
                List {
                    ForEach(libraryStore.favorites) { favorite in
                        Button {
                            activeFavorite = favorite
                        } label: {
                            ThreadFavoriteRow(
                                favorite: favorite,
                                readingPosition: libraryStore.position(for: favorite.threadID)
                            )
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("thread-favorite-row-\(favorite.threadID)")
                        .accessibilityHint("打开收藏的帖子")
                    }
                    .onDelete(perform: deleteFavorites)
                }
                .listStyle(.plain)
                .accessibilityIdentifier("thread-favorites-list")
            }
        }
        .navigationTitle("帖子收藏")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if libraryStore.favorites.isEmpty == false || libraryStore.readingPositions.isEmpty == false {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if libraryStore.favorites.isEmpty == false {
                            Button(role: .destructive) {
                                showsClearFavoritesConfirmation = true
                            } label: {
                                Label("清空收藏", systemImage: "star.slash")
                            }
                        }

                        if libraryStore.readingPositions.isEmpty == false {
                            Button(role: .destructive) {
                                showsClearReadingPositionsConfirmation = true
                            } label: {
                                Label("清除阅读位置", systemImage: "bookmark.slash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .minTouchTarget()
                    .accessibilityLabel("管理本机帖子记录")
                    .accessibilityHint("清空收藏或清除阅读位置")
                    .accessibilityIdentifier("thread-library-manage")
                }
            }
        }
        .navigationDestination(isPresented: favoriteIsActive) {
            if let activeFavorite {
                ThreadDetailView(
                    account: account,
                    threadID: activeFavorite.threadID,
                    forumID: activeFavorite.forumID
                )
            }
        }
        .confirmationDialog(
            "清空全部帖子收藏？",
            isPresented: $showsClearFavoritesConfirmation,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                libraryStore.clearFavorites()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("阅读位置会继续保留，重新打开帖子时仍可继续阅读。")
        }
        .confirmationDialog(
            "清除全部帖子阅读位置？",
            isPresented: $showsClearReadingPositionsConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                libraryStore.clearReadingPositions()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除阅读位置，不会删除帖子收藏。")
        }
        .onAppear {
            libraryStore.reload()
        }
        .fullScreenInteractiveNavigationPop()
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

    private func deleteFavorites(at offsets: IndexSet) {
        let threadIDs = Set(offsets.compactMap { index in
            libraryStore.favorites.indices.contains(index)
                ? libraryStore.favorites[index].threadID
                : nil
        })
        libraryStore.removeFavorites(threadIDs: threadIDs)
    }
}

private struct ThreadFavoriteRow: View {
    let favorite: ThreadFavoriteEntry
    let readingPosition: ThreadReadingPosition?

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
            favorite.forumDisplayName,
            favorite.authorDisplayName,
            readingPosition.map { "上次读到 \($0.floor)楼" },
            "收藏于 \(ReaderDateText.string(from: favorite.savedAt))"
        ].compactMap { $0 }.filter { $0.isEmpty == false }
    }

    private var accessibilityText: String {
        ([favorite.title] + metadataItems).joined(separator: "，")
    }
}
