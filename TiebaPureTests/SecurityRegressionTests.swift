import XCTest
@testable import TiebaPure

final class SecurityRegressionTests: XCTestCase {
    override func tearDown() {
        SecurityURLProtocol.payload = Data()
        SecurityURLProtocol.mimeType = "application/octet-stream"
        SecurityURLProtocol.delay = 0
        SecurityURLProtocol.declaredContentLength = nil
        super.tearDown()
    }

    func testKeychainUpdatesExistingItemWithoutDeleteFirst() async throws {
        let service = KeychainAccountStoreService(
            service: "dev.kevinchen.tiebapure.tests.\(UUID().uuidString)",
            account: "update"
        )
        try? await service.clearData()
        try await service.saveData(Data("first".utf8))
        try await service.saveData(Data("second".utf8))
        let loaded = try await service.loadData()
        XCTAssertEqual(loaded, Data("second".utf8))
        try await service.clearData()
    }

    func testAccountEncodingDoesNotPersistCompleteCookieField() throws {
        let account = FixtureTiebaAPI.account
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(account), encoding: .utf8))
        XCTAssertFalse(json.contains("\"cookie\""))
        XCTAssertFalse(json.contains("Cookie:"))
    }

    @MainActor
    func testCancellationDuringAccountSaveRollsBackWithoutPublishingLogin() async throws {
        let service = ControlledSaveAccountStoreService()
        let store = AccountStore(service: service)
        var publishedAccounts: [Account] = []
        let observation = store.accountDidChange.compactMap { $0 }.sink {
            publishedAccounts.append($0)
        }

        let saveTask = Task {
            try await store.save(FixtureTiebaAPI.account)
        }
        for _ in 0..<200 {
            if await service.hasPendingSave() { break }
            await Task.yield()
        }
        let didStartSaving = await service.hasPendingSave()
        XCTAssertTrue(didStartSaving)

        saveTask.cancel()
        await service.finishPendingSave()
        do {
            try await saveTask.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }

        let persisted = try await store.load()
        XCTAssertNil(persisted)
        XCTAssertTrue(publishedAccounts.isEmpty)
        withExtendedLifetime(observation) {}
    }

    func testBoundedResponseRejectsDeclaredOverflow() async throws {
        SecurityURLProtocol.payload = Data(repeating: 0x41, count: 9)
        SecurityURLProtocol.declaredContentLength = 9
        let loader = BoundedURLSession(session: Self.session())
        do {
            _ = try await loader.data(for: URLRequest(url: URL(string: "https://example.com/large")!), maximumBytes: 8)
            XCTFail("Expected response cap")
        } catch {
            XCTAssertEqual(error as? TiebaHTTPError, .responseTooLarge(limit: 8))
        }
    }

    func testBoundedResponseRejectsAccumulatedOverflowWithoutDeclaredLength() async throws {
        SecurityURLProtocol.payload = Data(repeating: 0x41, count: 9)
        SecurityURLProtocol.declaredContentLength = nil
        let loader = BoundedURLSession(session: Self.session())
        do {
            _ = try await loader.data(
                for: URLRequest(url: URL(string: "https://example.com/chunked")!),
                maximumBytes: 8
            )
            XCTFail("Expected streamed response cap")
        } catch {
            XCTAssertEqual(error as? TiebaHTTPError, .responseTooLarge(limit: 8))
        }
    }

    func testImageMIMEValidationRejectsNonImageResponse() async throws {
        SecurityURLProtocol.payload = Data("not an image".utf8)
        SecurityURLProtocol.mimeType = "text/html"
        let loader = BoundedURLSession(session: Self.session())
        do {
            _ = try await loader.data(
                for: URLRequest(url: URL(string: "https://example.com/image")!),
                maximumBytes: 100,
                requiredMIMEPrefix: "image/"
            )
            XCTFail("Expected MIME rejection")
        } catch {
            XCTAssertEqual(error as? TiebaHTTPError, .invalidMIMEType("text/html"))
        }
    }

    func testImageDecodePolicyRejectsPixelBombDimensions() {
        XCTAssertTrue(TiebaImageDecodePolicy.allows(width: 4_096, height: 4_096))
        XCTAssertFalse(TiebaImageDecodePolicy.allows(width: 100_000, height: 1))
        XCTAssertFalse(TiebaImageDecodePolicy.allows(width: 20_000, height: 20_000))
        XCTAssertFalse(TiebaImageDecodePolicy.allows(width: Int.max, height: 2))
    }

    func testBoundedResponsePropagatesCancellation() async throws {
        SecurityURLProtocol.payload = Data("late".utf8)
        SecurityURLProtocol.delay = 2
        let loader = BoundedURLSession(session: Self.session())
        let task = Task {
            try await loader.data(
                for: URLRequest(url: URL(string: "https://example.com/slow")!),
                maximumBytes: 100
            )
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            return
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        }
    }

    func testBusinessErrorsAndExpiredSessionAreDistinct() throws {
        XCTAssertNoThrow(try TiebaResponseValidator.validate(code: 0, message: ""))
        XCTAssertThrowsError(try TiebaResponseValidator.validate(code: 12, message: "业务错误")) {
            XCTAssertEqual($0 as? TiebaAPIError, .response(code: 12, message: "业务错误"))
        }
        XCTAssertThrowsError(try TiebaResponseValidator.validate(code: 110001, message: "登录失效")) {
            XCTAssertEqual($0 as? TiebaAPIError, .sessionExpired(code: 110001, message: "登录失效"))
        }
    }

    func testForumFallbackOnlyAcceptsDecodeIncompatibility() {
        let decodingError = DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "fixture"))
        XCTAssertTrue(TiebaAPI.shouldFallbackFromForumProtobuf(decodingError))
        XCTAssertFalse(TiebaAPI.shouldFallbackFromForumProtobuf(URLError(.notConnectedToInternet)))
        XCTAssertFalse(TiebaAPI.shouldFallbackFromForumProtobuf(CancellationError()))
        XCTAssertFalse(TiebaAPI.shouldFallbackFromForumProtobuf(TiebaAPIError.response(code: 1, message: "业务错误")))
    }

    @MainActor
    func testLogoutFailureKeepsStoredAccount() async throws {
        let store = AccountStore(service: MemoryAccountStoreService())
        try await store.save(FixtureTiebaAPI.account)
        let coordinator = LogoutCoordinator(accountStore: store, artifactCleaner: FailingArtifactCleaner())

        do {
            try await coordinator.logOut()
            XCTFail("Expected logout failure")
        } catch {
            let persisted = try await store.load()
            XCTAssertEqual(persisted, FixtureTiebaAPI.account)
        }
    }

    @MainActor
    func testCompleteLogoutClearsAccountAfterArtifacts() async throws {
        let store = AccountStore(service: MemoryAccountStoreService())
        try await store.save(FixtureTiebaAPI.account)
        let cleaner = RecordingArtifactCleaner()
        let coordinator = LogoutCoordinator(accountStore: store, artifactCleaner: cleaner)

        try await coordinator.logOut()
        let persisted = try await store.load()
        XCTAssertNil(persisted)
        XCTAssertTrue(cleaner.didClear)
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SecurityURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

@MainActor
private struct FailingArtifactCleaner: SessionArtifactCleaning {
    func clear() async throws { throw URLError(.cannotRemoveFile) }
}

@MainActor
private final class RecordingArtifactCleaner: SessionArtifactCleaning {
    private(set) var didClear = false
    func clear() async throws { didClear = true }
}

private final class SecurityURLProtocol: URLProtocol {
    static var payload = Data()
    static var mimeType = "application/octet-stream"
    static var delay: TimeInterval = 0
    static var declaredContentLength: Int?
    private var workItem: DispatchWorkItem?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let item = DispatchWorkItem { [weak self] in
            guard let self, let url = request.url else { return }
            var headers = ["Content-Type": Self.mimeType]
            if let declaredContentLength = Self.declaredContentLength {
                headers["Content-Length"] = "\(declaredContentLength)"
            }
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Self.payload)
            client?.urlProtocolDidFinishLoading(self)
        }
        workItem = item
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.delay, execute: item)
    }

    override func stopLoading() {
        workItem?.cancel()
        workItem = nil
    }
}

private actor ControlledSaveAccountStoreService: AccountStoreService {
    private var data: Data?
    private var pendingSave: (data: Data, continuation: CheckedContinuation<Void, Never>)?

    func loadData() async throws -> Data? { data }

    func saveData(_ data: Data) async throws {
        await withCheckedContinuation { continuation in
            pendingSave = (data, continuation)
        }
        self.data = data
    }

    func clearData() async throws {
        data = nil
    }

    func hasPendingSave() -> Bool {
        pendingSave != nil
    }

    func finishPendingSave() {
        guard let pendingSave else { return }
        self.pendingSave = nil
        pendingSave.continuation.resume()
    }
}
