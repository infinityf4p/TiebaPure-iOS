import Foundation

enum MessageKind: String, CaseIterable, Sendable {
    case reply
    case at
}

struct MessageItem: Identifiable, Equatable, Sendable {
    var id: String
    var kind: MessageKind
    var author: UserSummary
    var content: String
    var threadID: Int64
    var postID: UInt64?
    var threadTitle: String
    var forumName: String?
    var isFloorReply: Bool
    var createdAt: Date?
}

struct MessagesPage: Equatable, Sendable {
    var items: [MessageItem]
    var currentPage: Int
    var hasMore: Bool
}

struct MessagePaginationState: Equatable, Sendable {
    var nextPage: Int
    var hasMore: Bool
}

enum MessagePaginationPolicy {
    static func state(
        after page: MessagesPage,
        requestedPage: Int
    ) -> MessagePaginationState {
        MessagePaginationState(
            nextPage: max(page.currentPage, requestedPage) + 1,
            hasMore: page.hasMore
        )
    }
}

/// Lives outside TiebaEndpoint because enum cases cannot be added from an
/// extension; the URLs still derive from the shared API hosts.
enum TiebaMessageEndpoint {
    case replyMe
    case atMe

    var url: URL {
        switch self {
        case .replyMe:
            return TiebaEndpoint.appBase.appending(path: "/c/u/feed/replyme")
        case .atMe:
            return TiebaEndpoint.appBase.appending(path: "/c/u/feed/atme")
        }
    }
}

enum TiebaMessageRequestFactory {
    /// The legacy message feed requires the 8.2.2 client profile.
    static let clientVersion = "8.2.2"

    static func feedFields(
        account: Account,
        page: Int,
        requestBuilder: TiebaRequestBuilder,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1_000)
    ) throws -> [String: String] {
        let requestedPage = try TiebaRequestValuePolicy.signedPage(page)
        // The legacy feed starts from the mini common fields but does not
        // accept the two keys below for this client version.
        var fields = requestBuilder.miniCommonFields(timestamp: timestamp)
        fields.removeValue(forKey: "subapp_type")
        fields.removeValue(forKey: "cuid_galaxy2")
        fields["_client_version"] = clientVersion
        fields["from"] = "baidu_appstore"
        fields["BDUSS"] = account.bduss
        fields["pn"] = "\(requestedPage)"
        fields["stErrorNums"] = "0"
        return fields
    }
}

struct MessageListResponseDTO: Decodable {
    struct UserDTO: Decodable {
        var id: Int64
        var name: String
        var displayName: String
        var portrait: String

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case displayName = "name_show"
            case portrait
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.flexibleInt64(forKey: .id)
            name = container.flexibleString(forKey: .name) ?? ""
            displayName = container.flexibleString(forKey: .displayName) ?? ""
            portrait = container.flexibleString(forKey: .portrait) ?? ""
        }

        var userSummary: UserSummary {
            let portraitToken = portrait.split(separator: "?", maxSplits: 1).first.map(String.init) ?? portrait
            return UserSummary(
                id: id,
                name: name,
                displayName: displayName,
                portrait: portraitToken
            )
        }
    }

    struct MessageDTO: Decodable {
        var isFloor: Bool
        var title: String
        var content: String
        var quoteContent: String
        var replyer: UserDTO?
        var threadID: Int64
        var postID: UInt64
        var quotePostID: UInt64
        var forumName: String
        var createdAt: Date?
        var timeIdentity: String

        enum CodingKeys: String, CodingKey {
            case isFloor = "is_floor"
            case title
            case content
            case quoteContent = "quote_content"
            case replyer
            case threadID = "thread_id"
            case postID = "post_id"
            case quotePostID = "quote_pid"
            case forumName = "fname"
            case time
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            isFloor = container.flexibleInt(forKey: .isFloor) == 1
            title = container.flexibleString(forKey: .title) ?? ""
            content = container.flexibleString(forKey: .content) ?? ""
            quoteContent = container.flexibleString(forKey: .quoteContent) ?? ""
            replyer = try? container.decodeIfPresent(UserDTO.self, forKey: .replyer)
            threadID = container.flexibleInt64(forKey: .threadID)
            postID = container.flexibleUInt64(forKey: .postID)
            quotePostID = container.flexibleUInt64(forKey: .quotePostID)
            forumName = container.flexibleString(forKey: .forumName) ?? ""
            timeIdentity = container.flexibleString(forKey: .time)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let seconds = TimeInterval(timeIdentity),
               seconds > 0 {
                createdAt = Date(timeIntervalSince1970: seconds)
            } else {
                createdAt = nil
            }
        }

        func messageItem(kind: MessageKind) -> MessageItem? {
            guard threadID > 0 else { return nil }
            // A floor reply's post_id addresses the subpost; the reader can
            // only land on whole posts, so jump to its parent via quote_pid.
            let jumpPostID = isFloor ? quotePostID : postID
            let author = replyer?.userSummary
                ?? UserSummary(id: 0, name: "", displayName: "", portrait: "")
            return MessageItem(
                // Match the upstream notification identity: post, sender and
                // server time distinguish separate events that target the same
                // thread while remaining stable across pagination reloads.
                id: "\(kind.rawValue)-\(threadID)-\(postID)-\(author.id)-\(timeIdentity)",
                kind: kind,
                author: author,
                content: content,
                threadID: threadID,
                postID: jumpPostID == 0 ? nil : jumpPostID,
                threadTitle: title,
                forumName: forumName.isEmpty ? nil : forumName,
                isFloorReply: isFloor,
                createdAt: createdAt
            )
        }
    }

    /// Tieba's legacy message adapter treats JSON primitives in `reply_list`
    /// and `at_list` as an empty feed. Keep that wire compatibility without
    /// accepting objects or malformed array elements as valid messages.
    private struct CompatibleMessageList: Decodable {
        let items: [MessageDTO]

        init(from decoder: Decoder) throws {
            let singleValue = try decoder.singleValueContainer()
            if singleValue.decodeNil() {
                items = []
                return
            }
            if (try? singleValue.decode(Bool.self)) != nil
                || (try? singleValue.decode(Int64.self)) != nil
                || (try? singleValue.decode(Double.self)) != nil
                || (try? singleValue.decode(String.self)) != nil {
                items = []
                return
            }

            var array = try decoder.unkeyedContainer()
            var decoded: [MessageDTO] = []
            decoded.reserveCapacity(array.count ?? 0)
            while array.isAtEnd == false {
                // Do not use a lossy element decoder here: a genuine schema
                // error inside an array must remain visible to callers.
                decoded.append(try array.decode(MessageDTO.self))
            }
            items = decoded
        }
    }

    var errorCode: Int
    var errorMessage: String
    var replyList: [MessageDTO]?
    var atList: [MessageDTO]?
    var currentPage: Int
    var hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case errorMessage = "error_msg"
        case replyList = "reply_list"
        case atList = "at_list"
        case page
    }

    enum PageCodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case hasMore = "has_more"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errorCode = container.flexibleInt(forKey: .errorCode)
        errorMessage = container.flexibleString(forKey: .errorMessage) ?? ""
        if errorCode == 0 {
            // A missing, null, or primitive list maps to an empty list.
            // Objects and malformed array elements still throw.
            replyList = try container.decodeIfPresent(
                CompatibleMessageList.self,
                forKey: .replyList
            )?.items
            atList = try container.decodeIfPresent(
                CompatibleMessageList.self,
                forKey: .atList
            )?.items
        } else {
            // Business failures must reach TiebaResponseValidator even when
            // the server includes a malformed payload alongside the code.
            replyList = nil
            atList = nil
        }
        if let page = try? container.nestedContainer(keyedBy: PageCodingKeys.self, forKey: .page) {
            currentPage = page.flexibleInt(forKey: .currentPage)
            hasMore = page.flexibleInt(forKey: .hasMore) != 0
        } else {
            currentPage = 0
            hasMore = false
        }
    }

    func list(for kind: MessageKind) -> [MessageDTO] {
        switch kind {
        case .reply:
            return replyList ?? []
        case .at:
            return atList ?? []
        }
    }
}

extension TiebaAPI {
    func messages(account: Account, kind: MessageKind, page: Int) async throws -> MessagesPage {
        let fields = try TiebaMessageRequestFactory.feedFields(
            account: account,
            page: page,
            requestBuilder: requestBuilder
        )
        let endpoint: TiebaMessageEndpoint = kind == .reply ? .replyMe : .atMe
        let response = try await client.postForm(
            endpoint,
            fields: fields,
            headers: [
                "Cookie": "ka=open",
                "Pragma": "no-cache",
                "User-Agent": "bdtb for Android \(TiebaMessageRequestFactory.clientVersion)",
                "cuid": requestBuilder.miniCUID
            ],
            signingSecret: "tiebaclient!!!",
            as: MessageListResponseDTO.self
        )
        try TiebaResponseValidator.validate(code: response.errorCode, message: response.errorMessage)
        let list = response.list(for: kind)
        return MessagesPage(
            items: list.compactMap { $0.messageItem(kind: kind) },
            currentPage: max(response.currentPage, page),
            hasMore: response.hasMore
        )
    }
}

extension TiebaHTTPClient {
    /// Mirrors postForm(_:fields:headers:signingSecret:as:) for message
    /// endpoints, which live outside the TiebaEndpoint enum.
    func postForm<T: Decodable>(
        _ endpoint: TiebaMessageEndpoint,
        fields: [String: String],
        headers: [String: String] = [:],
        signingSecret: String,
        as type: T.Type
    ) async throws -> T {
        var request = URLRequest(url: endpoint.url)
        var requestFields = fields
        if requestFields["sign"] == nil {
            requestFields["sign"] = TiebaFormSigner.sign(fields: requestFields, secret: signingSecret)
        }

        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = requestFields
            .sorted { $0.key < $1.key }
            .map { "\($0.key.messageFormEscaped)=\($0.value.messageFormEscaped)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await BoundedURLSession(session: session).data(
            for: request,
            maximumBytes: maximumResponseBytes
        )
        guard let http = response as? HTTPURLResponse else { throw TiebaHTTPError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw TiebaHTTPError.badStatus(code: http.statusCode, body: data)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private extension String {
    // Same escaping rules as the form encoder in TiebaHTTPClient.swift,
    // whose helper is file-private there.
    var messageFormEscaped: String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        return addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? self
    }
}

private extension KeyedDecodingContainer {
    func flexibleString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func flexibleInt(forKey key: Key) -> Int {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Int64.self, forKey: key) { return Int(clamping: value) }
        if let value = try? decode(String.self, forKey: key) { return Int(value) ?? 0 }
        return 0
    }

    func flexibleInt64(forKey key: Key) -> Int64 {
        if let value = try? decode(Int64.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Int64(value) }
        if let value = try? decode(String.self, forKey: key) { return Int64(value) ?? 0 }
        return 0
    }

    func flexibleUInt64(forKey key: Key) -> UInt64 {
        if let value = try? decode(UInt64.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) { return UInt64(value) ?? 0 }
        return 0
    }
}
