import Foundation
import UIKit
import XCTest
@testable import TiebaPure

final class EmoticonResourceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        EmoticonURLProtocol.reset()
        try super.tearDownWithError()
    }

    func testClassicEmoticonNamesResolveWithoutBundledArtwork() {
        let expectedNamesByImageName = [
            "image_emoticon1": "呵呵", "image_emoticon2": "哈哈",
            "image_emoticon3": "吐舌", "image_emoticon4": "啊",
            "image_emoticon5": "酷", "image_emoticon6": "怒",
            "image_emoticon7": "开心", "image_emoticon8": "汗",
            "image_emoticon9": "泪", "image_emoticon10": "黑线",
            "image_emoticon11": "鄙视", "image_emoticon12": "不高兴",
            "image_emoticon13": "真棒", "image_emoticon14": "钱",
            "image_emoticon15": "疑问", "image_emoticon16": "阴险",
            "image_emoticon17": "吐", "image_emoticon18": "咦",
            "image_emoticon19": "委屈", "image_emoticon20": "花心",
            "image_emoticon21": "呼~", "image_emoticon22": "笑眼",
            "image_emoticon23": "冷", "image_emoticon24": "太开心",
            "image_emoticon25": "滑稽", "image_emoticon26": "勉强",
            "image_emoticon27": "狂汗", "image_emoticon28": "乖",
            "image_emoticon29": "睡觉", "image_emoticon30": "惊哭",
            "image_emoticon31": "生气", "image_emoticon32": "惊讶",
            "image_emoticon33": "喷", "image_emoticon34": "爱心",
            "image_emoticon35": "心碎", "image_emoticon36": "玫瑰",
            "image_emoticon37": "礼物", "image_emoticon38": "彩虹",
            "image_emoticon39": "星星月亮", "image_emoticon40": "太阳",
            "image_emoticon41": "钱币", "image_emoticon42": "灯泡",
            "image_emoticon43": "茶杯", "image_emoticon44": "蛋糕",
            "image_emoticon45": "音乐", "image_emoticon46": "haha",
            "image_emoticon47": "胜利", "image_emoticon48": "大拇指",
            "image_emoticon49": "弱", "image_emoticon50": "OK",
            "image_emoticon89": "噗"
        ]

        XCTAssertEqual(expectedNamesByImageName.count, 51)
        for (imageName, name) in expectedNamesByImageName {
            XCTAssertEqual(TiebaEmoticon.imageName(for: name), imageName, name)
        }
    }

    func testBracketedAliasesAndUnknownCodesKeepReadableFallbacks() {
        XCTAssertEqual(TiebaEmoticon.blocks(from: "摸摸[小乖]继续"), [
            .text("摸摸"), .emoticon(code: "小乖"), .text("继续")
        ])
        XCTAssertEqual(TiebaEmoticon.imageName(for: "小乖"), "image_emoticon28")
        XCTAssertEqual(TiebaEmoticon.imageName(for: "[小乖]"), "image_emoticon28")
        XCTAssertNil(TiebaEmoticon.imageName(for: "不存在的表情"))
        XCTAssertEqual(TiebaEmoticon.displayText(for: "不存在的表情"), "[不存在的表情]")
    }

    func testExtendedNamesAndBoundedNumericCodesResolve() {
        let expectedNamesByImageName = [
            "image_emoticon77": "沙发", "image_emoticon78": "手纸",
            "image_emoticon79": "香蕉", "image_emoticon80": "便便",
            "image_emoticon81": "药丸", "image_emoticon82": "红领巾",
            "image_emoticon83": "蜡烛", "image_emoticon84": "三道杠"
        ]

        XCTAssertEqual(TiebaEmoticon.imageName(for: "image_emoticon61"), "image_emoticon61")
        XCTAssertEqual(TiebaEmoticon.imageName(for: "image_emoticon125"), "image_emoticon125")
        XCTAssertEqual(TiebaEmoticon.imageName(for: "image_emoticon999"), "image_emoticon999")
        XCTAssertNil(TiebaEmoticon.imageName(for: "image_emoticon0"))
        XCTAssertNil(TiebaEmoticon.imageName(for: "image_emoticon01"))
        XCTAssertNil(TiebaEmoticon.imageName(for: "image_emoticon1000"))
        XCTAssertNil(TiebaEmoticon.imageName(for: "image_emoticon１２５"))
        for (imageName, name) in expectedNamesByImageName {
            XCTAssertEqual(TiebaEmoticon.imageName(for: name), imageName, name)
        }
    }

    func testCDNURLFactoryAcceptsOnlyNumericEmoticonNames() throws {
        let url = try XCTUnwrap(TiebaEmoticon.remoteImageURL(imageName: "image_emoticon125"))
        XCTAssertEqual(url.absoluteString, "https://tb2.bdstatic.com/tb/editor/images/client/image_emoticon125.png")
        XCTAssertNil(TiebaEmoticon.remoteImageURL(imageName: "../image_emoticon1"))
        XCTAssertNil(TiebaEmoticon.remoteImageURL(imageName: "image_emoticon1/../../secret"))
        XCTAssertNil(TiebaEmoticon.remoteImageURL(imageName: "image_emoticon"))
        XCTAssertNil(TiebaEmoticon.remoteImageURL(imageName: "image_emoticon1000"))
    }

    func testDiskCacheReturnsOneDecodedInstanceAndDeletesCorruption() throws {
        let directory = temporaryDirectory()
        let cache = TiebaEmoticonCache(directory: directory)
        let stored = try cache.store(Self.pngData, for: "image_emoticon25")
        let memoryHit = try XCTUnwrap(cache.image(for: "image_emoticon25"))
        XCTAssertTrue(stored === memoryHit)

        let reloadedCache = TiebaEmoticonCache(directory: directory)
        XCTAssertNil(reloadedCache.memoryImage(for: "image_emoticon25"))
        XCTAssertNotNil(reloadedCache.image(for: "image_emoticon25"))

        let corruptURL = directory.appendingPathComponent("image_emoticon50.cache")
        try Data("not an image".utf8).write(to: corruptURL, options: .atomic)
        XCTAssertNil(reloadedCache.image(for: "image_emoticon50"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: corruptURL.path))
    }

    func testCacheDownsamplesArtworkAndBoundsMemoryAndDiskEntries() throws {
        let directory = temporaryDirectory()
        let cache = TiebaEmoticonCache(
            directory: directory,
            maximumMemoryEntries: 1,
            maximumDiskEntries: 2,
            maximumDiskBytes: 2 * 1_024 * 1_024
        )
        let oversizedArtwork = Self.pngData(width: 1_024, height: 768)
        let first = try cache.store(oversizedArtwork, for: "image_emoticon1")
        XCTAssertLessThanOrEqual(try XCTUnwrap(first.cgImage).width, TiebaEmoticonImagePolicy.maximumCachedDimension)
        XCTAssertLessThanOrEqual(try XCTUnwrap(first.cgImage).height, TiebaEmoticonImagePolicy.maximumCachedDimension)

        _ = try cache.store(Self.pngData, for: "image_emoticon2")
        let reloadedFirst = try XCTUnwrap(cache.image(for: "image_emoticon1"))
        XCTAssertFalse(first === reloadedFirst, "The first memory entry should have been evicted and decoded from disk")
        _ = try cache.store(Self.pngData, for: "image_emoticon3")

        let diskEntries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.pathExtension == "cache" }
        XCTAssertLessThanOrEqual(diskEntries.count, 2)
        let totalBytes = try diskEntries.reduce(Int64(0)) { total, url in
            total + Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        XCTAssertLessThanOrEqual(totalBytes, 2 * 1_024 * 1_024)
    }

    func testCacheRejectsArtworkBeyondSourceDimensionLimit() throws {
        let cache = TiebaEmoticonCache(directory: temporaryDirectory())
        let oversizedSource = Self.pngData(
            width: TiebaEmoticonImagePolicy.maximumSourceDimension + 1,
            height: 1
        )

        XCTAssertThrowsError(try cache.store(oversizedSource, for: "image_emoticon25")) { error in
            XCTAssertEqual(error as? TiebaEmoticonCacheError, .invalidImageData)
        }
    }

    func testDiskCachePrunesToEncodedByteBudget() throws {
        let directory = temporaryDirectory()
        let singleCachedPayload = try XCTUnwrap(
            TiebaEmoticonImagePolicy.thumbnail(from: Self.pngData)?.pngData()
        )
        let cache = TiebaEmoticonCache(
            directory: directory,
            maximumMemoryEntries: 2,
            maximumDiskEntries: 10,
            maximumDiskBytes: Int64(singleCachedPayload.count)
        )

        _ = try cache.store(Self.pngData, for: "image_emoticon1")
        _ = try cache.store(Self.pngData, for: "image_emoticon2")

        let diskEntries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.pathExtension == "cache" }
        let totalBytes = try diskEntries.reduce(Int64(0)) { total, url in
            total + Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        }
        XCTAssertEqual(diskEntries.count, 1)
        XCTAssertLessThanOrEqual(totalBytes, Int64(singleCachedPayload.count))
    }

    func testRepositoryDeduplicatesConcurrentFetchesAndPublishesOnce() async throws {
        let cache = TiebaEmoticonCache(directory: temporaryDirectory())
        let downloader = EmoticonDownloaderStub(result: .success(Self.pngData), delayNanoseconds: 40_000_000)
        let notifications = EmoticonNotificationRecorder()
        let repository = TiebaEmoticonRepository(
            cache: cache,
            downloader: downloader,
            onArtworkAvailable: { await notifications.record() }
        )

        async let first = repository.fetch("image_emoticon25")
        async let second = repository.fetch("image_emoticon25")
        async let third = repository.fetch("image_emoticon25")
        let results = await [first, second, third]
        let requestCount = await downloader.requestCount()
        let notificationCount = await notifications.count()

        XCTAssertEqual(results, [true, true, true])
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(notificationCount, 1)
        XCTAssertNotNil(cache.image(for: "image_emoticon25"))
    }

    func testRepositoryLoadsDiskCacheOffRenderPathAndPublishesOnce() async throws {
        let directory = temporaryDirectory()
        let writer = TiebaEmoticonCache(directory: directory)
        _ = try writer.store(Self.pngData, for: "image_emoticon25")

        let reader = TiebaEmoticonCache(directory: directory)
        let downloader = EmoticonDownloaderStub(result: .failure(.offline))
        let notifications = EmoticonNotificationRecorder()
        let repository = TiebaEmoticonRepository(
            cache: reader,
            downloader: downloader,
            onArtworkAvailable: { await notifications.record() }
        )

        XCTAssertNil(reader.memoryImage(for: "image_emoticon25"))
        let loadedFromDisk = await repository.fetch("image_emoticon25")
        let requestCount = await downloader.requestCount()
        let notificationCount = await notifications.count()
        XCTAssertTrue(loadedFromDisk)
        XCTAssertNotNil(reader.memoryImage(for: "image_emoticon25"))
        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(notificationCount, 1)
    }

    func testRepositorySuppressesFailureUntilFiniteRetryDeadline() async throws {
        let cache = TiebaEmoticonCache(directory: temporaryDirectory())
        let downloader = EmoticonDownloaderStub(result: .failure(.offline))
        let clock = EmoticonTestClock(Date(timeIntervalSince1970: 1_000))
        let repository = TiebaEmoticonRepository(
            cache: cache,
            downloader: downloader,
            failureRetryInterval: 60,
            now: { clock.now }
        )

        let initialFetch = await repository.fetch("image_emoticon25")
        XCTAssertFalse(initialFetch)
        await downloader.setResult(.success(Self.pngData))
        let suppressedFetch = await repository.fetch("image_emoticon25")
        let suppressedRequestCount = await downloader.requestCount()
        XCTAssertFalse(suppressedFetch)
        XCTAssertEqual(suppressedRequestCount, 1)

        clock.advance(by: 61)
        let retriedFetch = await repository.fetch("image_emoticon25")
        let retriedRequestCount = await downloader.requestCount()
        XCTAssertTrue(retriedFetch)
        XCTAssertEqual(retriedRequestCount, 2)
    }

    func testRepositoryBoundsConcurrentDownloads() async throws {
        let cache = TiebaEmoticonCache(directory: temporaryDirectory())
        let downloader = EmoticonDownloaderStub(
            result: .success(Self.pngData),
            delayNanoseconds: 80_000_000
        )
        let repository = TiebaEmoticonRepository(
            cache: cache,
            downloader: downloader,
            maximumConcurrentDownloads: 2,
            maximumInFlightRequests: 8
        )

        let results = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for numericID in 1...6 {
                group.addTask {
                    await repository.fetch("image_emoticon\(numericID)")
                }
            }
            var values: [Bool] = []
            for await value in group { values.append(value) }
            return values
        }

        let requestCount = await downloader.requestCount()
        let maximumConcurrentRequestCount = await downloader.maximumConcurrentRequestCount()
        XCTAssertEqual(results.filter { $0 }.count, 6)
        XCTAssertEqual(requestCount, 6)
        XCTAssertLessThanOrEqual(maximumConcurrentRequestCount, 2)
    }

    func testRepositoryCapsNegativeCacheAndRecoversAfterDeadline() async throws {
        let cache = TiebaEmoticonCache(directory: temporaryDirectory())
        let downloader = EmoticonDownloaderStub(result: .failure(.offline))
        let clock = EmoticonTestClock(Date(timeIntervalSince1970: 2_000))
        let repository = TiebaEmoticonRepository(
            cache: cache,
            downloader: downloader,
            failureRetryInterval: 60,
            maximumNegativeEntries: 2,
            now: { clock.now }
        )

        let firstFailure = await repository.fetch("image_emoticon1")
        let secondFailure = await repository.fetch("image_emoticon2")
        XCTAssertFalse(firstFailure)
        XCTAssertFalse(secondFailure)
        await downloader.setResult(.success(Self.pngData))
        let suppressedFetch = await repository.fetch("image_emoticon3")
        let suppressedRequestCount = await downloader.requestCount()
        XCTAssertFalse(suppressedFetch)
        XCTAssertEqual(suppressedRequestCount, 2)

        clock.advance(by: 61)
        let recoveredFetch = await repository.fetch("image_emoticon3")
        let recoveredRequestCount = await downloader.requestCount()
        XCTAssertTrue(recoveredFetch)
        XCTAssertEqual(recoveredRequestCount, 3)
    }

    func testSynchronousRequestGateDeduplicatesAndAllowsTimedRetry() {
        let gate = TiebaEmoticonRequestGate()
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(gate.begin("image_emoticon25", now: start))
        XCTAssertFalse(gate.begin("image_emoticon25", now: start))
        gate.finish(
            "image_emoticon25",
            succeeded: false,
            now: start,
            failureRetryInterval: 60
        )
        XCTAssertFalse(gate.begin("image_emoticon25", now: start.addingTimeInterval(59)))
        XCTAssertTrue(gate.begin("image_emoticon25", now: start.addingTimeInterval(60)))
    }

    func testSynchronousRequestGateBoundsActiveAndNegativeEntries() {
        let gate = TiebaEmoticonRequestGate(maximumActiveNames: 2, maximumRetryEntries: 2)
        let start = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(gate.begin("image_emoticon1", now: start))
        XCTAssertTrue(gate.begin("image_emoticon2", now: start))
        XCTAssertFalse(gate.begin("image_emoticon3", now: start))
        gate.finish("image_emoticon1", succeeded: false, now: start, failureRetryInterval: 60)
        gate.finish("image_emoticon2", succeeded: false, now: start, failureRetryInterval: 60)
        XCTAssertFalse(gate.begin("image_emoticon3", now: start.addingTimeInterval(59)))
        XCTAssertTrue(gate.begin("image_emoticon3", now: start.addingTimeInterval(61)))
    }

    func testCDNClientRejectsWrongMIMEAndDeclaredOversize() async throws {
        let client = TiebaEmoticonCDNClient(session: Self.mockSession())
        let url = try XCTUnwrap(TiebaEmoticonURLPolicy.imageURL(for: "image_emoticon25"))

        EmoticonURLProtocol.configure(data: Self.pngData, mimeType: "text/html")
        do {
            _ = try await client.download(from: url, imageName: "image_emoticon25")
            XCTFail("Expected MIME rejection")
        } catch let error as TiebaHTTPError {
            guard case .invalidMIMEType = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        EmoticonURLProtocol.configure(
            data: Data(),
            mimeType: "image/png",
            declaredLength: TiebaEmoticonCDNClient.maximumArtworkBytes + 1
        )
        do {
            _ = try await client.download(from: url, imageName: "image_emoticon25")
            XCTFail("Expected size rejection")
        } catch let error as TiebaHTTPError {
            guard case let .responseTooLarge(limit) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(limit, TiebaEmoticonCDNClient.maximumArtworkBytes)
        }
    }

    func testCDNClientAcceptsBoundedDecodableImage() async throws {
        EmoticonURLProtocol.configure(data: Self.pngData, mimeType: "image/png")
        let client = TiebaEmoticonCDNClient(session: Self.mockSession())
        let url = try XCTUnwrap(TiebaEmoticonURLPolicy.imageURL(for: "image_emoticon25"))

        let data = try await client.download(from: url, imageName: "image_emoticon25")

        XCTAssertEqual(data, Self.pngData)
        XCTAssertEqual(EmoticonURLProtocol.requestCount, 1)
    }

    func testCDNClientRejectsImageBeyondEmoticonDimensionLimit() async throws {
        let oversizedSource = Self.pngData(
            width: TiebaEmoticonImagePolicy.maximumSourceDimension + 1,
            height: 1
        )
        EmoticonURLProtocol.configure(data: oversizedSource, mimeType: "image/png")
        let client = TiebaEmoticonCDNClient(session: Self.mockSession())
        let url = try XCTUnwrap(TiebaEmoticonURLPolicy.imageURL(for: "image_emoticon25"))

        do {
            _ = try await client.download(from: url, imageName: "image_emoticon25")
            XCTFail("Expected source dimension rejection")
        } catch {
            XCTAssertEqual(error as? TiebaImageDownloadError, .invalidImageData)
        }
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TiebaPure-EmoticonTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private static func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EmoticonURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static let pngData = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!

    private static func pngData(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        ).pngData { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }
}

private enum EmoticonStubError: Error, Sendable {
    case offline
}

private actor EmoticonDownloaderStub: TiebaEmoticonDownloading {
    private var result: Result<Data, EmoticonStubError>
    private let delayNanoseconds: UInt64
    private var requests = 0
    private var activeRequests = 0
    private var maximumActiveRequests = 0

    init(result: Result<Data, EmoticonStubError>, delayNanoseconds: UInt64 = 0) {
        self.result = result
        self.delayNanoseconds = delayNanoseconds
    }

    func download(from url: URL, imageName: String) async throws -> Data {
        requests += 1
        activeRequests += 1
        maximumActiveRequests = max(maximumActiveRequests, activeRequests)
        defer { activeRequests -= 1 }
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return try result.get()
    }

    func setResult(_ result: Result<Data, EmoticonStubError>) {
        self.result = result
    }

    func requestCount() -> Int { requests }
    func maximumConcurrentRequestCount() -> Int { maximumActiveRequests }
}

private actor EmoticonNotificationRecorder {
    private var value = 0
    func record() { value += 1 }
    func count() -> Int { value }
}

private final class EmoticonTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) {
        self.value = value
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }
}

private final class EmoticonURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responseData = Data()
    private static var responseMIMEType = "image/png"
    private static var responseDeclaredLength: Int?
    private static var requests = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func configure(data: Data, mimeType: String, declaredLength: Int? = nil) {
        lock.lock()
        responseData = data
        responseMIMEType = mimeType
        responseDeclaredLength = declaredLength
        requests = 0
        lock.unlock()
    }

    static func reset() {
        configure(data: Data(), mimeType: "image/png")
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let data = Self.responseData
        let mimeType = Self.responseMIMEType
        let declaredLength = Self.responseDeclaredLength
        Self.requests += 1
        Self.lock.unlock()

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        var headers = ["Content-Type": mimeType]
        if let declaredLength {
            headers["Content-Length"] = String(declaredLength)
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
