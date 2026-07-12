import Foundation

enum ContentBlock: Equatable, Sendable {
    case text(String)
    case link(title: String, url: URL?)
    case mention(userID: Int64?, text: String)
    case emoticon(code: String)
    case image(ImageContent)
    case video(VideoContent)

    var plainText: String? {
        switch self {
        case let .text(text):
            return text
        case let .link(title, url):
            return title.isEmpty ? url?.absoluteString : title
        case let .mention(_, text):
            return text
        case let .emoticon(code):
            return TiebaEmoticon.displayText(for: code)
        case .image, .video:
            return nil
        }
    }
}

struct ImageContent: Equatable, Sendable {
    var thumbnailURL: URL?
    var originalURL: URL?
    var width: Int
    var height: Int
    var showOriginalButton: Bool

    var aspectRatio: Double {
        guard width > 0, height > 0 else { return 1 }
        return Double(width) / Double(height)
    }
}

struct VideoContent: Equatable, Sendable {
    var videoURL: URL?
    var coverURL: URL?
    var webURL: URL?
    var width: Int
    var height: Int
    var duration: Int

    var aspectRatio: Double {
        guard width > 0, height > 0 else { return 16.0 / 9.0 }
        return Double(width) / Double(height)
    }
}
