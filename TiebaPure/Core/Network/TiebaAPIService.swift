import Foundation

protocol TiebaAPIService {
    func validateLogin(cookies: BaiduCookies) async throws -> Account
    func personalizedThreads(account: Account?, page: Int, loadType: Int) async throws -> [ThreadSummary]
    func followedForums(account: Account) async throws -> [Forum]
    func forumThreads(account: Account?, forumName: String, page: Int, sortType: Int) async throws -> [ThreadSummary]
    func searchThreads(
        keyword: String,
        page: Int,
        sortType: Int,
        filterType: Int,
        forumName: String?,
        pageSize: Int
    ) async throws -> SearchResultsPage
    func threadPage(
        account: Account?,
        threadID: Int64,
        page: Int,
        forumID: Int64?,
        postID: UInt64?,
        seeLz: Bool,
        sortType: ThreadReplySort
    ) async throws -> ThreadPage
    func subposts(
        account: Account?,
        threadID: Int64,
        postID: UInt64,
        forumID: Int64,
        page: Int,
        subpostID: UInt64
    ) async throws -> [Subpost]
    func userProfile(account: Account?, user: UserSummary) async throws -> UserProfile
    func userThreads(account: Account?, userID: Int64, page: Int) async throws -> UserThreadsPage
    func setUserFollowed(account: Account, user: UserSummary, followed: Bool) async throws
    func followedUsers(account: Account, page: Int) async throws -> FollowedUsersPage
    func setPostLiked(
        account: Account,
        threadID: Int64,
        postID: UInt64,
        objectType: TiebaLikeObjectType,
        liked: Bool
    ) async throws
}

extension TiebaAPIService {
    func forumThreads(account: Account?, forumName: String, page: Int) async throws -> [ThreadSummary] {
        try await forumThreads(account: account, forumName: forumName, page: page, sortType: 0)
    }

    func searchThreads(
        keyword: String,
        page: Int,
        sortType: Int = 5,
        filterType: Int = 2,
        forumName: String? = nil,
        pageSize: Int = 30
    ) async throws -> SearchResultsPage {
        try await searchThreads(
            keyword: keyword,
            page: page,
            sortType: sortType,
            filterType: filterType,
            forumName: forumName,
            pageSize: pageSize
        )
    }

    func threadPage(
        account: Account?,
        threadID: Int64,
        page: Int,
        forumID: Int64? = nil,
        postID: UInt64? = nil,
        seeLz: Bool = false,
        sortType: ThreadReplySort = .ascending
    ) async throws -> ThreadPage {
        try await threadPage(
            account: account,
            threadID: threadID,
            page: page,
            forumID: forumID,
            postID: postID,
            seeLz: seeLz,
            sortType: sortType
        )
    }

    func subposts(
        account: Account?,
        threadID: Int64,
        postID: UInt64,
        forumID: Int64,
        page: Int,
        subpostID: UInt64 = 0
    ) async throws -> [Subpost] {
        try await subposts(
            account: account,
            threadID: threadID,
            postID: postID,
            forumID: forumID,
            page: page,
            subpostID: subpostID
        )
    }
}

extension TiebaAPI: TiebaAPIService {}
