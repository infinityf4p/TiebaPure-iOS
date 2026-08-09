import SwiftUI

/// Identity of a thread shown in the trailing detail column of the
/// regular-width reader layout.
struct ReaderSplitThreadRoute: Hashable {
    let threadID: Int64
    let forumID: Int64?
    let initialPostID: UInt64?
    let ownThreadDeletionTarget: OwnThreadDeletionTarget?

    init(
        threadID: Int64,
        forumID: Int64?,
        initialPostID: UInt64? = nil,
        ownThreadDeletionTarget: OwnThreadDeletionTarget? = nil
    ) {
        self.threadID = threadID
        self.forumID = forumID
        self.initialPostID = initialPostID
        self.ownThreadDeletionTarget = ownThreadDeletionTarget
    }
}

/// Action injected into the leading column of `ReaderSplitLayout`. Thread
/// lists that find it hand thread opens to the shared detail column instead
/// of pushing onto their local stack. The detail column deliberately leaves
/// it unset so lists pushed inside the detail column keep plain pushes.
struct ReaderSplitOpenThreadAction {
    let open: (ReaderSplitThreadRoute) -> Void

    func callAsFunction(_ route: ReaderSplitThreadRoute) {
        open(route)
    }
}

private struct ReaderSplitOpenThreadKey: EnvironmentKey {
    static let defaultValue: ReaderSplitOpenThreadAction? = nil
}

private struct ReaderSplitListColumnKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var readerSplitOpenThread: ReaderSplitOpenThreadAction? {
        get { self[ReaderSplitOpenThreadKey.self] }
        set { self[ReaderSplitOpenThreadKey.self] = newValue }
    }

    var isReaderSplitListColumn: Bool {
        get { self[ReaderSplitListColumnKey.self] }
        set { self[ReaderSplitListColumnKey.self] = newValue }
    }
}

enum ReaderSplitColumnWidthPolicy {
    private static let minimumListWidth: CGFloat = 320
    private static let maximumListWidth: CGFloat = 560
    private static let minimumDetailWidth: CGFloat = 440
    private static let listFraction: CGFloat = 0.4

    static func preferredWidth(containerWidth: CGFloat) -> CGFloat {
        guard containerWidth.isFinite, containerWidth > 0 else { return 400 }
        let maximumLeavingDetail = max(containerWidth - minimumDetailWidth, 0)
        return min(
            max(containerWidth * listFraction, minimumListWidth),
            min(maximumListWidth, maximumLeavingDetail)
        )
    }
}

/// Detail-column resting state before any thread is selected.
struct ReaderSplitDetailPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "选择一个帖子开始阅读",
            systemImage: "text.bubble",
            description: Text("从左侧列表中打开的帖子会显示在这里。")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .accessibilityIdentifier("split-detail-placeholder")
    }
}

/// Two-column reader layout for regular-width screens. The leading column
/// hosts the tab's existing navigation stack; thread opens from lists inside
/// it land in a shared detail column. Compact width keeps the plain stack so
/// iPhone and narrow iPad Split View behavior is unchanged.
struct ReaderSplitLayout<Route: Hashable, ListColumn: View, DetailRoot: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let account: Account?
    @Binding var navigationPath: [Route]
    @Binding var detailPath: [ReaderSplitThreadRoute]
    var openThreadInDetail: ((ReaderSplitThreadRoute) -> Void)?
    var openThreadInCompact: ((ReaderSplitThreadRoute) -> Void)?
    let listColumn: () -> ListColumn
    let detailRoot: (ReaderSplitDetailPlaceholder) -> DetailRoot

    init(
        account: Account?,
        navigationPath: Binding<[Route]>,
        detailPath: Binding<[ReaderSplitThreadRoute]>,
        openThreadInDetail: ((ReaderSplitThreadRoute) -> Void)? = nil,
        openThreadInCompact: ((ReaderSplitThreadRoute) -> Void)? = nil,
        @ViewBuilder listColumn: @escaping () -> ListColumn,
        detailRoot: @escaping (ReaderSplitDetailPlaceholder) -> DetailRoot
    ) {
        self.account = account
        _navigationPath = navigationPath
        _detailPath = detailPath
        self.openThreadInDetail = openThreadInDetail
        self.openThreadInCompact = openThreadInCompact
        self.listColumn = listColumn
        self.detailRoot = detailRoot
    }

    var body: some View {
        if horizontalSizeClass == .regular {
            GeometryReader { geometry in
                let leadingColumnWidth = ReaderSplitColumnWidthPolicy.preferredWidth(
                    containerWidth: geometry.size.width
                )

                splitNavigation(leadingColumnWidth: leadingColumnWidth)
            }
        } else {
            compactNavigation
        }
    }

    private func splitNavigation(leadingColumnWidth: CGFloat) -> some View {
        NavigationSplitView(columnVisibility: .constant(.doubleColumn)) {
            NavigationStack(path: $navigationPath) {
                listColumn()
            }
            // A sidebar toggle could hide the list and strand the detail
            // thread without a way back.
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(leadingColumnWidth)
            .environment(\.isReaderSplitListColumn, true)
            .environment(
                \.readerSplitOpenThread,
                ReaderSplitOpenThreadAction(open: resolvedOpenThread)
            )
        } detail: {
            NavigationStack(path: $detailPath) {
                detailRoot(ReaderSplitDetailPlaceholder())
                    .navigationDestination(for: ReaderSplitThreadRoute.self) { route in
                        ThreadDetailView(
                            account: account,
                            threadID: route.threadID,
                            forumID: route.forumID,
                            initialPostID: route.initialPostID,
                            ownThreadDeletionTarget: route.ownThreadDeletionTarget
                        )
                        // Replacing the selection must never reuse the
                        // previous thread's loaded state.
                        .id(route)
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var compactNavigation: some View {
        NavigationStack(path: $navigationPath) {
            listColumn()
        }
        // A compact handler lets the parent keep ownership of a thread opened
        // by a nested list. The same selection remains transferable when the
        // horizontal size class changes between compact and regular.
        .environment(\.readerSplitOpenThread, compactOpenThreadAction)
    }

    private var resolvedOpenThread: (ReaderSplitThreadRoute) -> Void {
        openThreadInDetail ?? { route in detailPath = [route] }
    }

    private var compactOpenThreadAction: ReaderSplitOpenThreadAction? {
        openThreadInCompact.map { ReaderSplitOpenThreadAction(open: $0) }
    }
}

extension ReaderSplitLayout where DetailRoot == ReaderSplitDetailPlaceholder {
    init(
        account: Account?,
        navigationPath: Binding<[Route]>,
        detailPath: Binding<[ReaderSplitThreadRoute]>,
        openThreadInDetail: ((ReaderSplitThreadRoute) -> Void)? = nil,
        openThreadInCompact: ((ReaderSplitThreadRoute) -> Void)? = nil,
        @ViewBuilder listColumn: @escaping () -> ListColumn
    ) {
        self.init(
            account: account,
            navigationPath: navigationPath,
            detailPath: detailPath,
            openThreadInDetail: openThreadInDetail,
            openThreadInCompact: openThreadInCompact,
            listColumn: listColumn,
            detailRoot: { $0 }
        )
    }
}
