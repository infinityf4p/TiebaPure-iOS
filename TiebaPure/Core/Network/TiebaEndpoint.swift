import Foundation

enum TiebaEndpoint {
    static let base = URL(string: "https://tieba.baidu.com")!
    static let appBase = URL(string: "https://c.tieba.baidu.com")!
    static let protobufBase = URL(string: "https://tiebac.baidu.com")!
    static let socialBase = URL(string: "https://tiebac.baidu.com")!

    case login
    case postingLogin
    case initNickname
    case webMyInfo
    case followedForums
    case followedForumGuide
    case forumPageForm
    case personalized
    case hotThreadList
    case topicDetail
    case frsPage
    case pbPage
    case pbFloor
    case searchThread
    case searchUser
    case userProfile
    case userThreads
    case modifyProfile
    case deleteOwnThread
    case followUser
    case unfollowUser
    case followedUsers
    case followers
    case resolveForumID
    case forumMembership
    case followForum
    case unfollowForum
    case signForum
    case threadStoreList
    case addThreadStore
    case removeThreadStore
    case agreePost
    case webAddThread
    case webAddPost(timestamp: Int64)
    case webUploadPicture(nonce: String)
    case addPost
    case uploadPicture

    var url: URL {
        switch self {
        case .login:
            return Self.appBase.appending(path: "/c/s/login")
        case .postingLogin:
            return Self.protobufBase.appending(path: "/c/s/login")
        case .initNickname:
            return Self.appBase.appending(path: "/c/s/initNickname")
        case .webMyInfo:
            return Self.base.appending(path: "/mo/q/newmoindex")
        case .followedForums:
            return Self.appBase.appending(path: "/c/f/forum/getforumlist")
        case .followedForumGuide:
            // The web "hybrid" guide endpoint: the only followed-forum call
            // that also reports the account's per-forum level and check-in.
            return Self.base.appending(path: "/c/f/forum/forumGuide")
        case .forumPageForm:
            return Self.appBase.appending(path: "/c/f/frs/page")
        case .personalized:
            return Self.base
                .appending(path: "/c/f/excellent/personalized")
                .appending(queryItems: [.init(name: "cmd", value: "309264")])
        case .hotThreadList:
            // The hot-thread (热榜) listing behind the app's 热点 tab. An empty
            // tab code asks for the default tab plus the tab list itself.
            return Self.base
                .appending(path: "/c/f/forum/hotThreadList")
                .appending(queryItems: [.init(name: "cmd", value: "309661")])
        case .topicDetail:
            // 话题详情: the web JSON endpoint behind one 话题榜 row. It pages by
            // cursor (`last_id`), which is why the API layer carries one.
            return Self.base.appending(path: "/mo/q/newtopic/topicDetail")
        case .frsPage:
            return Self.base
                .appending(path: "/c/f/frs/page")
                .appending(queryItems: [.init(name: "cmd", value: "301001")])
        case .pbPage:
            return Self.base
                .appending(path: "/c/f/pb/page")
                .appending(queryItems: [
                    .init(name: "cmd", value: "302001"),
                    .init(name: "format", value: "protobuf")
                ])
        case .pbFloor:
            return Self.base
                .appending(path: "/c/f/pb/floor")
                .appending(queryItems: [
                    .init(name: "cmd", value: "302002"),
                    .init(name: "format", value: "protobuf")
                ])
        case .searchThread:
            return Self.base.appending(path: "/mo/q/search/thread")
        case .searchUser:
            return Self.base.appending(path: "/mo/q/search/user")
        case .userProfile:
            return Self.protobufBase
                .appending(path: "/c/u/user/profile")
                .appending(queryItems: [
                    .init(name: "cmd", value: "303012"),
                    .init(name: "format", value: "protobuf")
                ])
        case .userThreads:
            return Self.protobufBase
                .appending(path: "/c/u/feed/userpost")
                .appending(queryItems: [
                    .init(name: "cmd", value: "303002"),
                    .init(name: "format", value: "protobuf")
                ])
        case .modifyProfile:
            return Self.socialBase.appending(path: "/c/c/profile/modify")
        case .deleteOwnThread:
            return Self.appBase.appending(path: "/c/c/bawu/delthread")
        case .followUser:
            return Self.socialBase.appending(path: "/c/c/user/follow")
        case .unfollowUser:
            return Self.socialBase.appending(path: "/c/c/user/unfollow")
        case .followedUsers:
            return Self.socialBase.appending(path: "/c/u/follow/followList")
        case .followers:
            return Self.socialBase.appending(path: "/c/u/fans/page")
        case .resolveForumID:
            // The www host answers this path with a 301 down to plain http,
            // which the client refuses to follow; the app host serves the same
            // JSON over https.
            return Self.appBase.appending(path: "/f/commit/share/fnameShareApi")
        case .forumMembership:
            return Self.socialBase.appending(path: "/c/f/forum/getUserForumLevelInfo")
        case .followForum:
            return Self.socialBase.appending(path: "/c/c/forum/like")
        case .unfollowForum:
            return Self.socialBase.appending(path: "/c/c/forum/unfavolike")
        case .signForum:
            return Self.appBase.appending(path: "/c/c/forum/sign")
        case .threadStoreList:
            return Self.appBase.appending(path: "/c/u/feed/threadStoreList")
        case .addThreadStore:
            return Self.appBase.appending(path: "/c/c/post/addstore")
        case .removeThreadStore:
            return Self.appBase.appending(path: "/c/c/post/rmstore")
        case .agreePost:
            return Self.socialBase.appending(path: "/c/c/agree/opAgree")
        case .webAddThread:
            return Self.base.appending(path: "/f/commit/thread/add")
        case let .webAddPost(timestamp):
            return Self.base
                .appending(path: "/mo/q/apubpost")
                .appending(queryItems: [.init(name: "_t", value: String(timestamp))])
        case let .webUploadPicture(nonce):
            return Self.base
                .appending(path: "/mo/q/cooluploadpic")
                .appending(queryItems: [
                    .init(name: "type", value: "ajax"),
                    .init(name: "r", value: nonce)
                ])
        case .addPost:
            return Self.protobufBase
                .appending(path: "/c/c/post/add")
                .appending(queryItems: [.init(name: "cmd", value: "309731")])
        case .uploadPicture:
            return Self.protobufBase.appending(path: "/c/s/uploadPicture")
        }
    }
}
