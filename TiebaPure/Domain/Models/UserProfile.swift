import Foundation

enum UserContentVisibility: Equatable, Sendable {
    case visible
    case privateContent
}

enum UserProfileSex: Equatable, Sendable {
    case male
    case female
    case unspecified

    var symbolName: String {
        switch self {
        case .male:
            return "person.fill"
        case .female:
            return "person.fill"
        case .unspecified:
            return "person"
        }
    }

    var accessibilityText: String {
        switch self {
        case .male:
            return "男"
        case .female:
            return "女"
        case .unspecified:
            return "性别未公开"
        }
    }
}

struct UserProfile: Equatable, Sendable {
    var user: UserSummary
    var isCurrentUser: Bool
    var isFollowed: Bool
    var tiebaID: String
    var tiebaAge: String
    var sex: UserProfileSex
    var location: String?
    var intro: String
    var backgroundURL: URL?
    var agreeCount: Int
    var followingCount: Int
    var followerCount: Int
    var threadCount: Int
    var followedForumCount: Int
    var followedForums: [Forum]
    var followedForumsVisibility: UserContentVisibility
}

struct UserThreadsPage: Equatable, Sendable {
    var threads: [ThreadSummary]
    var currentPage: Int
    var hasMore: Bool
    var visibility: UserContentVisibility
}

struct FollowedUsersPage: Equatable, Sendable {
    var users: [UserSummary]
    var currentPage: Int
    var totalCount: Int
    var hasMore: Bool
}

enum UserProfilePrivacyPolicy {
    static func followedForumsVisibility(
        isCurrentUser: Bool,
        privacyValue: Int,
        declaredCount: Int,
        returnedCount: Int
    ) -> UserContentVisibility {
        if isCurrentUser || privacyValue == 1 || declaredCount == 0 || returnedCount > 0 {
            return .visible
        }
        return .privateContent
    }
}
