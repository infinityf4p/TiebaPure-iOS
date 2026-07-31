import Foundation
import ImageIO
import UIKit

enum TiebaEmoticonCacheError: Error, Equatable {
    case invalidImageName
    case invalidImageData
    case cacheUnavailable
}

enum TiebaEmoticonURLPolicy {
    static let host = "tb2.bdstatic.com"
    static let maximumNumericID = 999

    static func imageURL(for imageName: String) -> URL? {
        guard isValidImageName(imageName) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/tb/editor/images/client/\(imageName).png"
        return components.url
    }

    static func isAllowedResponseURL(_ url: URL?, imageName: String) -> Bool {
        guard isValidImageName(imageName),
              let url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == host,
              url.user == nil,
              url.password == nil else {
            return false
        }
        return url.path == "/tb/editor/images/client/\(imageName).png"
    }

    static func isValidImageName(_ value: String) -> Bool {
        guard value.hasPrefix("image_emoticon") else { return false }
        let suffix = value.dropFirst("image_emoticon".count)
        guard suffix.isEmpty == false,
              suffix.count <= String(maximumNumericID).count,
              suffix.first != "0",
              suffix.unicodeScalars.allSatisfy({ scalar in
                  scalar.value >= 48 && scalar.value <= 57
              }),
              let numericID = Int(suffix) else {
            return false
        }
        return (1...maximumNumericID).contains(numericID)
    }
}

enum TiebaEmoticonImagePolicy {
    static let maximumSourceDimension = 4_096
    static let maximumSourcePixels = 16_777_216
    static let maximumCachedDimension = 512
    static let maximumCachedPixels = 262_144

    static func allows(source: CGImageSource) -> Bool {
        guard CGImageSourceGetCount(source) == 1,
              let dimensions = dimensions(of: source),
              dimensions.width <= maximumSourceDimension,
              dimensions.height <= maximumSourceDimension else {
            return false
        }
        let (pixels, overflow) = dimensions.width.multipliedReportingOverflow(by: dimensions.height)
        return overflow == false && pixels <= maximumSourcePixels
    }

    static func thumbnail(from data: Data) -> UIImage? {
        guard data.isEmpty == false,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              allows(source: source) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumCachedDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              cgImage.width > 0,
              cgImage.height > 0,
              cgImage.width <= maximumCachedDimension,
              cgImage.height <= maximumCachedDimension else {
            return nil
        }
        let (pixels, overflow) = cgImage.width.multipliedReportingOverflow(by: cgImage.height)
        guard overflow == false, pixels <= maximumCachedPixels else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func dimensions(of source: CGImageSource) -> (width: Int, height: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            return nil
        }
        return (width, height)
    }
}

final class TiebaEmoticonCache: @unchecked Sendable {
    static let shared = TiebaEmoticonCache()

    private struct MemoryEntry {
        let image: UIImage
        let access: UInt64
    }

    private let fileManager: FileManager
    private let directory: URL?
    private let maximumMemoryEntries: Int
    private let maximumDiskEntries: Int
    private let maximumDiskBytes: Int64
    private let memoryLock = NSLock()
    private let diskLock = NSLock()
    private var images: [String: MemoryEntry] = [:]
    private var accessCounter: UInt64 = 0

    init(
        directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("TiebaPure/Emoticons", isDirectory: true),
        fileManager: FileManager = .default,
        maximumMemoryEntries: Int = 64,
        maximumDiskEntries: Int = 128,
        maximumDiskBytes: Int64 = 16 * 1_024 * 1_024
    ) {
        self.directory = directory
        self.fileManager = fileManager
        self.maximumMemoryEntries = max(1, maximumMemoryEntries)
        self.maximumDiskEntries = max(1, maximumDiskEntries)
        self.maximumDiskBytes = max(1, maximumDiskBytes)
        if let directory {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            pruneDiskCache(in: directory)
        }
    }

    func image(for imageName: String) -> UIImage? {
        guard TiebaEmoticonURLPolicy.isValidImageName(imageName) else { return nil }

        if let image = memoryImage(for: imageName) {
            return image
        }

        guard let url = fileURL(for: imageName) else { return nil }
        diskLock.lock()
        let data = try? Data(contentsOf: url, options: [.mappedIfSafe])
        diskLock.unlock()
        guard let data else {
            return nil
        }
        guard let image = Self.decodeImage(data) else {
            diskLock.lock()
            try? fileManager.removeItem(at: url)
            diskLock.unlock()
            return nil
        }

        memoryLock.lock()
        let resolved = images[imageName]?.image ?? image
        insertMemoryImage(resolved, for: imageName)
        memoryLock.unlock()
        diskLock.lock()
        try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        diskLock.unlock()
        return resolved
    }

    func memoryImage(for imageName: String) -> UIImage? {
        guard TiebaEmoticonURLPolicy.isValidImageName(imageName) else { return nil }

        memoryLock.lock()
        if let entry = images[imageName] {
            accessCounter &+= 1
            images[imageName] = MemoryEntry(image: entry.image, access: accessCounter)
            memoryLock.unlock()
            return entry.image
        }
        memoryLock.unlock()
        return nil
    }

    func fileURLIfPresent(for imageName: String) -> URL? {
        guard let url = fileURL(for: imageName) else { return nil }
        diskLock.lock()
        defer { diskLock.unlock() }
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              Self.decodeImage(data) != nil else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return url
    }

    @discardableResult
    func store(_ data: Data, for imageName: String) throws -> UIImage {
        guard TiebaEmoticonURLPolicy.isValidImageName(imageName) else {
            throw TiebaEmoticonCacheError.invalidImageName
        }
        guard let image = Self.decodeImage(data),
              let cachedData = image.pngData(),
              Int64(cachedData.count) <= maximumDiskBytes else {
            throw TiebaEmoticonCacheError.invalidImageData
        }
        guard let url = fileURL(for: imageName) else {
            throw TiebaEmoticonCacheError.cacheUnavailable
        }
        guard let directory else {
            throw TiebaEmoticonCacheError.cacheUnavailable
        }
        diskLock.lock()
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try cachedData.write(to: url, options: .atomic)
            pruneDiskCache(in: directory)
            diskLock.unlock()
        } catch {
            diskLock.unlock()
            throw error
        }

        memoryLock.lock()
        insertMemoryImage(image, for: imageName)
        memoryLock.unlock()
        return image
    }

    func remove(_ imageName: String) {
        guard TiebaEmoticonURLPolicy.isValidImageName(imageName) else { return }
        memoryLock.lock()
        images[imageName] = nil
        memoryLock.unlock()
        if let url = fileURL(for: imageName) {
            diskLock.lock()
            try? fileManager.removeItem(at: url)
            diskLock.unlock()
        }
    }

    private func fileURL(for imageName: String) -> URL? {
        guard TiebaEmoticonURLPolicy.isValidImageName(imageName) else { return nil }
        return directory?.appendingPathComponent("\(imageName).cache", isDirectory: false)
    }

    private static func decodeImage(_ data: Data) -> UIImage? {
        TiebaEmoticonImagePolicy.thumbnail(from: data)
    }

    private func insertMemoryImage(_ image: UIImage, for imageName: String) {
        accessCounter &+= 1
        images[imageName] = MemoryEntry(image: image, access: accessCounter)
        while images.count > maximumMemoryEntries,
              let oldest = images.min(by: { $0.value.access < $1.value.access })?.key {
            images[oldest] = nil
        }
    }

    private func pruneDiskCache(in directory: URL) {
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let entries: [(url: URL, modified: Date, bytes: Int64)] = urls.compactMap { url in
            guard url.pathExtension == "cache",
                  let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isRegularFile == true else {
                return nil
            }
            return (url, values.contentModificationDate ?? .distantPast, Int64(values.fileSize ?? 0))
        }.sorted { lhs, rhs in
            if lhs.modified != rhs.modified { return lhs.modified > rhs.modified }
            return lhs.url.lastPathComponent > rhs.url.lastPathComponent
        }

        var keptEntries = 0
        var keptBytes: Int64 = 0
        for entry in entries {
            let (newBytes, overflow) = keptBytes.addingReportingOverflow(entry.bytes)
            let shouldKeep = keptEntries < maximumDiskEntries
                && overflow == false
                && newBytes <= maximumDiskBytes
            if shouldKeep {
                keptEntries += 1
                keptBytes = newBytes
            } else {
                try? fileManager.removeItem(at: entry.url)
            }
        }
    }
}

final class TiebaEmoticonRequestGate: @unchecked Sendable {
    static let shared = TiebaEmoticonRequestGate()

    private let lock = NSLock()
    private let maximumActiveNames: Int
    private let maximumRetryEntries: Int
    private var activeNames: Set<String> = []
    private var retryAfter: [String: Date] = [:]
    private var saturatedRetryUntil: Date?

    init(maximumActiveNames: Int = 64, maximumRetryEntries: Int = 256) {
        self.maximumActiveNames = max(1, maximumActiveNames)
        self.maximumRetryEntries = max(1, maximumRetryEntries)
    }

    func begin(_ imageName: String, now: Date = Date()) -> Bool {
        guard TiebaEmoticonURLPolicy.isValidImageName(imageName) else { return false }
        lock.lock()
        defer { lock.unlock() }
        pruneExpiredFailures(at: now)
        guard activeNames.contains(imageName) == false else { return false }
        guard retryAfter[imageName].map({ $0 <= now }) ?? true else { return false }
        guard saturatedRetryUntil.map({ $0 <= now }) ?? true else { return false }
        guard activeNames.count < maximumActiveNames,
              retryAfter.count < maximumRetryEntries else {
            return false
        }
        activeNames.insert(imageName)
        return true
    }

    func finish(
        _ imageName: String,
        succeeded: Bool,
        now: Date = Date(),
        failureRetryInterval: TimeInterval = 5 * 60
    ) {
        guard TiebaEmoticonURLPolicy.isValidImageName(imageName) else { return }
        lock.lock()
        activeNames.remove(imageName)
        if succeeded {
            retryAfter[imageName] = nil
        } else {
            let deadline = now.addingTimeInterval(max(0, failureRetryInterval))
            if retryAfter[imageName] != nil || retryAfter.count < maximumRetryEntries {
                retryAfter[imageName] = deadline
            } else {
                saturatedRetryUntil = max(saturatedRetryUntil ?? deadline, deadline)
            }
        }
        lock.unlock()
    }

    private func pruneExpiredFailures(at now: Date) {
        retryAfter = retryAfter.filter { $0.value > now }
        if saturatedRetryUntil.map({ $0 <= now }) == true {
            saturatedRetryUntil = nil
        }
    }
}

private actor TiebaEmoticonDownloadLimiter {
    private let maximumConcurrentDownloads: Int
    private var activeDownloads = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maximumConcurrentDownloads: Int) {
        self.maximumConcurrentDownloads = max(1, maximumConcurrentDownloads)
    }

    func acquire() async {
        if activeDownloads < maximumConcurrentDownloads {
            activeDownloads += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if waiters.isEmpty {
            activeDownloads = max(0, activeDownloads - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

protocol TiebaEmoticonDownloading: Sendable {
    func download(from url: URL, imageName: String) async throws -> Data
}

struct TiebaEmoticonCDNClient: TiebaEmoticonDownloading, Sendable {
    static let shared = TiebaEmoticonCDNClient()
    static let maximumArtworkBytes = 1 * 1_024 * 1_024

    let session: URLSession

    init(session: URLSession = TiebaEmoticonCDNClient.makeSession()) {
        self.session = session
    }

    func download(from url: URL, imageName: String) async throws -> Data {
        guard TiebaEmoticonURLPolicy.isAllowedResponseURL(url, imageName: imageName) else {
            throw TiebaImageDownloadError.invalidURL
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 15
        request.setValue("image/png,image/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, rawResponse) = try await BoundedURLSession(session: session).data(
            for: request,
            maximumBytes: Self.maximumArtworkBytes,
            requiredMIMEPrefix: "image/"
        )
        guard let response = rawResponse as? HTTPURLResponse else {
            throw TiebaImageDownloadError.invalidResponse
        }
        guard (200...299).contains(response.statusCode) else {
            throw TiebaImageDownloadError.badStatus(response.statusCode)
        }
        guard TiebaEmoticonURLPolicy.isAllowedResponseURL(response.url, imageName: imageName),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              TiebaEmoticonImagePolicy.allows(source: source) else {
            throw TiebaImageDownloadError.invalidImageData
        }
        return data
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        return SecureRemoteURLSession.make(
            configuration: configuration,
            redirectScope: .bdStaticHTTPS
        )
    }
}

actor TiebaEmoticonRepository {
    static let shared = TiebaEmoticonRepository(
        cache: .shared,
        downloader: TiebaEmoticonCDNClient.shared,
        onArtworkAvailable: {
            await MainActor.run {
                TiebaEmoticonArtwork.shared.didFetch()
            }
        }
    )

    private let cache: TiebaEmoticonCache
    private let downloader: any TiebaEmoticonDownloading
    private let failureRetryInterval: TimeInterval
    private let maximumInFlightRequests: Int
    private let maximumNegativeEntries: Int
    private let now: @Sendable () -> Date
    private let onArtworkAvailable: @Sendable () async -> Void
    private let downloadLimiter: TiebaEmoticonDownloadLimiter
    private var inFlight: [String: Task<Bool, Never>] = [:]
    private var retryAfter: [String: Date] = [:]
    private var saturatedRetryUntil: Date?

    init(
        cache: TiebaEmoticonCache,
        downloader: any TiebaEmoticonDownloading,
        failureRetryInterval: TimeInterval = 5 * 60,
        maximumConcurrentDownloads: Int = 4,
        maximumInFlightRequests: Int = 64,
        maximumNegativeEntries: Int = 256,
        now: @escaping @Sendable () -> Date = { Date() },
        onArtworkAvailable: @escaping @Sendable () async -> Void = {}
    ) {
        self.cache = cache
        self.downloader = downloader
        self.failureRetryInterval = max(0, failureRetryInterval)
        self.maximumInFlightRequests = max(1, maximumInFlightRequests)
        self.maximumNegativeEntries = max(1, maximumNegativeEntries)
        self.now = now
        self.onArtworkAvailable = onArtworkAvailable
        self.downloadLimiter = TiebaEmoticonDownloadLimiter(
            maximumConcurrentDownloads: maximumConcurrentDownloads
        )
    }

    @discardableResult
    func fetch(_ imageName: String) async -> Bool {
        guard TiebaEmoticonURLPolicy.isValidImageName(imageName) else { return false }
        let currentDate = now()
        pruneExpiredFailures(at: currentDate)
        if cache.memoryImage(for: imageName) != nil {
            retryAfter[imageName] = nil
            return true
        }
        if cache.image(for: imageName) != nil {
            retryAfter[imageName] = nil
            await onArtworkAvailable()
            return true
        }
        if let retryDate = retryAfter[imageName], retryDate > currentDate { return false }
        if let existing = inFlight[imageName] {
            return await existing.value
        }
        guard saturatedRetryUntil.map({ $0 <= currentDate }) ?? true else { return false }
        guard retryAfter.count < maximumNegativeEntries else {
            saturatedRetryUntil = currentDate.addingTimeInterval(failureRetryInterval)
            return false
        }
        guard inFlight.count < maximumInFlightRequests else {
            recordFailure(for: imageName, at: currentDate)
            return false
        }
        guard let url = TiebaEmoticonURLPolicy.imageURL(for: imageName) else { return false }

        let cache = self.cache
        let downloader = self.downloader
        let callback = self.onArtworkAvailable
        let limiter = self.downloadLimiter
        let task = Task(priority: .utility) {
            await limiter.acquire()
            do {
                try Task.checkCancellation()
                let data = try await downloader.download(from: url, imageName: imageName)
                try Task.checkCancellation()
                try cache.store(data, for: imageName)
                await limiter.release()
                await callback()
                return true
            } catch {
                await limiter.release()
                return false
            }
        }
        inFlight[imageName] = task
        let succeeded = await task.value
        inFlight[imageName] = nil
        if succeeded {
            retryAfter[imageName] = nil
        } else {
            recordFailure(for: imageName, at: now())
        }
        return succeeded
    }

    private func pruneExpiredFailures(at currentDate: Date) {
        retryAfter = retryAfter.filter { $0.value > currentDate }
        if saturatedRetryUntil.map({ $0 <= currentDate }) == true {
            saturatedRetryUntil = nil
        }
    }

    private func recordFailure(for imageName: String, at currentDate: Date) {
        let deadline = currentDate.addingTimeInterval(failureRetryInterval)
        if retryAfter[imageName] != nil || retryAfter.count < maximumNegativeEntries {
            retryAfter[imageName] = deadline
        } else {
            saturatedRetryUntil = max(saturatedRetryUntil ?? deadline, deadline)
        }
    }
}
