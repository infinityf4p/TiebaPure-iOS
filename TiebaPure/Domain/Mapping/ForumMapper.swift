import Foundation

enum ForumMapper {
    static func fromFollowedForum(_ dto: FollowedForumsDTO.ForumDTO) -> Forum {
        Forum(
            id: dto.id,
            name: dto.name,
            displayName: dto.name,
            avatarURL: TiebaURL.make(dto.avatar),
            memberCount: 0,
            threadCount: 0
        )
    }

    static func fromProto(_ proto: Tieba_SimpleForum) -> Forum {
        Forum(
            id: proto.id,
            name: proto.name,
            displayName: proto.name,
            avatarURL: TiebaURL.make(proto.avatar),
            memberCount: Int(proto.memberNum),
            threadCount: Int(proto.postNum)
        )
    }
}
