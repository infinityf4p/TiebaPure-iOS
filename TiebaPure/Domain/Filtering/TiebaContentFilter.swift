import Foundation

enum TiebaContentFilter {
    static func shouldKeep(thread: Tieba_ThreadInfo) -> Bool {
        if thread.hasAlaInfo { return false }
        if thread.hasTwzhiboInfo { return false }
        if thread.isDeleted != 0 { return false }
        return true
    }

    static func shouldKeep(post: Tieba_Post) -> Bool {
        if post.hasAdvertisement { return false }
        if post.isFold != 0 { return false }
        return post.content.contains(where: shouldKeep(content:))
    }

    static func shouldKeep(content: Tieba_PbContent) -> Bool {
        if content.type == 10 { return false }
        if content.voiceMd5.isEmpty == false { return false }
        return true
    }
}
