import SwiftUI
import UIKit
import ImageIO

enum TiebaImageRequestPolicy {
    static let maximumRetryCount = 2

    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .returnCacheDataElseLoad,
            timeoutInterval: 20
        )
        request.setValue("tieba/12.52.1.0 skin/default", forHTTPHeaderField: "User-Agent")
        request.setValue("https://tieba.baidu.com/", forHTTPHeaderField: "Referer")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        return request
    }

    static func shouldRetry(statusCode: Int, attempt: Int) -> Bool {
        guard attempt < maximumRetryCount else { return false }
        return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }

    static func shouldRetry(error: Error, attempt: Int) -> Bool {
        guard attempt < maximumRetryCount else { return false }
        let code = (error as? URLError)?.code
        return code == .timedOut
            || code == .networkConnectionLost
            || code == .notConnectedToInternet
            || code == .cannotConnectToHost
            || code == .cannotFindHost
    }

    static func retryDelayNanoseconds(after attempt: Int) -> UInt64 {
        UInt64(250_000_000 * max(attempt + 1, 1))
    }
}

enum TiebaImageSourcePolicy {
    private static let syntheticFailureHost = "fixture.invalid"

    static func urls(primary: URL?, fallback: URL? = nil) -> [URL] {
        var result: [URL] = []
        for candidate in [primary, fallback].compactMap({ $0 }) {
            guard let safeURL = TiebaURL.image(candidate.absoluteString),
                  result.contains(safeURL) == false else {
                continue
            }
            result.append(safeURL)
        }
        return result
    }

    /// UI-test fixtures use this reserved host to exercise the accessible
    /// failure and retry states without consulting DNS or the network stack.
    static func isSyntheticFailureURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == syntheticFailureHost
    }
}

enum TiebaImageDecodePolicy {
    static let maximumSourceDimension = 32_768
    static let maximumSourcePixels = 100_000_000

    static func allows(width: Int, height: Int) -> Bool {
        guard width > 0, height > 0,
              width <= maximumSourceDimension,
              height <= maximumSourceDimension else {
            return false
        }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        return overflow == false && pixels <= maximumSourcePixels
    }
}

private enum TiebaImagePipelineError: Error {
    case invalidURL
    case invalidResponse
    case badStatus(Int)
    case invalidImageData
    case noSource
}

actor TiebaImagePipeline {
    static let shared = TiebaImagePipeline()
    static let maximumImageBytes = 30 * 1_024 * 1_024

    private let memoryCache = NSCache<NSURL, UIImage>()
    private let urlCache: URLCache
    private let session: URLSession
    private var inFlight: [URL: Task<UIImage, Error>] = [:]

    init() {
        let configuration = URLSessionConfiguration.default
        let urlCache = URLCache(
            memoryCapacity: 64 * 1_024 * 1_024,
            diskCapacity: 256 * 1_024 * 1_024,
            diskPath: "TiebaPureImages"
        )
        configuration.urlCache = urlCache
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        self.urlCache = urlCache
        session = SecureRemoteURLSession.make(configuration: configuration, redirectScope: .publicHTTPS)
        memoryCache.totalCostLimit = 96 * 1_024 * 1_024
        memoryCache.countLimit = 300
    }

    func clearCaches() {
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
        memoryCache.removeAllObjects()
        urlCache.removeAllCachedResponses()
    }

    func image(from urls: [URL]) async throws -> UIImage {
        guard urls.isEmpty == false else { throw TiebaImagePipelineError.noSource }

        var latestError: Error = TiebaImagePipelineError.noSource
        for url in urls {
            do {
                return try await image(from: url)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                latestError = error
            }
        }
        throw latestError
    }

    private func image(from url: URL) async throws -> UIImage {
        guard TiebaURL.image(url.absoluteString) != nil else {
            throw TiebaImagePipelineError.invalidURL
        }
        guard TiebaImageSourcePolicy.isSyntheticFailureURL(url) == false else {
            throw TiebaImagePipelineError.invalidImageData
        }
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached
        }
        if let task = inFlight[url] {
            return try await task.value
        }

        let session = session
        let task = Task<UIImage, Error> {
            try await Self.download(url: url, session: session)
        }
        inFlight[url] = task

        do {
            let image = try await task.value
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memoryCache.setObject(image, forKey: url as NSURL, cost: cost)
            inFlight[url] = nil
            return image
        } catch {
            inFlight[url] = nil
            throw error
        }
    }

    private static func download(url: URL, session: URLSession) async throws -> UIImage {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await BoundedURLSession(session: session).data(
                    for: TiebaImageRequestPolicy.request(for: url),
                    maximumBytes: maximumImageBytes,
                    requiredMIMEPrefix: "image/"
                )
                guard let response = response as? HTTPURLResponse else {
                    throw TiebaImagePipelineError.invalidResponse
                }
                guard (200...299).contains(response.statusCode) else {
                    if TiebaImageRequestPolicy.shouldRetry(statusCode: response.statusCode, attempt: attempt) {
                        try await Task.sleep(
                            nanoseconds: TiebaImageRequestPolicy.retryDelayNanoseconds(after: attempt)
                        )
                        attempt += 1
                        continue
                    }
                    throw TiebaImagePipelineError.badStatus(response.statusCode)
                }
                guard let image = decodedImage(from: data) else {
                    throw TiebaImagePipelineError.invalidImageData
                }
                return image
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard TiebaImageRequestPolicy.shouldRetry(error: error, attempt: attempt) else {
                    throw error
                }
                try await Task.sleep(
                    nanoseconds: TiebaImageRequestPolicy.retryDelayNanoseconds(after: attempt)
                )
                attempt += 1
            }
        }
    }

    private static func decodedImage(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              TiebaImageDecodePolicy.allows(width: width, height: height) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4_096,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}

@MainActor
private final class TiebaRemoteImageModel: ObservableObject {
    enum Phase {
        case empty
        case loading
        case success(UIImage)
        case failure
    }

    @Published private(set) var phase: Phase = .empty
    private var sourceKey = ""
    private var task: Task<Void, Never>?

    deinit {
        task?.cancel()
    }

    func load(urls: [URL], force: Bool = false) {
        let key = urls.map(\.absoluteString).joined(separator: "|")
        guard force || key != sourceKey || isFailed else { return }
        sourceKey = key
        task?.cancel()

        guard urls.isEmpty == false else {
            phase = .failure
            return
        }

        if case .success = phase, force == false {
            return
        }
        phase = .loading
        task = Task {
            do {
                let image = try await TiebaImagePipeline.shared.image(from: urls)
                guard Task.isCancelled == false else { return }
                phase = .success(image)
            } catch is CancellationError {
                return
            } catch {
                guard Task.isCancelled == false else { return }
                phase = .failure
            }
        }
    }

    private var isFailed: Bool {
        if case .failure = phase { return true }
        return false
    }

    var loadState: TiebaRemoteImageLoadState {
        switch phase {
        case .empty:
            return .empty
        case .loading:
            return .loading
        case .success:
            return .success
        case .failure:
            return .failure
        }
    }
}

enum TiebaRemoteImageLoadState: Equatable, Sendable {
    case empty
    case loading
    case success
    case failure
}

struct TiebaRemoteImage: View {
    let urls: [URL]
    var contentMode: ContentMode = .fill
    var showsProgress = false
    var retryTrigger = 0
    var showsRetryButton = true
    var onLoadStateChange: ((TiebaRemoteImageLoadState) -> Void)?

    @StateObject private var model = TiebaRemoteImageModel()

    init(
        primaryURL: URL?,
        fallbackURL: URL? = nil,
        contentMode: ContentMode = .fill,
        showsProgress: Bool = false,
        retryTrigger: Int = 0,
        showsRetryButton: Bool = true,
        onLoadStateChange: ((TiebaRemoteImageLoadState) -> Void)? = nil
    ) {
        urls = TiebaImageSourcePolicy.urls(primary: primaryURL, fallback: fallbackURL)
        self.contentMode = contentMode
        self.showsProgress = showsProgress
        self.retryTrigger = retryTrigger
        self.showsRetryButton = showsRetryButton
        self.onLoadStateChange = onLoadStateChange
    }

    var body: some View {
        Group {
            switch model.phase {
            case let .success(image):
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            case .empty, .loading:
                if showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Color.clear
                }
            case .failure:
                if showsRetryButton {
                    Button {
                        model.load(urls: urls, force: true)
                    } label: {
                        retryLabel
                    }
                    .accessibilityLabel("图片加载失败")
                    .accessibilityHint("点按重新加载图片")
                } else {
                    retryLabel
                        .accessibilityHidden(true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(urls.map(\.absoluteString).joined(separator: "|"))#\(retryTrigger)") {
            model.load(urls: urls, force: retryTrigger > 0)
        }
        .onChange(of: model.loadState) { state in
            onLoadStateChange?(state)
        }
        .onAppear {
            onLoadStateChange?(model.loadState)
        }
    }

    private var retryLabel: some View {
        Label("图片加载失败，点按重试", systemImage: "arrow.clockwise")
            .labelStyle(.iconOnly)
            .font(.system(size: 24))
            .foregroundStyle(.secondary)
            .minTouchTarget()
            .contentShape(Rectangle())
    }
}

struct AvatarView: View {
    let url: URL?
    let title: String?
    let size: CGFloat

    init(url: URL?, title: String? = nil, size: CGFloat = TiebaPureTheme.AvatarSize.medium) {
        self.url = url
        self.title = title
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(TiebaPureTheme.ColorToken.readerTertiarySurface)

            if let url {
                TiebaRemoteImage(
                    primaryURL: url,
                    contentMode: .fill,
                    showsProgress: true,
                    showsRetryButton: false
                )
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(title.map { "\($0)头像" } ?? "头像")
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: max(13, size * 0.42), weight: .medium))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }
}
