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
        components.queryItems = (components.queryItems ?? []) + queryItems
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

struct BoundedURLSession: Sendable {
    let session: URLSession

    func data(
        for request: URLRequest,
        maximumBytes: Int,
        requiredMIMEPrefix: String? = nil
    ) async throws -> (Data, URLResponse) {
        precondition(maximumBytes > 0)
        let (bytes, response) = try await session.bytes(for: request)

        if response.expectedContentLength > Int64(maximumBytes) {
            throw TiebaHTTPError.responseTooLarge(limit: maximumBytes)
        }
        if let requiredMIMEPrefix {
            let mime = response.mimeType?.lowercased()
            guard mime?.hasPrefix(requiredMIMEPrefix.lowercased()) == true else {
                throw TiebaHTTPError.invalidMIMEType(mime)
            }
        }

        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(min(Int(response.expectedContentLength), maximumBytes))
        }
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else {
                throw TiebaHTTPError.responseTooLarge(limit: maximumBytes)
            }
            data.append(byte)
        }
        return (data, response)
    }
}

enum SecureRemoteRedirectScope: Sendable {
    case publicHTTPS
    case baiduHTTPS

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
}
