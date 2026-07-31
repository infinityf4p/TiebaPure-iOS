import SwiftUI
import UIKit
import CoreText

enum ThreadContentDisplayPolicy {
    static let detailLineLimit = 0
    static let summaryLineLimit = 2
    static let paragraphLineBreakMode: NSLineBreakMode = .byWordWrapping

    static func maximumNumberOfLines(for lineLimit: Int) -> Int {
        max(lineLimit, 0)
    }

    static func lineBreakMode(for lineLimit: Int) -> NSLineBreakMode {
        maximumNumberOfLines(for: lineLimit) == 0 ? .byWordWrapping : .byTruncatingTail
    }
}

enum ThreadContentInteractionPolicy {
    static func allowsTextSelection(for lineLimit: Int) -> Bool {
        ThreadContentDisplayPolicy.maximumNumberOfLines(for: lineLimit) == 0
    }
}

enum InlineUserNamePresentation {
    static let foregroundColor = UIColor.secondaryLabel
}

struct ContentBlocksView: View {
    let blocks: [ContentBlock]
    var textStyle: InlineContentText.Style = .body
    var lineLimit: Int = ThreadContentDisplayPolicy.detailLineLimit
    var inlineAccessibilityIdentifier: String?
    var onOpenUser: ((UserSummary) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
            ForEach(InlineContentGroup.groups(from: blocks)) { group in
                switch group.kind {
                case let .inline(inlineBlocks):
                    InlineContentText(
                        blocks: inlineBlocks,
                        style: textStyle,
                        lineLimit: lineLimit,
                        allowsTextSelection: ThreadContentInteractionPolicy.allowsTextSelection(
                            for: lineLimit
                        ),
                        accessibilityIdentifier: inlineAccessibilityIdentifier,
                        onOpenUser: onOpenUser
                    )
                    .fixedSize(horizontal: false, vertical: true)
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

    // Redraw when artwork that was missing arrives from the network.
    @ObservedObject private var artwork = TiebaEmoticonArtwork.shared

    var body: some View {
        if let image = TiebaEmoticon.cachedImage(for: code) {
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

final class InlineContentTextView: UITextView {
    var allowsTextSelection = false

    private var appliedDisplayScale: CGFloat = 0
    private var cachedFittingText: NSAttributedString?
    private var cachedFittingWidth: CGFloat = 0
    private var cachedFittingMaximumNumberOfLines = 0
    private var cachedFittingLineBreakMode: NSLineBreakMode = .byWordWrapping
    private var cachedFittingDisplayScale: CGFloat = 0
    private var cachedFittingSize: CGSize = .zero

    init() {
        // Let UITextView own its single live TextKit stack. Supplying a custom
        // TextKit 1 trio bypasses part of UIKit's letterform-aware fitting path
        // on current iOS releases: stacked marks then draw outside the height
        // returned by `sizeThatFits`. The view-owned stack keeps measurement,
        // drawing, links, and selection on the same supported path.
        super.init(frame: .zero, textContainer: nil)
        textContainer.lineFragmentPadding = 0
        textContainer.widthTracksTextView = false
        // Ask UIKit to size from the actual letterform extents. The default
        // typographic rule can omit extreme ascenders/descenders (for example
        // stacked combining marks and tall scripts), which makes a correctly
        // measured line fragment still render with its first pixels clipped.
        if #available(iOS 17.0, *) {
            sizingRule = .oversize
        }
        // UIKit rewrites the live textStorage fonts in place on Dynamic Type
        // changes, so the next apply() would compare equal against metrics
        // measured for the old font size. Drop the memoized state so it
        // re-measures.
        registerForTraitChanges(
            [UITraitPreferredContentSizeCategory.self, UITraitLegibilityWeight.self]
        ) { (view: InlineContentTextView, _) in
            view.appliedDisplayScale = 0
            view.cachedFittingText = nil
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(
        attributedText: NSAttributedString,
        maximumNumberOfLines: Int,
        lineBreakMode: NSLineBreakMode
    ) {
        let displayScale = window?.screen.scale ?? UIScreen.main.scale
        // SwiftUI rebuilds the attributed string for every update and measure
        // pass. An application identical to the live state can skip the
        // CTLine inset measurement entirely. Attachment-bearing strings
        // compare unequal per instance, which only costs a recompute.
        if displayScale == appliedDisplayScale,
           textContainer.maximumNumberOfLines == maximumNumberOfLines,
           textContainer.lineBreakMode == lineBreakMode,
           textStorage.isEqual(to: attributedText) {
            return
        }
        appliedDisplayScale = displayScale
        var needsLayoutInvalidation = false
        let resolvedInsets = InlineContentTextLayout.textContainerInsets(
            for: attributedText,
            displayScale: displayScale
        )
        if InlineContentTextLayout.insetsAreEqual(textContainerInset, resolvedInsets) == false {
            textContainerInset = resolvedInsets
            needsLayoutInvalidation = true
        }
        if textStorage.isEqual(to: attributedText) == false {
            textStorage.setAttributedString(attributedText)
            needsLayoutInvalidation = true
        }
        if textContainer.maximumNumberOfLines != maximumNumberOfLines {
            textContainer.maximumNumberOfLines = maximumNumberOfLines
            needsLayoutInvalidation = true
        }
        if textContainer.lineBreakMode != lineBreakMode {
            textContainer.lineBreakMode = lineBreakMode
            needsLayoutInvalidation = true
        }
        if needsLayoutInvalidation {
            invalidateLiveLayout()
        }
    }

    func fittingSize(
        width: CGFloat,
        attributedText: NSAttributedString,
        maximumNumberOfLines: Int,
        lineBreakMode: NSLineBreakMode
    ) -> CGSize {
        // SwiftUI probes sizeThatFits several times per layout pass with
        // identical inputs. The last measurement is memoized on the full
        // input key; content changes always miss because the key includes
        // the attributed text itself.
        let displayScale = window?.screen.scale ?? UIScreen.main.scale
        if let cachedFittingText,
           cachedFittingWidth == width,
           cachedFittingMaximumNumberOfLines == maximumNumberOfLines,
           cachedFittingLineBreakMode == lineBreakMode,
           cachedFittingDisplayScale == displayScale,
           cachedFittingText.isEqual(to: attributedText) {
            return cachedFittingSize
        }
        apply(
            attributedText: attributedText,
            maximumNumberOfLines: maximumNumberOfLines,
            lineBreakMode: lineBreakMode
        )
        configureTextContainer(forViewWidth: width)
        layoutManager.ensureLayout(for: textContainer)

        let usedRect = layoutManager.usedRect(for: textContainer)
        let extraLineRect = layoutManager.extraLineFragmentRect
        let geometryHeight = InlineContentTextLayout.measuredHeight(
            usedRect: usedRect,
            extraLineFragmentRect: extraLineRect,
            containerInset: textContainerInset
        )
        // UIKit's own fitting height and the live TextKit geometry both come
        // from this view. Taking their maximum also accounts for a trailing
        // extra line fragment without introducing a fixed safety padding.
        let nativeHeight = super.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        ).height
        let liveLayoutHeight = ceil(max(geometryHeight, nativeHeight))
        let size = CGSize(width: width, height: liveLayoutHeight)
        cachedFittingText = attributedText.copy() as? NSAttributedString
        cachedFittingWidth = width
        cachedFittingMaximumNumberOfLines = maximumNumberOfLines
        cachedFittingLineBreakMode = lineBreakMode
        cachedFittingDisplayScale = displayScale
        cachedFittingSize = size
        return size
    }

    var renderedTextBoundsInView: CGRect {
        layoutManager.ensureLayout(for: textContainer)
        return layoutManager.usedRect(for: textContainer).offsetBy(
            dx: textContainerInset.left - contentOffset.x,
            dy: textContainerInset.top - contentOffset.y
        )
    }

    override func layoutSubviews() {
        // Update the live container before UIKit lays out glyphs. Mutating it
        // after super.layoutSubviews() leaves one frame drawn with stale width,
        // which is the source of intermittent clipping during cell reuse.
        configureTextContainer(forViewWidth: bounds.width)
        super.layoutSubviews()
        if abs(contentOffset.x) > 0.01 || abs(contentOffset.y) > 0.01 {
            setContentOffset(.zero, animated: false)
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event), isSelectable else {
            return false
        }

        let textPoint = CGPoint(
            x: point.x - textContainerInset.left,
            y: point.y - textContainerInset.top
        )
        guard textPoint.x >= 0, textPoint.y >= 0, layoutManager.numberOfGlyphs > 0 else {
            return false
        }

        let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return false }

        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.insetBy(dx: -4, dy: -4).contains(textPoint) else { return false }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return false }
        if allowsTextSelection {
            return true
        }
        return textStorage.attribute(.link, at: characterIndex, effectiveRange: nil) != nil
    }

    private func configureTextContainer(forViewWidth width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        let availableWidth = max(width - textContainerInset.left - textContainerInset.right, 0)
        let targetSize = CGSize(
            width: availableWidth,
            height: CGFloat.greatestFiniteMagnitude
        )
        guard abs(textContainer.size.width - targetSize.width) > 0.25
                || textContainer.size.height != targetSize.height else { return }
        textContainer.size = targetSize
        invalidateLiveLayout()
    }

    private func invalidateLiveLayout() {
        layoutManager.invalidateLayout(
            forCharacterRange: NSRange(location: 0, length: textStorage.length),
            actualCharacterRange: nil
        )
        setNeedsLayout()
        setNeedsDisplay()
    }
}

struct InlineContentText: UIViewRepresentable {
    // Attributed strings are built synchronously, so an emoticon that has no
    // artwork yet renders as text; this rebuilds the run once it downloads.
    @ObservedObject private var artwork = TiebaEmoticonArtwork.shared


    enum PrefixPart: Equatable {
        case text(String)
        case user(UserSummary)
        case threadAuthorBadge

        var plainText: String? {
            switch self {
            case let .text(text):
                return text
            case let .user(user):
                return user.displayNameResolved
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
    var lineLimit: Int = ThreadContentDisplayPolicy.detailLineLimit
    var prefix: String?
    var prefixParts: [PrefixPart] = []
    var highlightKeyword: String?
    var allowsLinkInteraction = true
    var allowsTextSelection = false
    var accessibilityIdentifier: String?
    var onOpenUser: ((UserSummary) -> Void)?
    var emoticonImageProvider: (String) -> UIImage? = { code in
        TiebaEmoticon.cachedImage(for: code)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenUser: onOpenUser)
    }

    func makeUIView(context: Context) -> InlineContentTextView {
        let textView = InlineContentTextView()
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.isEditable = false
        textView.isScrollEnabled = false
        // UITextView keeps an internal pan recognizer even when scrolling is
        // disabled. Let the enclosing thread ScrollView own vertical drags,
        // while the text view continues to handle taps on real HTTPS links.
        textView.panGestureRecognizer.isEnabled = false
        textView.adjustsFontForContentSizeCategory = true
        // Vertical room comes from UIKit's letterform-aware oversize rule,
        // rather than a fixed padding that only masks a subset of fonts.
        textView.textContainerInset = .zero
        textView.contentInset = .zero
        textView.scrollIndicatorInsets = .zero
        textView.contentInsetAdjustmentBehavior = .never
        textView.automaticallyAdjustsScrollIndicatorInsets = false
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentHuggingPriority(.defaultHigh, for: .vertical)
        // Links carry their own semantic colors. Keeping this empty lets
        // external URLs stay blue while user links remain secondary grey.
        textView.linkTextAttributes = [:]
        textView.delegate = context.coordinator
        textView.accessibilityValue = accessibilityText()
        return textView
    }

    func updateUIView(_ textView: InlineContentTextView, context: Context) {
        textView.accessibilityIdentifier = accessibilityIdentifier
        textView.accessibilityValue = accessibilityText()
        textView.apply(
            attributedText: attributedString(),
            maximumNumberOfLines: ThreadContentDisplayPolicy.maximumNumberOfLines(for: lineLimit),
            lineBreakMode: ThreadContentDisplayPolicy.lineBreakMode(for: lineLimit)
        )
        let supportsInteraction = allowsLinkInteraction || allowsTextSelection
        textView.isSelectable = supportsInteraction
        textView.isUserInteractionEnabled = supportsInteraction
        textView.allowsTextSelection = allowsTextSelection
        textView.panGestureRecognizer.isEnabled = false
        if abs(textView.contentOffset.x) > 0.01 || abs(textView.contentOffset.y) > 0.01 {
            textView.setContentOffset(.zero, animated: false)
        }
        context.coordinator.onOpenUser = onOpenUser
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: InlineContentTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else {
            return nil
        }
        return uiView.fittingSize(
            width: width,
            attributedText: attributedString(),
            maximumNumberOfLines: ThreadContentDisplayPolicy.maximumNumberOfLines(for: lineLimit),
            lineBreakMode: ThreadContentDisplayPolicy.lineBreakMode(for: lineLimit)
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var onOpenUser: ((UserSummary) -> Void)?

        init(onOpenUser: ((UserSummary) -> Void)?) {
            self.onOpenUser = onOpenUser
        }

        func textView(
            _ textView: UITextView,
            shouldInteractWith URL: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            if let user = InlineUserProfileLink.user(from: URL) {
                onOpenUser?(user)
                return false
            }
            guard let safeURL = TiebaURL.webpage(URL.absoluteString) else { return false }
            UIApplication.shared.open(safeURL)
            return false
        }
    }

    func attributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = style.font
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = style == .subpost ? 2 : 4
        paragraph.lineBreakMode = ThreadContentDisplayPolicy.paragraphLineBreakMode

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: style.foregroundColor,
            .paragraphStyle: paragraph
        ]
        let prefixAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: InlineUserNamePresentation.foregroundColor,
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
            case let .user(user):
                let text = user.displayNameResolved
                guard text.isEmpty == false else { continue }
                var attributes = prefixAttributes
                if onOpenUser != nil,
                   let url = InlineUserProfileLink.url(user: user) {
                    attributes[.link] = url
                }
                result.append(NSAttributedString(string: text, attributes: attributes))
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
            case let .mention(userID, text):
                var attributes = baseAttributes
                // A reply target remains a secondary user name even when the
                // server omits its UID. A name-only link is resolved through
                // the exact user search endpoint when it is activated.
                attributes[.foregroundColor] = InlineUserNamePresentation.foregroundColor
                if onOpenUser != nil,
                   let url = InlineUserProfileLink.url(
                    userID: userID ?? 0,
                    displayText: text
                   ) {
                    attributes[.link] = url
                }
                result.append(NSAttributedString(string: text, attributes: attributes))
            case let .emoticon(code):
                result.append(emoticonAttachment(for: code, font: font, attributes: baseAttributes))
            case .image, .video:
                break
            }
        }

        return result
    }

    // Emoticons render as attachment characters (U+FFFC), which VoiceOver
    // skips. The spoken value mirrors the rendered text with each emoticon
    // replaced by its bracketed display name.
    func accessibilityText() -> String {
        var result = ""
        let resolvedPrefixParts = prefixParts.isEmpty ? legacyPrefixParts : prefixParts
        for part in resolvedPrefixParts {
            switch part {
            case let .text(text):
                result.append(text)
            case let .user(user):
                result.append(user.displayNameResolved)
            case .threadAuthorBadge:
                result.append(Self.threadAuthorBadgeTitle)
            }
        }
        for block in blocks {
            switch block {
            case let .text(text):
                result.append(text)
            case let .link(title, url):
                result.append(title.isEmpty ? url?.absoluteString ?? "" : title)
            case let .mention(_, text):
                result.append(text)
            case let .emoticon(code):
                result.append(TiebaEmoticon.displayText(for: code))
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
        guard let image = emoticonImageProvider(code) else {
            return NSAttributedString(string: TiebaEmoticon.displayText(for: code), attributes: attributes)
        }

        let attachment = NSTextAttachment()
        attachment.image = image
        // Keep artwork inside the font's own ascent/descent. An attachment
        // taller than that line box makes the row jump when CDN artwork
        // replaces the readable fallback, and can invalidate a reused cell's
        // already measured height.
        let size = min(style.emoticonSize, font.lineHeight)
        let baselineY = font.descender + max((font.lineHeight - size) / 2, 0)
        attachment.bounds = CGRect(x: 0, y: baselineY, width: size, height: size)
        return NSAttributedString(attachment: attachment)
    }

    private var legacyPrefixParts: [PrefixPart] {
        guard let prefix, prefix.isEmpty == false else { return [] }
        return [.text(prefix)]
    }

    private static let threadAuthorBadgeTitle = " 楼主 "

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
        return NSAttributedString(string: Self.threadAuthorBadgeTitle, attributes: attributes)
    }

}

enum InlineContentTextLayout {
    /// Returns only the vertical space the actual glyph outlines need beyond
    /// their typographic ascent/descent, plus scale-aware raster edge guards.
    /// UIKit documents that even letterform-aware oversize fitting can miss
    /// extreme ascenders and descenders; measuring the Core Text outline avoids
    /// a guessed fixed padding and keeps ordinary Chinese replies compact.
    static func textContainerInsets(
        for attributedText: NSAttributedString,
        displayScale: CGFloat
    ) -> UIEdgeInsets {
        guard attributedText.length > 0 else { return .zero }

        let line = CTLineCreateWithAttributedString(attributedText)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let inkBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        let topOverflow = max(inkBounds.maxY - ascent, 0)
        let bottomOverflow = max(-inkBounds.minY - descent, 0)
        let scale = max(displayScale, 1)
        // Glyph-path bounds are vector bounds. TextKit can shift a fallback
        // font's live baseline by as much as the adjacent logical point. One
        // physical pixel absorbs fractional raster rounding and a second keeps
        // the final antialiased pixel inside (rather than on) the clip edge.
        // Keeping those two quantities separate avoids a scale-dependent edge
        // clip: on a 2x iPad, a plain 1pt inset leaves the last two pixels of a
        // tall script on the clipping boundary even though it is sufficient on
        // a 3x phone.
        let fractionalBaselineGuard: CGFloat = 1
        let physicalPixel = 1 / scale
        let rasterizationGuard = fractionalBaselineGuard + physicalPixel * 2

        return UIEdgeInsets(
            top: ceil(topOverflow * scale) / scale + rasterizationGuard,
            left: 0,
            bottom: ceil(bottomOverflow * scale) / scale + rasterizationGuard,
            right: 0
        )
    }

    static func insetsAreEqual(_ lhs: UIEdgeInsets, _ rhs: UIEdgeInsets) -> Bool {
        abs(lhs.top - rhs.top) < 0.01
            && abs(lhs.left - rhs.left) < 0.01
            && abs(lhs.bottom - rhs.bottom) < 0.01
            && abs(lhs.right - rhs.right) < 0.01
    }

    static func measuredHeight(
        usedRect: CGRect,
        extraLineFragmentRect: CGRect,
        containerInset: UIEdgeInsets
    ) -> CGFloat {
        ceil(
            containerInset.top
                + max(usedRect.maxY, extraLineFragmentRect.maxY, 0)
                + containerInset.bottom
        )
    }
}

enum InlineUserProfileLink {
    private static let scheme = "tiebapure-user"
    private static let host = "profile"

    static func url(userID: Int64, displayText: String) -> URL? {
        url(userID: userID, displayText: displayText, portrait: nil)
    }

    static func url(user: UserSummary) -> URL? {
        url(
            userID: user.id,
            displayText: user.displayNameResolved,
            portrait: user.portrait
        )
    }

    private static func url(
        userID: Int64,
        displayText: String,
        portrait: String?
    ) -> URL? {
        let name = TiebaUserName.referenceText(displayText)
        guard userID > 0 || name.isEmpty == false else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        var queryItems: [URLQueryItem] = []
        if userID > 0 {
            queryItems.append(URLQueryItem(name: "id", value: String(userID)))
        }
        if name.isEmpty == false {
            queryItems.append(URLQueryItem(name: "name", value: name))
        }
        if let portrait, portrait.isEmpty == false {
            queryItems.append(URLQueryItem(name: "portrait", value: portrait))
        }
        components.queryItems = queryItems
        return components.url
    }

    static func user(from url: URL) -> UserSummary? {
        guard url.scheme == scheme,
              url.host == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let userID = components.queryItems?
            .first(where: { $0.name == "id" })?
            .value
            .flatMap(Int64.init) ?? 0
        let name = TiebaUserName.referenceText(
            components.queryItems?.first(where: { $0.name == "name" })?.value ?? ""
        )
        guard userID > 0 || name.isEmpty == false else { return nil }
        let portrait = components.queryItems?
            .first(where: { $0.name == "portrait" })?
            .value ?? ""
        return UserSummary(
            id: userID,
            name: name,
            displayName: name,
            portrait: portrait
        )
    }

    static func normalizedName(_ value: String) -> String {
        TiebaUserName.referenceText(value)
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
