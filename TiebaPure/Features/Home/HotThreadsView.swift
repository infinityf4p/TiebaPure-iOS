import SwiftUI
import UIKit

/// The two top-level tabs of the home feed. 推荐 is the personalized feed the
/// app has always shown; 热点 is the service's hot-thread listing.
enum HomeFeedSegment: String, CaseIterable, Identifiable, Sendable {
    case recommended
    case hot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recommended:
            return "推荐"
        case .hot:
            return "热点"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .recommended:
            return "显示个性化推荐的帖子"
        case .hot:
            return "显示贴吧热点帖子"
        }
    }
}

/// Decides whether a finished drag is a deliberate horizontal swipe between the
/// two home segments. 推荐 and 热点 are the only segments, so a swipe in either
/// direction moves to the other one: a right swipe leaves 推荐 for 热点, and a
/// left swipe leaves 热点 for 推荐.
///
/// The feed itself scrolls vertically, so a drag only counts once it is clearly
/// horizontal — otherwise a normal scroll with a little sideways drift would
/// jump the user to the other segment mid-read.
enum HomeFeedSwipePolicy {
    /// Drags shorter than this are scroll jitter, not a segment switch.
    static let minimumHorizontalDistance: CGFloat = 60
    /// A drag this diagonal or steeper stays a scroll.
    static let maximumVerticalToHorizontalRatio: CGFloat = 0.6
    /// The drag recognizer needs a little travel before it reports a gesture at
    /// all; the thresholds above still decide whether that gesture counts.
    static let gestureMinimumDistance: CGFloat = 12

    static func isHorizontalSwipe(translation: CGSize) -> Bool {
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)
        guard horizontalDistance >= minimumHorizontalDistance else { return false }
        return verticalDistance <= horizontalDistance * maximumVerticalToHorizontalRatio
    }

    static func toggled(_ segment: HomeFeedSegment) -> HomeFeedSegment {
        switch segment {
        case .recommended:
            return .hot
        case .hot:
            return .recommended
        }
    }
}

extension View {
    /// Reports only drags that end as a deliberate horizontal swipe. Attach it
    /// to the scrolling feed, never to a horizontally scrollable bar, so the
    /// bar keeps owning its own drags.
    func homeFeedSwipeGesture(onSwipe: @escaping () -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: HomeFeedSwipePolicy.gestureMinimumDistance)
                .onEnded { value in
                    guard HomeFeedSwipePolicy.isHorizontalSwipe(
                        translation: value.translation
                    ) else { return }
                    onSwipe()
                }
        )
    }
}

/// 热点 keeps its listing for the whole session. Switching to 推荐 and back only
/// hides and shows the same view, so re-activation must reuse the loaded
/// listing instead of firing another request; the listing is dropped only when
/// the account changes.
enum HotFeedLoadPolicy {
    static func shouldLoadOnActivation(isActive: Bool, didLoad: Bool) -> Bool {
        isActive && didLoad == false
    }
}

/// Which per-segment request counters a home-tab gesture must bump.
///
/// The home-tab gestures act on the segment that is on screen. Addressing the
/// hidden segment as well would scroll it away from where the user left it and
/// re-fetch a list nobody can see.
struct HomeFeedGestureTargets: Equatable {
    var scrollToTopSegment: HomeFeedSegment
    var refreshSegment: HomeFeedSegment
}

enum HomeFeedGestureTargetPolicy {
    static func targets(forActiveSegment active: HomeFeedSegment) -> HomeFeedGestureTargets {
        HomeFeedGestureTargets(
            scrollToTopSegment: active,
            refreshSegment: active
        )
    }
}

/// The 热点 half of the home feed.
///
/// The endpoint answers one listing per sub-tab and takes no page parameter, so
/// this view loads a whole tab at a time: a sub-tab switch replaces the list
/// instead of appending a page, and pulling down reloads the current sub-tab.
struct HotThreadsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.readingPreferences) private var readingPreferences
    @ObservedObject private var blocklistStore = BlocklistStore.shared

    let account: Account?
    /// Whether 热点 is the segment currently on screen. The view stays in the
    /// hierarchy while 推荐 is shown, so this decides when the first load may
    /// start; a later switch back must not fetch the listing again.
    let isActive: Bool
    /// Changed by a double tap on the 首页 tab: scroll the listing back to top.
    let scrollToTopToken: Int
    /// Changed by a long press on the 首页 tab: refresh the listing.
    let refreshToken: Int
    let onOpenThread: (ThreadSummary) -> Void
    let onOpenComments: (ThreadSummary) -> Void
    let onOpenForum: (Forum) -> Void
    let onOpenUser: (UserSummary) -> Void
    let onOpenTopic: (HotTopic) -> Void
    /// A horizontal swipe on the thread list switches the home segment. The
    /// sub-tab bar is deliberately outside this gesture: its own horizontal
    /// scroll owns drags that start there.
    let onHorizontalSwipe: () -> Void

    @State private var tabs: [HotTab] = []
    @State private var topics: [HotTopic] = []
    @State private var selectedTabCode = HotTab.allCode
    @State private var threads: [ThreadSummary] = []
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var errorMessage: String?
    @State private var requestGeneration = 0
    @State private var loadTask: Task<HotFeed, Error>?

    var body: some View {
        VStack(spacing: 0) {
            if tabs.isEmpty == false {
                hotTabBar
            }

            feedContent
                .homeFeedSwipeGesture(onSwipe: onHorizontalSwipe)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
        .task {
            guard HotFeedLoadPolicy.shouldLoadOnActivation(
                isActive: isActive,
                didLoad: didLoad
            ) else { return }
            await load(tabCode: selectedTabCode)
        }
        .onChange(of: isActive) { active in
            // First switch to 热点 loads once; every later switch back reuses
            // the listing already on screen.
            guard HotFeedLoadPolicy.shouldLoadOnActivation(
                isActive: active,
                didLoad: didLoad
            ) else { return }
            Task { await load(tabCode: selectedTabCode) }
        }
        .onChange(of: account?.sessionIdentity) { _ in
            requestGeneration += 1
            loadTask?.cancel()
            tabs = []
            topics = []
            selectedTabCode = HotTab.allCode
            threads = []
            errorMessage = nil
            didLoad = false
            isLoading = false
            // A hidden segment only drops its stale listing; the next
            // activation loads the new account's data.
            guard HotFeedLoadPolicy.shouldLoadOnActivation(
                isActive: isActive,
                didLoad: false
            ) else { return }
            Task { await load(tabCode: selectedTabCode) }
        }
        .onDisappear {
            loadTask?.cancel()
            requestGeneration += 1
            isLoading = false
        }
    }

    private var hotTabBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: TiebaPureTheme.Spacing.xs) {
                ForEach(tabs) { tab in
                    Button {
                        guard tab.code != selectedTabCode else { return }
                        selectedTabCode = tab.code
                        Task { await load(tabCode: tab.code) }
                    } label: {
                        CapsuleLabel(
                            tab.name,
                            isSelected: tab.code == selectedTabCode
                        )
                    }
                    .buttonStyle(.plain)
                    .minTouchTarget()
                    .accessibilityLabel(tab.name)
                    .accessibilityIdentifier("hot-thread-tab-\(tab.code)")
                }
            }
            .padding(.horizontal, TiebaPureTheme.Spacing.md)
            .padding(.vertical, TiebaPureTheme.Spacing.xs)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("hot-thread-tab-bar")
        .background(TiebaPureTheme.ColorToken.readerGroupedBackground)
    }

    /// 话题榜: the service sends the same hot topics with every listing, and the
    /// official page shows them above the threads. Tapping one opens its feed.
    private var hotTopicSection: some View {
        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.xs) {
            Text("热议话题")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                Button {
                    onOpenTopic(topic)
                } label: {
                    hotTopicRow(topic, rank: index)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("第\(index + 1)名 \(topic.name)，\(topic.discussCountText)讨论")
                .accessibilityHint("查看该话题的帖子")
                .accessibilityIdentifier("hot-topic-row")
            }
        }
        .padding(TiebaPureTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.card, style: .continuous)
                .fill(TiebaPureTheme.ColorToken.readerSecondarySurface)
        )
        .accessibilityIdentifier("hot-topic-section")
    }

    private func hotTopicRow(_ topic: HotTopic, rank: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TiebaPureTheme.Spacing.sm) {
            Text("\(rank + 1)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(topicRankColor(rank))
                .frame(minWidth: 18, alignment: .trailing)

            Text(topic.name)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)

            Spacer(minLength: TiebaPureTheme.Spacing.xs)

            Text(topic.discussCountText)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .frame(minHeight: 32)
    }

    /// The first three ranks carry the service's own red/orange/yellow accents.
    private func topicRankColor(_ index: Int) -> Color {
        switch index {
        case 0:
            return Color(red: 0.84, green: 0.0, blue: 0.0)
        case 1:
            return Color(red: 1.0, green: 0.43, blue: 0.0)
        case 2:
            return Color(red: 0.98, green: 0.75, blue: 0.18)
        default:
            return .secondary
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        if isLoading && didLoad == false {
            ReaderStateView.loading("正在加载热点")
        } else if let errorMessage, threads.isEmpty {
            ReaderStateScrollView(refresh: { await reload() }) {
                ReaderStateView.error(message: errorMessage) {
                    Task { await reload() }
                }
            }
        } else if threads.isEmpty {
            ReaderStateScrollView(refresh: { await reload() }) {
                ReaderStateView.empty(
                    title: "暂无热点",
                    message: "下拉即可刷新热点帖子。"
                )
            }
        } else {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Scroll anchor for the double tap on the 首页 tab. It
                        // sits outside the LazyVStack so it adds no spacing.
                        Color.clear
                            .frame(height: 0)
                            .id(HotFeedScrollTarget.top)

                        LazyVStack(spacing: TiebaPureTheme.Spacing.sm, pinnedViews: []) {
                            if topics.isEmpty == false {
                                hotTopicSection
                            }

                            ForEach(threads) { thread in
                                ForumThreadRow(
                                    thread: thread,
                                    presentation: .homeFeed,
                                    onOpenThread: { onOpenThread(thread) },
                                    onOpenForum: onOpenForum,
                                    onOpenUser: { onOpenUser($0) },
                                    onBlockForum: { blockedThread in
                                        blocklistStore.addForum(
                                            id: blockedThread.forumID,
                                            named: blockedThread.forumName
                                        )
                                    },
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
                                            onOpenThread(thread)
                                        }
                                    },
                                    onOpenComments: { onOpenComments(thread) },
                                    commentsAccessibilityIdentifier: "hot-comments-button-\(thread.id)"
                                )
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("thread-row")
                            }

                            if let errorMessage {
                                InlineLoadErrorView(message: errorMessage) {
                                    Task { await reload() }
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
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("hot-thread-scroll-view")
                .shortPullRefresh(
                    isEnabled: didLoad && isLoading == false,
                    surface: .grouped,
                    accessibilityIdentifier: "hot-thread-refresh-animation",
                    programmaticRefreshToken: refreshToken
                ) { source in
                    if source == .pullGesture {
                        guard isLoading == false else { return }
                    }
                    await reload()
                }
                .onChange(of: scrollToTopToken) { _ in
                    // Same transaction rules as the recommended feed: a lazy
                    // layout update during an animated jump can loop on iOS 26.
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        scrollProxy.scrollTo(HotFeedScrollTarget.top, anchor: .top)
                    }
                }
            }
        }
    }

    private func reload() async {
        await load(tabCode: selectedTabCode)
    }

    private func load(tabCode: String) async {
        loadTask?.cancel()
        requestGeneration += 1
        let generation = requestGeneration
        let requestedSession = account?.sessionIdentity
        isLoading = true
        errorMessage = nil

        do {
            let task = Task {
                try await environment.api.hotThreads(account: account, tabCode: tabCode)
            }
            loadTask = task
            let feed = try await task.value
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity else { return }
            tabs = feed.tabs
            topics = feed.topics
            threads = feed.threads.filter(TiebaContentFilter.shouldKeep(thread:))
            // A sub-tab the service stopped reporting must not leave the tab bar
            // pointing at a listing that can no longer be requested. 全部 is
            // always on the bar, so the selection falls back to it and the next
            // refresh puts the highlighted chip and the list back in agreement.
            if tabs.contains(where: { $0.code == tabCode }) == false {
                selectedTabCode = HotTab.allCode
            }
        } catch is CancellationError {
            guard generation == requestGeneration,
                  requestedSession == account?.sessionIdentity else { return }
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

private enum HotFeedScrollTarget {
    case top
}