import Foundation

enum TiebaEndpoint {
    static let base = URL(string: "https://tieba.baidu.com")!
    static let appBase = URL(string: "https://c.tieba.baidu.com")!

    case login
    case initNickname
    case webMyInfo
    case followedForums
    case forumPageForm
    case personalized
    case frsPage
    case pbPage
    case pbFloor
    case searchThread

    var url: URL {
        switch self {
        case .login:
            return Self.base.appending(path: "/c/s/login")
        case .initNickname:
            return Self.base.appending(path: "/c/s/initNickname")
        case .webMyInfo:
            return Self.base.appending(path: "/mo/q/newmoindex")
        case .followedForums:
            return Self.base.appending(path: "/c/f/forum/getforumlist")
        case .forumPageForm:
            return Self.appBase.appending(path: "/c/f/frs/page")
        case .personalized:
            return Self.base
                .appending(path: "/c/f/excellent/personalized")
                .appending(queryItems: [.init(name: "cmd", value: "309264")])
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
        }
    }
}
