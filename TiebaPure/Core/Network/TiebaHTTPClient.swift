import Foundation
import CryptoKit
import SwiftProtobuf

struct TiebaHTTPClient {
    static let maximumAPIResponseBytes = 16 * 1_024 * 1_024
    var session: URLSession
    var maximumResponseBytes = maximumAPIResponseBytes

    func getJSON<T: Decodable>(
        _ endpoint: TiebaEndpoint,
        queryItems: [URLQueryItem],
        headers: [String: String] = [:],
        as type: T.Type
    ) async throws -> T {
        guard var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false) else {
            throw TiebaHTTPError.invalidURL
        }
        // URLComponents.queryItems leaves '+' literal, which Baidu's web
        // endpoints decode as a space; encode the query manually so '+'
        // becomes %2B.
        if queryItems.isEmpty == false {
            let appendedQuery = queryItems
                .map { item in
                    guard let value = item.value else { return item.name.urlQueryEscaped }
                    return "\(item.name.urlQueryEscaped)=\(value.urlQueryEscaped)"
                }
                .joined(separator: "&")
            if let existingQuery = components.percentEncodedQuery, existingQuery.isEmpty == false {
                components.percentEncodedQuery = existingQuery + "&" + appendedQuery
            } else {
                components.percentEncodedQuery = appendedQuery
            }
        }
        guard let url = components.url else {
            throw TiebaHTTPError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(headers["User-Agent"] ?? "tieba/12.52.1.0 skin/default", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (data, response) = try await BoundedURLSession(session: session).data(
            for: request,
            maximumBytes: maximumResponseBytes
        )
        try validate(response: response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func postForm<T: Decodable>(
        _ endpoint: TiebaEndpoint,
        fields: [String: String],
        headers: [String: String] = [:],
        signingSecret: String? = nil,
        as type: T.Type
    ) async throws -> T {
        var request = URLRequest(url: endpoint.url)
        var requestFields = fields
        let shouldSortFields = signingSecret != nil
        if let signingSecret, requestFields["sign"] == nil {
            requestFields["sign"] = TiebaFormSigner.sign(fields: requestFields, secret: signingSecret)
        }

        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(headers["User-Agent"] ?? "bdtb for iPhone 12.0.8.0", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let bodyPairs = shouldSortFields ? requestFields.sorted { $0.key < $1.key } : Array(requestFields)
        request.httpBody = bodyPairs
            .map { "\($0.key.urlFormEscaped)=\($0.value.urlFormEscaped)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await BoundedURLSession(session: session).data(
            for: request,
            maximumBytes: maximumResponseBytes
        )
        try validate(response: response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func postProtobuf<Response: SwiftProtobuf.Message>(
        _ endpoint: TiebaEndpoint,
        body: Data,
        contentType: String,
        headers: [String: String] = [:],
        as type: Response.Type
    ) async throws -> Response {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("tieba/12.52.1.0", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = body

        let (data, response) = try await BoundedURLSession(session: session).data(
            for: request,
            maximumBytes: maximumResponseBytes
        )
        try validate(response: response, data: data)
        return try Response(serializedBytes: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw TiebaHTTPError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw TiebaHTTPError.badStatus(code: http.statusCode, body: data)
        }
    }
}

enum TiebaHTTPError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case badStatus(code: Int, body: Data)
    case responseTooLarge(limit: Int)
    case invalidMIMEType(String?)
}

struct BoundedURLSessionProgress: Equatable, Sendable {
    let receivedBytes: Int
    let expectedBytes: Int?

    var fractionCompleted: Double? {
        guard let expectedBytes, expectedBytes > 0 else { return nil }
        return min(max(Double(receivedBytes) / Double(expectedBytes), 0), 1)
    }
}

struct BoundedURLSession: Sendable {
    let session: URLSession

    func data(
        for request: URLRequest,
        maximumBytes: Int,
        requiredMIMEPrefix: String? = nil,
        enforcesDeclaredContentLength: Bool = true,
        onProgress: (@Sendable (BoundedURLSessionProgress) async -> Void)? = nil
    ) async throws -> (Data, URLResponse) {
        precondition(maximumBytes > 0)
        let (bytes, response) = try await session.bytes(for: request)

        if enforcesDeclaredContentLength,
           response.expectedContentLength > Int64(maximumBytes) {
            throw TiebaHTTPError.responseTooLarge(limit: maximumBytes)
        }
        if let requiredMIMEPrefix {
            let mime = response.mimeType?.lowercased()
            guard mime?.hasPrefix(requiredMIMEPrefix.lowercased()) == true else {
                throw TiebaHTTPError.invalidMIMEType(mime)
            }
        }

        let expectedBytes = response.expectedContentLength > 0
            ? Int(response.expectedContentLength)
            : nil
        await onProgress?(BoundedURLSessionProgress(
            receivedBytes: 0,
            expectedBytes: expectedBytes
        ))
        try Task.checkCancellation()

        var data = Data()
        if let expectedBytes {
            data.reserveCapacity(min(expectedBytes, maximumBytes))
        }
        var iterator = bytes.makeAsyncIterator()
        let chunkCapacity = 64 * 1_024
        let progressIncrement = max(64 * 1_024, (expectedBytes ?? maximumBytes) / 100)
        var lastReportedBytes = 0
        var chunk = [UInt8]()
        chunk.reserveCapacity(chunkCapacity)
        while true {
            chunk.removeAll(keepingCapacity: true)
            while chunk.count < chunkCapacity, let byte = try await iterator.next() {
                chunk.append(byte)
            }
            guard chunk.isEmpty == false else { break }
            try Task.checkCancellation()
            guard data.count + chunk.count <= maximumBytes else {
                throw TiebaHTTPError.responseTooLarge(limit: maximumBytes)
            }
            data.append(contentsOf: chunk)
            if data.count - lastReportedBytes >= progressIncrement
                || expectedBytes.map({ data.count >= $0 }) == true {
                lastReportedBytes = data.count
                await onProgress?(BoundedURLSessionProgress(
                    receivedBytes: data.count,
                    expectedBytes: expectedBytes
                ))
                try Task.checkCancellation()
            }
        }
        if lastReportedBytes != data.count {
            await onProgress?(BoundedURLSessionProgress(
                receivedBytes: data.count,
                expectedBytes: expectedBytes
            ))
            try Task.checkCancellation()
        }
        return (data, response)
    }
}

enum SecureRemoteRedirectScope: Sendable {
    case publicHTTPS
    case baiduHTTPS
    case bdStaticHTTPS

    func allows(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https" else { return false }
        guard TiebaURL.webpage(url.absoluteString) != nil else { return false }
        switch self {
        case .publicHTTPS:
            return true
        case .baiduHTTPS:
            guard let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else {
                return false
            }
            return host == "baidu.com" || host.hasSuffix(".baidu.com")
        case .bdStaticHTTPS:
            guard url.host?.lowercased() == TiebaEmoticonURLPolicy.host,
                  url.user == nil,
                  url.password == nil else {
                return false
            }
            let prefix = "/tb/editor/images/client/"
            guard url.path.hasPrefix(prefix), url.path.hasSuffix(".png") else { return false }
            let imageName = String(url.path.dropFirst(prefix.count).dropLast(".png".count))
            return imageName.contains("/") == false
                && TiebaEmoticonURLPolicy.isValidImageName(imageName)
        }
    }
}

final class SecureRemoteRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let scope: SecureRemoteRedirectScope

    init(scope: SecureRemoteRedirectScope) {
        self.scope = scope
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(scope.allows(request.url) ? request : nil)
    }
}

enum SecureRemoteURLSession {
    static func make(
        configuration: URLSessionConfiguration,
        redirectScope: SecureRemoteRedirectScope
    ) -> URLSession {
        URLSession(
            configuration: configuration,
            delegate: SecureRemoteRedirectDelegate(scope: redirectScope),
            delegateQueue: nil
        )
    }
}

/// Lives here rather than in TiebaAPI.swift because importing SwiftProtobuf
/// there would make its `Decoder` protocol shadow `Swift.Decoder` for every
/// hand-written `init(from:)` in that file.
enum TiebaProtobufErrorClassifier {
    static func isDecodeFailure(_ error: Error) -> Bool {
        error is BinaryDecodingError || error is SwiftProtobufError
    }
}

enum TiebaFormSigner {
    static func sign(fields: [String: String], secret: String) -> String {
        let raw = fields
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined()
        let digest = Insecure.MD5.hash(data: Data((raw + secret).utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }
}

private extension String {
    var urlFormEscaped: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? self
    }

    var urlQueryEscaped: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+#")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
