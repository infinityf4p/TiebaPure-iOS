import SwiftUI

enum TiebaVideoSourcePolicy {
    static func videoURL(_ url: URL?) -> URL? {
        TiebaVideoRemotePolicy.url(url?.absoluteString)
    }

    static func webpageURL(_ url: URL?) -> URL? {
        TiebaURL.webpage(url?.absoluteString)
    }
}

enum VideoPreviewSourceIdentityPolicy {
    static func identity(for video: VideoContent) -> String {
        [
            "video",
            video.videoURL?.absoluteString ?? "",
            video.coverURL?.absoluteString ?? "",
            video.webURL?.absoluteString ?? "",
            String(video.width),
            String(video.height),
            String(video.duration)
        ].joined(separator: "|")
    }
}

enum VideoPreviewReusePolicy {
    static func effectiveLoadState(
        storedState: TiebaRemoteImageLoadState,
        storedIdentity: String?,
        currentIdentity: String
    ) -> TiebaRemoteImageLoadState {
        storedIdentity == currentIdentity ? storedState : .empty
    }

    static func isManualLoadAuthorized(
        authorizedIdentity: String?,
        currentIdentity: String
    ) -> Bool {
        authorizedIdentity == currentIdentity
    }

    static func canUseSourceAnchor(
        anchorIdentity: String,
        currentIdentity: String
    ) -> Bool {
        anchorIdentity == currentIdentity
    }
}

struct VideoPlayerView: View {
    @Environment(\.readingPreferences) private var readingPreferences
    @Environment(\.displayScale) private var displayScale

    let video: VideoContent

    @State private var coverLoadState: TiebaRemoteImageLoadState = .empty
    @State private var coverLoadStateIdentity: String?
    @State private var manualCoverAuthorization: String?
    @StateObject private var previewSource: ImagePreviewSourceAnchor
    private let previewSourceIdentity: String

    init(video: VideoContent) {
        self.video = video
        let identity = VideoPreviewSourceIdentityPolicy.identity(for: video)
        previewSourceIdentity = identity
        _previewSource = StateObject(
            wrappedValue: ImagePreviewSourceAnchor(sourceIdentity: identity)
        )
    }

    var body: some View {
        Group {
            if resolvedVideoURL != nil || resolvedWebURL != nil {
                Button(action: activateVideo) {
                    thumbnail
                }
                .buttonStyle(.plain)
                .minTouchTarget()
                .accessibilityLabel(videoAccessibilityLabel)
                .accessibilityHint(videoAccessibilityHint)
            } else {
                thumbnail
                    .accessibilityLabel("视频不可用")
            }
        }
        .onChangeCompat(of: previewSourceIdentity, initial: true) { (_: String, identity: String) in
            coverLoadState = .empty
            coverLoadStateIdentity = identity
            manualCoverAuthorization = nil
            previewSource.prepareForReuse(sourceIdentity: identity)
        }
    }

    private func activateVideo() {
        if effectiveCoverLoadState == .failure {
            openVideo()
        } else if effectiveCoverLoadState == .empty,
                  isManualCoverMode {
            manualCoverAuthorization = previewSourceIdentity
        } else if effectiveCoverLoadState == .loading,
                  ReaderMediaActivationPolicy.blocksWhileLoading(
                    requestPolicy: mediaRequestPolicy
                  ) {
            return
        } else {
            openVideo()
        }
    }

    private func openVideo() {
        previewSource.prepareForReuse(sourceIdentity: previewSourceIdentity)
        let sourceAnchor = VideoPreviewReusePolicy.canUseSourceAnchor(
            anchorIdentity: previewSource.sourceIdentity,
            currentIdentity: previewSourceIdentity
        ) ? previewSource : nil
        VideoPreviewCoordinator.shared.present(
            VideoPreviewSession(
                video: video,
                sourceFrame: ImagePreviewSourceRegistry.shared
                    .frameInWindow(for: previewSourceIdentity)
                    ?? sourceAnchor?.frameInWindow,
                sourceImage: sourceAnchor?.image,
                sourceAnchor: sourceAnchor,
                sourceIdentity: previewSourceIdentity
            )
        )
    }

    private var resolvedVideoURL: URL? {
        TiebaVideoSourcePolicy.videoURL(video.videoURL)
    }

    private var resolvedWebURL: URL? {
        TiebaVideoSourcePolicy.webpageURL(video.webURL)
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous)
                .fill(TiebaPureTheme.ColorToken.readerTertiarySurface)

            if let coverURL = video.coverURL {
                GeometryReader { proxy in
                    TiebaRemoteImage(
                        primaryURL: coverURL,
                        targetPixelSize: TiebaImageDecodePolicy.previewTargetPixelSize(
                            for: proxy.size,
                            displayScale: displayScale
                        ),
                        contentMode: .fill,
                        showsProgress: true,
                        showsRetryButton: false,
                        showsResolvedImage: false,
                        loadsAutomatically: mediaRequestPolicy.loadsAutomatically || isManualCoverLoadAuthorized,
                        onLoadStateChange: {
                            coverLoadState = $0
                            coverLoadStateIdentity = previewSourceIdentity
                            if $0 != .success {
                                previewSource.clearImage(sourceIdentity: previewSourceIdentity)
                            }
                        },
                        onImageResolved: {
                            previewSource.store(
                                image: $0,
                                sourceIdentity: previewSourceIdentity
                            )
                        }
                    )
                }

                ImagePreviewSourceAnchorReader(
                    anchor: previewSource,
                    sourceIdentity: previewSourceIdentity,
                    onTransitionTap: activateVideo
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            } else {
                placeholderIcon
            }

            if waitsForManualCoverLoad == false || effectiveCoverLoadState != .empty {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: TiebaPureTheme.IconSize.play))
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .accessibilityHidden(true)
            }

            if waitsForManualCoverLoad,
               effectiveCoverLoadState == .empty {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let durationText {
                Text(durationText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.7), in: Capsule())
                    .padding(TiebaPureTheme.Spacing.xs)
            }
        }
        .aspectRatio(inlineAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous))
    }

    private var placeholderIcon: some View {
        Image(systemName: "play.rectangle.fill")
            .font(.system(size: 30))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    private var inlineAspectRatio: CGFloat {
        max(0.5, min(CGFloat(video.aspectRatio), 2.0))
    }

    private var durationText: String? {
        guard video.duration > 0 else { return nil }

        let seconds = video.duration > 10_000 ? video.duration / 1_000 : video.duration
        return [seconds / 60, seconds % 60]
            .map { String(format: "%02d", $0) }
            .joined(separator: ":")
    }

    private var mediaRequestPolicy: ReaderMediaRequestPolicy {
        ReaderMediaRequestPolicy.resolve(readingPreferences.mediaLoading)
    }

    private var waitsForManualCoverLoad: Bool {
        isManualCoverMode && isManualCoverLoadAuthorized == false
    }

    private var isManualCoverMode: Bool {
        video.coverURL != nil && mediaRequestPolicy.loadsAutomatically == false
    }

    private var isManualCoverLoadAuthorized: Bool {
        VideoPreviewReusePolicy.isManualLoadAuthorized(
            authorizedIdentity: manualCoverAuthorization,
            currentIdentity: previewSourceIdentity
        )
    }

    private var effectiveCoverLoadState: TiebaRemoteImageLoadState {
        VideoPreviewReusePolicy.effectiveLoadState(
            storedState: coverLoadState,
            storedIdentity: coverLoadStateIdentity,
            currentIdentity: previewSourceIdentity
        )
    }

    private var videoAccessibilityLabel: String {
        switch effectiveCoverLoadState {
        case .empty where waitsForManualCoverLoad:
            return "加载视频封面"
        case .loading:
            return "正在加载视频封面"
        case .failure:
            return "播放视频，封面加载失败"
        case .empty, .success:
            return "播放视频"
        }
    }

    private var videoAccessibilityHint: String {
        switch effectiveCoverLoadState {
        case .empty where waitsForManualCoverLoad:
            return "加载当前视频封面"
        case .loading:
            return "请等待视频封面加载完成"
        case .failure:
            return "封面不可用，仍可打开视频播放器"
        case .empty, .success:
            return "打开全屏视频播放器"
        }
    }
}
