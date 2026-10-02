import Combine
import Foundation

enum SessionExpirationErrorClassifier {
    static func isSessionExpired(_ error: Error) -> Bool {
        if let apiError = error as? TiebaAPIError,
           case .sessionExpired = apiError {
            return true
        }
        return (error as? ContentSubmissionError) == .sessionExpired
    }
}

enum SessionExpirationHandlingPolicy {
    static func shouldHandle(
        reportedSession: AccountSessionIdentity,
        currentAccount: Account?,
        expiringSession: AccountSessionIdentity?
    ) -> Bool {
        guard expiringSession == nil else { return false }
        return currentAccount?.sessionIdentity == reportedSession
    }
}

@MainActor
final class SessionExpirationMonitor {
    private let subject = PassthroughSubject<AccountSessionIdentity, Never>()

    var expiredSessions: AnyPublisher<AccountSessionIdentity, Never> {
        subject.eraseToAnyPublisher()
    }

    func report(_ session: AccountSessionIdentity) {
        subject.send(session)
    }
}

struct SessionMonitoringTiebaAPI: TiebaAPIService {
    let base: any TiebaAPIService
    let monitor: SessionExpirationMonitor

    func validateLogin(cookies: BaiduCookies) async throws -> Account {
        try await base.validateLogin(cookies: cookies)
    }

    func personalizedThreads(
        account: Account?,
        page: Int,
        loadType: Int
    ) async throws -> [ThreadSummary] {
        try await monitored(account: account) {
            try await base.personalizedThreads(account: account, page: page, loadType: loadType)
        }
    }

    func followedForums(account: Account) async throws -> [Forum] {
        try await monitored(account: account) {
            try await base.followedForums(account: account)
        }
    }

    func forumThreads(
        account: Account?,
        forumName: String,
        page: Int,
        category: ForumThreadCategory
    ) async throws -> [ThreadSummary] {
        try await monitored(account: account) {
            try await base.forumThreads(
                account: account,
                forumName: forumName,
                page: page,
                category: category
            )
        }
    }

    func searchThreads(
        keyword: String,
        page: Int,
        sortType: Int,
        filterType: Int,
        forumName: String?,
        pageSize: Int
    ) async throws -> SearchResultsPage {
        try await base.searchThreads(
            keyword: keyword,
            page: page,
            sortType: sortType,
            filterType: filterType,
            forumName: forumName,
            pageSize: pageSize
        )
    }

    func resolveUser(named name: String) async throws -> UserSummary {
        try await base.resolveUser(named: name)
    }

    func threadPage(
        account: Account?,
        threadID: Int64,
        page: Int,
        forumID: Int64?,
        postID: UInt64?,
        seeLz: Bool,
        sortType: ThreadReplySort
    ) async throws -> ThreadPage {
        try await monitored(account: account) {
            try await base.threadPage(
                account: account,
                threadID: threadID,
                page: page,
                forumID: forumID,
                postID: postID,
                seeLz: seeLz,
                sortType: sortType
            )
        }
    }

    func subposts(
        account: Account?,
        threadID: Int64,
        postID: UInt64,
        forumID: Int64,
        page: Int,
        subpostID: UInt64
    ) async throws -> [Subpost] {
        try await monitored(account: account) {
            try await base.subposts(
                account: account,
                threadID: threadID,
                postID: postID,
                forumID: forumID,
                page: page,
                subpostID: subpostID
            )
        }
    }

    func userProfile(account: Account?, user: UserSummary) async throws -> UserProfile {
        try await monitored(account: account) {
            try await base.userProfile(account: account, user: user)
        }
    }

    func userThreads(
        account: Account?,
        userID: Int64,
        page: Int
    ) async throws -> UserThreadsPage {
        try await monitored(account: account) {
            try await base.userThreads(account: account, userID: userID, page: page)
        }
    }

    func updateOwnProfile(account: Account, request: UserProfileEditRequest) async throws {
        try await monitored(account: account) {
            try await base.updateOwnProfile(account: account, request: request)
        }
    }

    func deleteOwnThread(account: Account, target: OwnThreadDeletionTarget) async throws {
        try await monitored(account: account) {
            try await base.deleteOwnThread(account: account, target: target)
        }
    }

    func setUserFollowed(
        account: Account,
        user: UserSummary,
        followed: Bool
    ) async throws {
        try await monitored(account: account) {
            try await base.setUserFollowed(account: account, user: user, followed: followed)
        }
    }

    func userRelationships(
        account: Account?,
        userID: Int64,
        kind: UserRelationshipKind,
        page: Int
    ) async throws -> UserRelationshipPage {
        try await monitored(account: account) {
            try await base.userRelationships(
                account: account,
                userID: userID,
                kind: kind,
                page: page
            )
        }
    }

    func forumMembership(account: Account, forum: Forum) async throws -> ForumMembership {
        try await monitored(account: account) {
            try await base.forumMembership(account: account, forum: forum)
        }
    }

    func setForumFollowed(
        account: Account,
        forum: Forum,
        followed: Bool
    ) async throws -> ForumMembership {
        try await monitored(account: account) {
            try await base.setForumFollowed(account: account, forum: forum, followed: followed)
        }
    }

    func signForum(account: Account, forum: Forum) async throws -> ForumSignResult {
        try await monitored(account: account) {
            try await base.signForum(account: account, forum: forum)
        }
    }

    /// Forwarded on purpose: the protocol default would reject the call, and a
    /// check-in run would silently fall back to resolving a token per forum —
    /// the very cost this token reuse exists to remove.
    func signingTBS(account: Account) async throws -> String {
        try await monitored(account: account) {
            try await base.signingTBS(account: account)
        }
    }

    func signForum(account: Account, forum: Forum, tbs: String) async throws -> ForumSignResult {
        try await monitored(account: account) {
            try await base.signForum(account: account, forum: forum, tbs: tbs)
        }
    }

    func followedForumStatuses(account: Account) async throws -> [FollowedForumStatus] {
        try await monitored(account: account) {
            try await base.followedForumStatuses(account: account)
        }
    }

    func hotThreads(account: Account?, tabCode: String) async throws -> HotFeed {
        try await monitored(account: account) {
            try await base.hotThreads(account: account, tabCode: tabCode)
        }
    }

    /// Forwarded on purpose: without it the topic page would only ever see the
    /// protocol's "unsupported" default.
    func topicThreads(
        account: Account?,
        topicID: Int64,
        topicName: String,
        cursor: String,
        page: Int,
        pageSize: Int
    ) async throws -> TopicThreadPage {
        try await monitored(account: account) {
            try await base.topicThreads(
                account: account,
                topicID: topicID,
                topicName: topicName,
                cursor: cursor,
                page: page,
                pageSize: pageSize
            )
        }
    }

    func accountThreadFavorites(
        account: Account,
        page: Int
    ) async throws -> AccountThreadFavoritesPage {
        try await monitored(account: account) {
            try await base.accountThreadFavorites(account: account, page: page)
        }
    }

    func setAccountThreadFavorite(
        account: Account,
        threadID: Int64,
        postID: UInt64,
        favorited: Bool
    ) async throws {
        try await monitored(account: account) {
            try await base.setAccountThreadFavorite(
                account: account,
                threadID: threadID,
                postID: postID,
                favorited: favorited
            )
        }
    }

    func messages(
        account: Account,
        kind: MessageKind,
        page: Int
    ) async throws -> MessagesPage {
        try await monitored(account: account) {
            try await base.messages(account: account, kind: kind, page: page)
        }
    }

    func setPostLiked(
        account: Account,
        threadID: Int64,
        postID: UInt64,
        objectType: TiebaLikeObjectType,
        liked: Bool
    ) async throws {
        try await monitored(account: account) {
            try await base.setPostLiked(
                account: account,
                threadID: threadID,
                postID: postID,
                objectType: objectType,
                liked: liked
            )
        }
    }

    func submitContent(
        account: Account,
        request: ContentSubmissionRequest
    ) async throws -> ContentSubmissionReceipt {
        try await monitored(account: account) {
            try await base.submitContent(account: account, request: request)
        }
    }

    private func monitored<T>(
        account: Account?,
        operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch {
            if let account,
               SessionExpirationErrorClassifier.isSessionExpired(error) {
                await monitor.report(account.sessionIdentity)
            }
            throw error
        }
    }
}
