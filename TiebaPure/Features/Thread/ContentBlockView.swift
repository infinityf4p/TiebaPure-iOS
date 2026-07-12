import SwiftUI
import UIKit

struct ContentBlocksView: View {
    let blocks: [ContentBlock]
    var textStyle: InlineContentText.Style = .body
    var lineLimit: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
            ForEach(InlineContentGroup.groups(from: blocks)) { group in
                switch group.kind {
                case let .inline(inlineBlocks):
                    InlineContentText(blocks: inlineBlocks, style: textStyle, lineLimit: lineLimit)
                case let .media(mediaBlocks):
                    MediaBlocksView(blocks: mediaBlocks)
                }
            }
        }
    }
}

struct ContentBlockView: View {
    let block: ContentBlock

    var body: some View {
        switch block {
        case let .text(text):
            Text(text)
                .font(.body)
                .textSelection(.enabled)
        case let .link(title, url):
            if let url, let safeURL = TiebaURL.webpage(url.absoluteString) {
                Link(title.isEmpty ? safeURL.absoluteString : title, destination: safeURL)
                    .font(.body)
                    .foregroundStyle(TiebaPureTheme.ColorToken.primaryAccent)
            } else {
                Text(title)
                    .font(.body)
            }
        case let .mention(_, text):
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
        case let .emoticon(code):
            TiebaEmoticonView(code: code)
        case let .image(image):
            ImageViewer(image: image)
        case let .video(video):
            VideoPlayerView(video: video)
        }
    }
}

struct TiebaEmoticonView: View {
    let code: String
    var size: CGFloat = 28

    var body: some View {
        if let url = TiebaEmoticon.imageURL(for: code),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .accessibilityLabel(TiebaEmoticon.displayText(for: code))
        } else {
            Text(TiebaEmoticon.displayText(for: code))
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

struct KeywordHighlightSegment: Equatable, Sendable {
    var text: String
    var isHighlighted: Bool
}

enum KeywordHighlighter {
    static func segments(in text: String, keyword: String?) -> [KeywordHighlightSegment] {
        let trimmedKeyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.isEmpty == false else { return [] }
        guard trimmedKeyword.isEmpty == false else {
            return [KeywordHighlightSegment(text: text, isHighlighted: false)]
        }

        var segments: [KeywordHighlightSegment] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let range = text.range(
                of: trimmedKeyword,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchStart..<text.endIndex
              ) {
            if searchStart < range.lowerBound {
                segments.append(KeywordHighlightSegment(
                    text: String(text[searchStart..<range.lowerBound]),
                    isHighlighted: false
                ))
            }

            segments.append(KeywordHighlightSegment(
                text: String(text[range]),
                isHighlighted: true
            ))
            searchStart = range.upperBound
        }

        if searchStart < text.endIndex {
            segments.append(KeywordHighlightSegment(
                text: String(text[searchStart..<text.endIndex]),
                isHighlighted: false
            ))
        }

        return segments
    }
}

struct KeywordHighlightedText: View {
    let text: String
    var keyword: String?
    var font: Font
    var lineLimit: Int
    var defaultColor: Color = .primary

    var body: some View {
        composedText
            .font(font)
            .lineLimit(lineLimit)
    }

    private var composedText: Text {
        KeywordHighlighter.segments(in: text, keyword: keyword).reduce(Text("")) { partial, segment in
            partial + Text(segment.text)
                .foregroundColor(segment.isHighlighted ? .red : defaultColor)
        }
    }
}

struct InlineContentText: UIViewRepresentable {
    enum PrefixPart: Equatable {
        case text(String)
        case threadAuthorBadge

        var plainText: String? {
            switch self {
            case let .text(text):
                return text
            case .threadAuthorBadge:
                return nil
            }
        }
    }

    enum Style {
        case body
        case title
        case preview
        case reply
        case subpost

        var font: UIFont {
            switch self {
            case .body:
                return .preferredFont(forTextStyle: .body)
            case .title:
                return .preferredFont(forTextStyle: .title2)
            case .preview:
                return .preferredFont(forTextStyle: .subheadline)
            case .reply:
                return .preferredFont(forTextStyle: .callout)
            case .subpost:
                return .preferredFont(forTextStyle: .subheadline)
            }
        }

        var foregroundColor: UIColor {
            switch self {
            case .preview:
                return .secondaryLabel
            case .body, .title, .reply, .subpost:
                return .label
            }
        }

        var emoticonSize: CGFloat {
            switch self {
            case .title:
                return 26
            case .body:
                return 24
            case .preview:
                return 20
            case .reply:
                return 22
            case .subpost:
                return 18
            }
        }
    }

    let blocks: [ContentBlock]
    var style: Style = .body
    var lineLimit: Int = 0
    var prefix: String?
    var prefixParts: [PrefixPart] = []
    var highlightKeyword: String?
    var allowsLinkInteraction = true

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isScrollEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.textContainer.maximumNumberOfLines = lineLimit
        textView.textContainer.lineBreakMode = lineLimit > 0 ? .byTruncatingTail : .byWordWrapping
        textView.attributedText = attributedString()
        textView.isSelectable = allowsLinkInteraction && containsInteractiveLink
        textView.isUserInteractionEnabled = textView.isSelectable
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else {
            return nil
        }
        let size = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: size.height)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            guard let safeURL = TiebaURL.webpage(URL.absoluteString) else { return false }
            UIApplication.shared.open(safeURL)
            return false
        }
    }

    private func attributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = style.font
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style == .subpost ? 2 : 4
        paragraph.lineBreakMode = .byTruncatingTail

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.foregroundColor,
            .paragraphStyle: paragraph
        ]
        let prefixAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: paragraph
        ]
        let highlightAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.systemRed,
            .paragraphStyle: paragraph
        ]

        let resolvedPrefixParts = prefixParts.isEmpty ? legacyPrefixParts : prefixParts
        for part in resolvedPrefixParts {
            switch part {
            case let .text(text):
                guard text.isEmpty == false else { continue }
                result.append(NSAttributedString(string: text, attributes: prefixAttributes))
            case .threadAuthorBadge:
                result.append(threadAuthorBadgeText(baseFont: font, paragraph: paragraph))
            }
        }

        for block in blocks {
            switch block {
            case let .text(text):
                appendHighlightedText(
                    text,
                    to: result,
                    defaultAttributes: baseAttributes,
                    highlightAttributes: highlightAttributes
                )
            case let .link(title, url):
                let text = title.isEmpty ? url?.absoluteString ?? "" : title
                if let url, let safeURL = TiebaURL.webpage(url.absoluteString) {
                    var attributes = baseAttributes
                    attributes[.link] = safeURL
                    attributes[.foregroundColor] = UIColor.link
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    result.append(NSAttributedString(string: text, attributes: attributes))
                } else {
                    appendHighlightedText(text, to: result, defaultAttributes: baseAttributes, highlightAttributes: highlightAttributes)
                }
            case let .mention(_, text):
                appendHighlightedText(
                    text,
                    to: result,
                    defaultAttributes: baseAttributes,
                    highlightAttributes: highlightAttributes
                )
            case let .emoticon(code):
                result.append(emoticonAttachment(for: code, font: font, attributes: baseAttributes))
            case .image, .video:
                break
            }
        }

        return result
    }

    private func appendHighlightedText(
        _ text: String,
        to result: NSMutableAttributedString,
        defaultAttributes: [NSAttributedString.Key: Any],
        highlightAttributes: [NSAttributedString.Key: Any]
    ) {
        for segment in KeywordHighlighter.segments(in: text, keyword: highlightKeyword) {
            result.append(NSAttributedString(
                string: segment.text,
                attributes: segment.isHighlighted ? highlightAttributes : defaultAttributes
            ))
        }
    }

    private func emoticonAttachment(
        for code: String,
        font: UIFont,
        attributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        guard let url = TiebaEmoticon.imageURL(for: code),
              let image = UIImage(contentsOfFile: url.path) else {
            return NSAttributedString(string: TiebaEmoticon.displayText(for: code), attributes: attributes)
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        let size = style.emoticonSize
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - size) / 2, width: size, height: size)
        return NSAttributedString(attachment: attachment)
    }

    private var legacyPrefixParts: [PrefixPart] {
        guard let prefix, prefix.isEmpty == false else { return [] }
        return [.text(prefix)]
    }

    private func threadAuthorBadgeText(baseFont: UIFont, paragraph: NSParagraphStyle) -> NSAttributedString {
        let badgeFont = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: UIFont.systemFont(ofSize: 11, weight: .bold)
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: badgeFont,
            .foregroundColor: UIColor.label,
            .backgroundColor: UIColor.systemBlue.withAlphaComponent(0.16),
            .paragraphStyle: paragraph,
            .baselineOffset: (baseFont.capHeight - badgeFont.capHeight) / 2
        ]
        return NSAttributedString(string: " 楼主 ", attributes: attributes)
    }

    private var containsInteractiveLink: Bool {
        blocks.contains { block in
            guard case let .link(_, url) = block, let url else { return false }
            return TiebaURL.webpage(url.absoluteString) != nil
        }
    }
}

private struct InlineContentGroup: Identifiable {
    enum Kind {
        case inline([ContentBlock])
        case media([ContentBlock])
    }

    var id: Int
    var kind: Kind

    static func groups(from blocks: [ContentBlock]) -> [InlineContentGroup] {
        var result: [InlineContentGroup] = []
        var inline: [ContentBlock] = []
        var media: [ContentBlock] = []
        var index = 0

        func flushInline() {
            guard inline.isEmpty == false else { return }
            result.append(InlineContentGroup(id: index, kind: .inline(inline)))
            index += 1
            inline = []
        }

        func flushMedia() {
            guard media.isEmpty == false else { return }
            result.append(InlineContentGroup(id: index, kind: .media(media)))
            index += 1
            media = []
        }

        for block in blocks {
            switch block {
            case .text, .link, .mention, .emoticon:
                flushMedia()
                inline.append(block)
            case .image, .video:
                flushInline()
                media.append(block)
            }
        }

        flushInline()
        flushMedia()
        return result
    }
}

private struct MediaBlocksView: View {
    let blocks: [ContentBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { offset, block in
                switch block {
                case let .image(image):
                    ImageViewer(
                        image: image,
                        galleryImages: imageContents,
                        galleryIndex: imageIndex(for: offset)
                    )
                case let .video(video):
                    VideoPlayerView(video: video)
                default:
                    ContentBlockView(block: block)
                }
            }
        }
    }

    private var imageContents: [ImageContent] {
        blocks.compactMap { block in
            if case let .image(image) = block {
                return image
            }
            return nil
        }
    }

    private func imageIndex(for offset: Int) -> Int {
        blocks.prefix(offset).reduce(0) { count, block in
            if case .image = block {
                return count + 1
            }
            return count
        }
    }
}

enum ContentMediaPresentationPolicy {
    static func usesGrid(for blocks: [ContentBlock]) -> Bool {
        false
    }
}
