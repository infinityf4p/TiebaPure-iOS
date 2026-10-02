import Foundation

struct Forum: Identifiable, Equatable, Codable, Sendable {
    var id: Int64
    var name: String
    var displayName: String
    var avatarURL: URL?
    var memberCount: Int
    var threadCount: Int
}

/// The signed-in account's standing inside one followed forum.
///
/// The followed-forum guide endpoint reports both values per forum, so the
/// hub can show them without one level request per forum. Kept out of `Forum`
/// itself: the forum list itself still comes from the avatar-carrying endpoint,
/// and a status that failed to load must not invent a forum.
struct FollowedForumStatus: Equatable, Sendable, Identifiable {
    var forumID: Int64
    /// The account's membership level in this forum (0 when unreported).
    var level: Int
    /// Whether the account has already checked in today.
    var isSignedToday: Bool

    var id: Int64 { forumID }
}
