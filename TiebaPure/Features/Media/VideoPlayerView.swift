import AVKit
import SafariServices
import SwiftUI

struct VideoPlayerView: View {
    let video: VideoContent

    @State private var showsPlayer = false
    @State private var showsSafari = false
    @State private var coverLoadState: TiebaRemoteImageLoadState = .empty
    @State private var coverRetryTrigger = 0

    var body: some View {
        Group {
            if video.videoURL != nil || video.webURL != nil {
                Button {
                    if coverLoadState == .failure {
                        coverRetryTrigger += 1
                    } else {
                        openVideo()
                    }
                } label: {
                    thumbnail
                }
                .buttonStyle(.plain)
                .minTouchTarget()
                .accessibilityLabel(coverLoadState == .failure ? "视频封面加载失败，重新加载" : "播放视频")
                .accessibilityHint(coverLoadState == .failure ? "重新请求视频封面" : "打开视频播放器")
            } else {
                thumbnail
                    .accessibilityLabel("视频不可用")
            }
        }
        .fullScreenCover(isPresented: $showsPlayer) {
            if let videoURL = video.videoURL {
                FullScreenVideoPlayer(url: videoURL)
            }
        }
        .sheet(isPresented: $showsSafari) {
            if let webURL = video.webURL {
                SafariView(url: webURL)
                    .ignoresSafeArea()
            }
        }
    }

    private func openVideo() {
        if video.videoURL != nil {
            showsPlayer = true
        } else if video.webURL != nil {
            showsSafari = true
        }
    }

    private var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.media, style: .continuous)
                .fill(TiebaPureTheme.ColorToken.readerTertiarySurface)

            if let coverURL = video.coverURL {
                TiebaRemoteImage(
                    primaryURL: coverURL,
                    contentMode: .fill,
                    showsProgress: true,
                    retryTrigger: coverRetryTrigger,
                    showsRetryButton: false,
                    onLoadStateChange: { coverLoadState = $0 }
                )
            } else {
                placeholderIcon
            }

            Image(systemName: "play.circle.fill")
                .font(.system(size: TiebaPureTheme.IconSize.play))
                .foregroundStyle(.white)
                .shadow(radius: 3)
                .accessibilityHidden(true)
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
        return [
            seconds / 60,
            seconds % 60
        ]
        .map { String(format: "%02d", $0) }
        .joined(separator: ":")
    }
}

struct DirectVideoPlaybackView: View {
    let video: VideoContent

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let videoURL = video.videoURL {
                FullScreenVideoPlayer(url: videoURL)
            } else if let webURL = video.webURL {
                SafariView(url: webURL)
                    .ignoresSafeArea()
            } else {
                unavailableView
            }
        }
    }

    private var unavailableView: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            Text("视频不可用")
                .font(.body.weight(.medium))
                .foregroundStyle(.white)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: TiebaPureTheme.IconSize.toolbar, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("关闭视频")
            .padding(TiebaPureTheme.Spacing.md)
        }
    }
}

private struct FullScreenVideoPlayer: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        self.url = url
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            VideoPlayer(player: player)
                .ignoresSafeArea()

            Button {
                player.pause()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: TiebaPureTheme.IconSize.toolbar, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .accessibilityLabel("关闭视频")
            .padding(TiebaPureTheme.Spacing.md)
        }
        .onAppear {
            player.play()
        }
        .onDisappear {
            player.pause()
        }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
