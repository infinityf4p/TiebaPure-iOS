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
    var readerFontSize: ReaderFontSize = .standard
    var readerLineSpacing: ReaderLineSpacing = .standard
    var inlineAccessibilityIdentifier: String?
    var onOpenUser: ((UserSummary) -> Void)?
    var onPlainTextTap: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: TiebaPureTheme.Spacing.sm) {
            ForEach(InlineContentGroup.groups(from: blocks)) { group in
                switch group.kind {
                case let .inline(inlineBlocks):
                    if let plainText = InlinePlainTextPolicy.text(from: inlineBlocks) {
                        PlainInlineContentText(
                            text: plainText,
                            style: textStyle,
                            lineLimit: lineLimit,
                            readerFontSize: readerFontSize,
                            readerLineSpacing: readerLineSpacing,
                            accessibilityIdentifier: inlineAccessibilityIdentifier,
                            onPlainTextTap: onPlainTextTap
                        )
                    } else if InlineNativeTextPolicy.supports(inlineBlocks) {
                        NativeInlineContentText(
                            blocks: inlineBlocks,
                            style: textStyle,
                            lineLimit: lineLimit,
                            readerFontSize: readerFontSize,
                            readerLineSpacing: readerLineSpacing,
                            accessibilityIdentifier: inlineAccessibilityIdentifier,
                            onPlainTextTap: onPlainTextTap
                        )
                        .id(InlineNativeTextPolicy.artworkIdentity(in: inlineBlocks))
                    } else {
                        InlineContentText(
                            blocks: inlineBlocks,
                            style: textStyle,
                            lineLimit: lineLimit,
                            readerFontSize: readerFontSize,
                            readerLineSpacing: readerLineSpacing,
                            allowsTextSelection: ThreadContentInteractionPolicy.allowsTextSelection(
                                for: lineLimit
                            ),
                            accessibilityIdentifier: inlineAccessibilityIdentifier,
                            onOpenUser: onOpenUser,
                            onPlainTextTap: onPlainTextTap
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                case let .media(mediaBlocks):
                    MediaBlocksView(blocks: mediaBlocks)
                case let .voice(voice):
                    if ThreadContentDisplayPolicy.maximumNumberOfLines(for: lineLimit) == 0 {
                        VoicePlaybackControl(voice: voice)
                    } else {
                        InlineContentText(
                            blocks: [.text("[语音]")],
                            style: textStyle,
                            lineLimit: lineLimit,
                            readerFontSize: readerFontSize,
                            readerLineSpacing: readerLineSpacing,
                            allowsTextSelection: false,
                            accessibilityIdentifier: inlineAccessibilityIdentifier
                        )
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

enum InlinePlainTextPolicy {
    static func text(from blocks: [ContentBlock]) -> String? {
        var result = ""
        for block in blocks {
            guard case let .text(text) = block else { return nil }
            result.append(text)
        }
        return result
    }
}

enum InlineNativeTextPolicy {
    static func supports(_ blocks: [ContentBlock]) -> Bool {
        blocks.isEmpty == false && blocks.allSatisfy { block in
            switch block {
            case .text, .emoticon:
                return true
            case .link, .mention, .image, .video, .voice:
                return false
            }
        }
    }

    static func artworkImageNames(in blocks: [ContentBlock]) -> Set<String> {
        Set(blocks.compactMap { block in
            guard case let .emoticon(code) = block else { return nil }
            return TiebaEmoticon.imageName(for: code)
        })
    }

    static func artworkIdentity(in blocks: [ContentBlock]) -> String {
        artworkImageNames(in: blocks).sorted().joined(separator: "|")
    }
}

private struct NativeInlineContentText: View {
    let blocks: [ContentBlock]
    let style: InlineContentText.Style
    let lineLimit: Int
    let readerFontSize: ReaderFontSize
    let readerLineSpacing: ReaderLineSpacing
    let accessibilityIdentifier: String?
    let onPlainTextTap: (() -> Void)?

    @Environment(\.displayScale) private var displayScale
    @StateObject private var artwork: TiebaEmoticonArtworkObserver

    init(
        blocks: [ContentBlock],
        style: InlineContentText.Style,
        lineLimit: Int,
        readerFontSize: ReaderFontSize,
        readerLineSpacing: ReaderLineSpacing,
        accessibilityIdentifier: String?,
        onPlainTextTap: (() -> Void)?
    ) {
        self.blocks = blocks
        self.style = style
        self.lineLimit = lineLimit
        self.readerFontSize = readerFontSize
        self.readerLineSpacing = readerLineSpacing
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onPlainTextTap = onPlainTextTap
        _artwork = StateObject(wrappedValue: TiebaEmoticonArtworkObserver(
            imageNames: InlineNativeTextPolicy.artworkImageNames(in: blocks)
        ))
    }

    var body: some View {
        let _ = artwork.revision
        let font = style.font(readerFontSize: readerFontSize)
        let maximumNumberOfLines = ThreadContentDisplayPolicy.maximumNumberOfLines(for: lineLimit)
        let content = composedText(font: font)
            .font(Font(font))
            .foregroundStyle(Color(uiColor: style.foregroundColor))
            .lineSpacing(ReaderTypographyPolicy.lineSpacing(
                readerLineSpacing,
                context: style == .subpost ? .subpost : .body
            ))
            .lineLimit(maximumNumberOfLines == 0 ? nil : maximumNumberOfLines)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(accessibilityText)

        selectableContent(content)
    }

    private func composedText(font: UIFont) -> Text {
        blocks.reduce(Text("")) { partial, block in
            switch block {
            case let .text(text):
                return partial + Text(verbatim: text)
            case let .emoticon(code):
                let size = min(style.emoticonSize, font.lineHeight)
                if let image = InlineEmoticonImage.image(
                    for: code,
                    pointSize: size,
                    displayScale: displayScale
                ) {
                    let baseline = font.descender + max((font.lineHeight - size) / 2, 0)
                    return partial + Text(Image(uiImage: image)).baselineOffset(baseline)
                }
                return partial + Text(verbatim: TiebaEmoticon.displayText(for: code))
            case .link, .mention, .image, .video, .voice:
                return partial
            }
        }
    }

    private var accessibilityText: String {
        blocks.compactMap(\.plainText).joined()
    }

    @ViewBuilder
    private func selectableContent<Content: View>(_ content: Content) -> some View {
        if ThreadContentInteractionPolicy.allowsTextSelection(for: lineLimit) {
            identifiedContent(content.textSelection(.enabled))
        } else {
            identifiedContent(content.textSelection(.disabled))
        }
    }

    @ViewBuilder
    private func identifiedContent<Content: View>(_ content: Content) -> some View {
        if let accessibilityIdentifier {
            interactiveContent(content.accessibilityIdentifier(accessibilityIdentifier))
        } else {
            interactiveContent(content)
        }
    }

    @ViewBuilder
    private func interactiveContent<Content: View>(_ content: Content) -> some View {
        if let onPlainTextTap {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: onPlainTextTap)
        } else {
            content
        }
    }
}

@MainActor
private enum InlineEmoticonImage {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(
        for code: String,
        pointSize: CGFloat,
        displayScale: CGFloat
    ) -> UIImage? {
        guard pointSize > 0,
              let imageName = TiebaEmoticon.imageName(for: code),
              let source = TiebaEmoticon.cachedImage(for: code) else {
            return nil
        }
        let resolvedScale = max(displayScale, 1)
        let key = "\(imageName)#\(Int((pointSize * resolvedScale).rounded()))" as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let image: UIImage
        if let cgImage = source.cgImage {
            let pixelSize = CGFloat(max(cgImage.width, cgImage.height))
            image = UIImage(
                cgImage: cgImage,
                scale: max(pixelSize / pointSize, 1),
                orientation: source.imageOrientation
            )
        } else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = resolvedScale
            image = UIGraphicsImageRenderer(
                size: CGSize(width: pointSize, height: pointSize),
                format: format
            ).image { _ in
                source.draw(in: CGRect(x: 0, y: 0, width: pointSize, height: pointSize))
            }
        }
        cache.setObject(image, forKey: key)
        return image
    }
}

private struct PlainInlineContentText: View {
    let text: String
    let style: InlineContentText.Style
    let lineLimit: Int
    let readerFontSize: ReaderFontSize
    let readerLineSpacing: ReaderLineSpacing
    let accessibilityIdentifier: String?
    let onPlainTextTap: (() -> Void)?

    var body: some View {
        let maximumNumberOfLines = ThreadContentDisplayPolicy.maximumNumberOfLines(for: lineLimit)
        let content = Text(verbatim: text)
            .font(Font(style.font(readerFontSize: readerFontSize)))
            .foregroundStyle(Color(uiColor: style.foregroundColor))
            .lineSpacing(ReaderTypographyPolicy.lineSpacing(
                readerLineSpacing,
                context: style == .subpost ? .subpost : .body
            ))
            .lineLimit(maximumNumberOfLines == 0 ? nil : maximumNumberOfLines)
            .fixedSize(horizontal: false, vertical: true)

        selectableContent(content)
    }

    @ViewBuilder
    private func selectableContent<Content: View>(_ content: Content) -> some View {
        if ThreadContentInteractionPolicy.allowsTextSelection(for: lineLimit) {
            identifiedContent(content.textSelection(.enabled))
        } else {
            identifiedContent(content.textSelection(.disabled))
        }
    }

    @ViewBuilder
    private func identifiedContent<Content: View>(_ content: Content) -> some View {
        if let accessibilityIdentifier {
            interactiveContent(content.accessibilityIdentifier(accessibilityIdentifier))
        } else {
            interactiveContent(content)
        }
    }

    @ViewBuilder
    private func interactiveContent<Content: View>(_ content: Content) -> some View {
        if let onPlainTextTap {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: onPlainTextTap)
        } else {
            content
        }
    }
}

enum InlineContentTextTapTarget: Equatable {
    case outsideText
    case plainText
    case link
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
        case let .voice(voice):
            VoicePlaybackControl(voice: voice)
        }
    }
}

struct TiebaEmoticonView: View {
    let code: String
    var size: CGFloat

    @StateObject private var artwork: TiebaEmoticonArtworkObserver

    init(code: String, size: CGFloat = 28) {
        self.code = code
        self.size = size
        _artwork = StateObject(wrappedValue: TiebaEmoticonArtworkObserver(code: code))
    }

    var body: some View {
        let _ = artwork.revision
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

    // UITextView installs its own tap recognizers for links and selection, so
    // reuse may only remove the one this app added.
    private weak var plainTextTapRecognizer: UITapGestureRecognizer?

    private var appliedDisplayScale: CGFloat = 0
    private var appliedRenderID: UInt?
    private var cachedFittingText: NSAttributedString?
    private var cachedFittingRenderID: UInt?
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
        if #available(iOS 17.0, *) {
            registerForTraitChanges(
                [UITraitPreferredContentSizeCategory.self, UITraitLegibilityWeight.self]
            ) { (view: InlineContentTextView, _) in
                view.appliedDisplayScale = 0
                view.appliedRenderID = nil
                view.cachedFittingText = nil
                view.cachedFittingRenderID = nil
            }
        } else {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleContentSizeCategoryChange),
                name: UIContentSizeCategory.didChangeNotification,
                object: nil
            )
        }
    }

    @objc private func handleContentSizeCategoryChange() {
        appliedDisplayScale = 0
        appliedRenderID = nil
        cachedFittingText = nil
        cachedFittingRenderID = nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func installPlainTextTap(_ recognizer: UITapGestureRecognizer) {
        if let plainTextTapRecognizer {
            removeGestureRecognizer(plainTextTapRecognizer)
        }
        plainTextTapRecognizer = recognizer
        addGestureRecognizer(recognizer)
    }

    /// Returns a view the lazy stack dropped to a blank state. Everything the
    /// representable configures in `makeUIView` is reapplied there, so this only
    /// has to drop the content, this app's own recognizer, and the metrics
    /// memoized for the previous run.
    func prepareForReuse() {
        delegate = nil
        if let plainTextTapRecognizer {
            removeGestureRecognizer(plainTextTapRecognizer)
            self.plainTextTapRecognizer = nil
        }
        if textStorage.length > 0 {
            textStorage.setAttributedString(NSAttributedString())
        }
        textContainerInset = .zero
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        allowsTextSelection = false
        accessibilityIdentifier = nil
        accessibilityValue = nil
        appliedDisplayScale = 0
        appliedRenderID = nil
        cachedFittingText = nil
        cachedFittingRenderID = nil
        cachedFittingWidth = 0
        cachedFittingMaximumNumberOfLines = 0
        cachedFittingLineBreakMode = .byWordWrapping
        cachedFittingDisplayScale = 0
        cachedFittingSize = .zero
        setContentOffset(.zero, animated: false)
    }

    func apply(
        attributedText: NSAttributedString,
        renderID: UInt? = nil,
        maximumNumberOfLines: Int,
        lineBreakMode: NSLineBreakMode
    ) {
        let displayScale = window?.screen.scale ?? UIScreen.main.scale
        // SwiftUI rebuilds the attributed string for every update and measure
        // pass. An application identical to the live state can skip the
        // CTLine inset measurement entirely. Attachment-bearing strings
        // compare unequal per instance, which only costs a recompute.
        if displayScale == appliedDisplayScale,
           renderID == nil || renderID == appliedRenderID,
           textContainer.maximumNumberOfLines == maximumNumberOfLines,
           textContainer.lineBreakMode == lineBreakMode,
           renderID != nil || textStorage.isEqual(to: attributedText) {
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
        let needsTextReplacement = if let renderID {
            renderID != appliedRenderID
        } else {
            textStorage.isEqual(to: attributedText) == false
        }
        if needsTextReplacement {
            textStorage.setAttributedString(attributedText)
            appliedRenderID = renderID
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
        renderID: UInt? = nil,
        maximumNumberOfLines: Int,
        lineBreakMode: NSLineBreakMode
    ) -> CGSize {
        // SwiftUI probes sizeThatFits several times per layout pass with
        // identical inputs. The last measurement is memoized on the full
        // input key; content changes always miss because the key includes
        // the attributed text itself.
        let displayScale = window?.screen.scale ?? UIScreen.main.scale
        let contentMatches: Bool
        if let renderID {
            contentMatches = renderID == cachedFittingRenderID
        } else if let cachedFittingText {
            contentMatches = cachedFittingText.isEqual(to: attributedText)
        } else {
            contentMatches = false
        }
        if contentMatches,
           cachedFittingWidth == width,
           cachedFittingMaximumNumberOfLines == maximumNumberOfLines,
           cachedFittingLineBreakMode == lineBreakMode,
           cachedFittingDisplayScale == displayScale {
            return cachedFittingSize
        }
        apply(
            attributedText: attributedText,
            renderID: renderID,
            maximumNumberOfLines: maximumNumberOfLines,
            lineBreakMode: lineBreakMode
        )
        configureTextContainer(forViewWidth: width)

        // A row scrolled out of the lazy stack and back in arrives with a new
        // view whose own memo is empty, so the same paragraph would be laid out
        // from scratch again. The height depends only on the run, the width and
        // the text environment, so it is shared across views. The text is still
        // applied above — only the two layout passes below are skipped, and
        // TextKit lays the glyphs out lazily when the view actually draws.
        let sharedKey = InlineContentTextMeasurementCache.Key(
            attributedText: attributedText,
            width: width,
            maximumNumberOfLines: maximumNumberOfLines,
            lineBreakMode: lineBreakMode.rawValue,
            displayScale: displayScale,
            contentSizeCategory: UITraitCollection.current.preferredContentSizeCategory.rawValue,
            legibilityWeight: UITraitCollection.current.legibilityWeight.rawValue
        )
        if let sharedHeight = InlineContentTextMeasurementCache.height(for: sharedKey) {
            let size = CGSize(width: width, height: sharedHeight)
            memoizeFittingSize(
                size,
                attributedText: attributedText,
                renderID: renderID,
                width: width,
                maximumNumberOfLines: maximumNumberOfLines,
                lineBreakMode: lineBreakMode,
                displayScale: displayScale
            )
            return size
        }

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
        InlineContentTextMeasurementCache.store(height: size.height, for: sharedKey)
        memoizeFittingSize(
            size,
            attributedText: attributedText,
            renderID: renderID,
            width: width,
            maximumNumberOfLines: maximumNumberOfLines,
            lineBreakMode: lineBreakMode,
            displayScale: displayScale
        )
        return size
    }

    private func memoizeFittingSize(
        _ size: CGSize,
        attributedText: NSAttributedString,
        renderID: UInt?,
        width: CGFloat,
        maximumNumberOfLines: Int,
        lineBreakMode: NSLineBreakMode,
        displayScale: CGFloat
    ) {
        cachedFittingText = renderID == nil
            ? attributedText.copy() as? NSAttributedString
            : nil
        cachedFittingRenderID = renderID
        cachedFittingWidth = width
        cachedFittingMaximumNumberOfLines = maximumNumberOfLines
        cachedFittingLineBreakMode = lineBreakMode
        cachedFittingDisplayScale = displayScale
        cachedFittingSize = size
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
        let target = tapTarget(at: point)
        if allowsTextSelection {
            return target != .outsideText
        }
        return target == .link
    }

    func tapTarget(at point: CGPoint) -> InlineContentTextTapTarget {
        layoutManager.ensureLayout(for: textContainer)
        let textPoint = CGPoint(
            x: point.x + contentOffset.x - textContainerInset.left,
            y: point.y + contentOffset.y - textContainerInset.top
        )
        guard textPoint.x >= 0, textPoint.y >= 0, layoutManager.numberOfGlyphs > 0 else {
            return .outsideText
        }

        let glyphIndex = layoutManager.glyphIndex(for: textPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return .outsideText }

        let glyphRect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        guard glyphRect.insetBy(dx: -4, dy: -4).contains(textPoint) else {
            return .outsideText
        }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < textStorage.length else { return .outsideText }
        return textStorage.attribute(.link, at: characterIndex, effectiveRange: nil) == nil
            ? .plainText
            : .link
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

/// Recycles the hosted text views themselves.
///
/// Building a `UITextView` costs roughly as much as measuring the paragraph it
/// will show — it brings up a TextKit stack, gesture recognizers and text
/// interactions — and SwiftUI builds a new one for every row that scrolls in.
///
/// Views are only taken back a runloop turn after SwiftUI says it is done with
/// them, and only if SwiftUI has actually detached them by then. Reclaiming a
/// view that is still installed hands the next row a view the previous one can
/// still write to, which is how an earlier attempt lost the links inside
/// rebuilt rows.
@MainActor
enum InlineContentTextViewPool {
    static let capacity = 24

    private static var reusableViews: [InlineContentTextView] = []

    static var pooledViewCount: Int { reusableViews.count }

    static func dequeue() -> InlineContentTextView {
        guard let view = reusableViews.popLast() else {
            return InlineContentTextView()
        }
        view.prepareForReuse()
        return view
    }

    static func recycle(_ view: InlineContentTextView) {
        DispatchQueue.main.async {
            guard view.superview == nil,
                  view.window == nil,
                  reusableViews.count < capacity,
                  reusableViews.contains(where: { $0 === view }) == false else {
                return
            }
            view.prepareForReuse()
            reusableViews.append(view)
        }
    }

    static func drain() {
        reusableViews.removeAll(keepingCapacity: false)
    }
}

/// Paragraph heights shared by every hosted text run.
///
/// SwiftUI has no cell reuse, so scrolling a thread back over rows it already
/// showed rebuilds their text views from nothing. Measuring a paragraph is the
/// expensive half of that, and it is a pure function of the run, the proposed
/// width and the text environment.
@MainActor
enum InlineContentTextMeasurementCache {
    struct Key: Hashable {
        let attributedText: NSAttributedString
        let width: CGFloat
        let maximumNumberOfLines: Int
        let lineBreakMode: Int
        let displayScale: CGFloat
        let contentSizeCategory: String
        let legibilityWeight: Int
    }

    // A few screens of runs at a couple of widths. Entries are tiny, and the
    // oldest half is dropped wholesale rather than tracked per use: an exact
    // LRU would cost more bookkeeping than the measurement it saves.
    static let capacity = 512

    private static var heights: [Key: CGFloat] = [:]
    private static var insertionOrder: [Key] = []

    static var cachedHeightCount: Int { heights.count }

    static func height(for key: Key) -> CGFloat? {
        heights[key]
    }

    static func store(height: CGFloat, for key: Key) {
        guard height.isFinite else { return }
        if heights.updateValue(height, forKey: key) == nil {
            insertionOrder.append(key)
        }
        guard heights.count > capacity else { return }
        let overflow = heights.count - capacity / 2
        for key in insertionOrder.prefix(overflow) {
            heights.removeValue(forKey: key)
        }
        insertionOrder.removeFirst(overflow)
    }

    static func drain() {
        heights.removeAll(keepingCapacity: false)
        insertionOrder.removeAll(keepingCapacity: false)
    }
}

struct InlineContentText: UIViewRepresentable {
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

    enum Style: Equatable {
        case body
        case title
        case preview
        case reply
        case subpost

        func font(readerFontSize: ReaderFontSize) -> UIFont {
            switch self {
            case .body:
                return ReaderTypographyPolicy.font(
                    textStyle: .body,
                    fontSize: readerFontSize
                )
            case .title:
                return ReaderTypographyPolicy.font(
                    textStyle: .title2,
                    fontSize: readerFontSize
                )
            case .preview:
                return ReaderTypographyPolicy.font(
                    textStyle: .subheadline,
                    fontSize: readerFontSize
                )
            case .reply:
                return ReaderTypographyPolicy.font(
                    textStyle: .callout,
                    fontSize: readerFontSize
                )
            case .subpost:
                return ReaderTypographyPolicy.font(
                    textStyle: .subheadline,
                    fontSize: readerFontSize
                )
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
    var readerFontSize: ReaderFontSize = .standard
    var readerLineSpacing: ReaderLineSpacing = .standard
    var prefix: String?
    var prefixParts: [PrefixPart] = []
    var highlightKeyword: String?
    var allowsLinkInteraction = true
    var allowsTextSelection = false
    var accessibilityIdentifier: String?
    var onOpenUser: ((UserSummary) -> Void)?
    var onPlainTextTap: (() -> Void)?
    var emoticonImageProvider: (String) -> UIImage? = { code in
        TiebaEmoticon.cachedImage(for: code)
    }

    fileprivate struct RenderKey: Equatable {
        var blocks: [ContentBlock]
        var style: Style
        var readerFontSize: String
        var readerLineSpacing: String
        var prefix: String?
        var prefixParts: [PrefixPart]
        var highlightKeyword: String?
        var userLinksEnabled: Bool
        var fontName: String
        var fontPointSize: CGFloat
        var fontLineHeight: CGFloat
    }

    fileprivate struct RenderedContent {
        var id: UInt
        var attributedString: NSAttributedString
        var accessibilityText: String
        var emoticonImageNames: Set<String>
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenUser: onOpenUser, onPlainTextTap: onPlainTextTap)
    }

    func makeUIView(context: Context) -> InlineContentTextView {
        let textView = InlineContentTextViewPool.dequeue()
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
        let plainTextTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePlainTextTap(_:))
        )
        plainTextTap.cancelsTouchesInView = false
        plainTextTap.delegate = context.coordinator
        textView.installPlainTextTap(plainTextTap)
        context.coordinator.textView = textView
        return textView
    }

    static func dismantleUIView(_ uiView: InlineContentTextView, coordinator: Coordinator) {
        coordinator.detachFromTextView()
        InlineContentTextViewPool.recycle(uiView)
    }

    func updateUIView(_ textView: InlineContentTextView, context: Context) {
        let rendered = renderedContent(using: context.coordinator)
        textView.accessibilityIdentifier = accessibilityIdentifier
        textView.accessibilityValue = rendered.accessibilityText
        textView.apply(
            attributedText: rendered.attributedString,
            renderID: rendered.id,
            maximumNumberOfLines: ThreadContentDisplayPolicy.maximumNumberOfLines(for: lineLimit),
            lineBreakMode: ThreadContentDisplayPolicy.lineBreakMode(for: lineLimit)
        )
        let supportsInteraction = allowsLinkInteraction || allowsTextSelection || onPlainTextTap != nil
        textView.isSelectable = supportsInteraction
        textView.isUserInteractionEnabled = supportsInteraction
        textView.allowsTextSelection = allowsTextSelection
        textView.panGestureRecognizer.isEnabled = false
        if abs(textView.contentOffset.x) > 0.01 || abs(textView.contentOffset.y) > 0.01 {
            textView.setContentOffset(.zero, animated: false)
        }
        context.coordinator.onOpenUser = onOpenUser
        context.coordinator.onPlainTextTap = onPlainTextTap
        context.coordinator.observeArtwork(
            imageNames: rendered.emoticonImageNames,
            rerender: { [weak textView, weak coordinator = context.coordinator] in
                guard let textView, let coordinator else { return }
                let refreshedContent = renderedContent(using: coordinator)
                textView.accessibilityValue = refreshedContent.accessibilityText
                textView.apply(
                    attributedText: refreshedContent.attributedString,
                    renderID: refreshedContent.id,
                    maximumNumberOfLines: ThreadContentDisplayPolicy.maximumNumberOfLines(for: lineLimit),
                    lineBreakMode: ThreadContentDisplayPolicy.lineBreakMode(for: lineLimit)
                )
            }
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: InlineContentTextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else {
            return nil
        }
        let rendered = renderedContent(using: context.coordinator)
        return uiView.fittingSize(
            width: width,
            attributedText: rendered.attributedString,
            renderID: rendered.id,
            maximumNumberOfLines: ThreadContentDisplayPolicy.maximumNumberOfLines(for: lineLimit),
            lineBreakMode: ThreadContentDisplayPolicy.lineBreakMode(for: lineLimit)
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        weak var textView: InlineContentTextView?
        var onOpenUser: ((UserSummary) -> Void)?
        var onPlainTextTap: (() -> Void)?
        private var observedArtworkImageNames: Set<String> = []
        private var artworkNotificationToken: NSObjectProtocol?
        private var rerenderArtwork: (() -> Void)?
        private var cachedRenderKey: RenderKey?
        private var cachedRenderedContent: RenderedContent?
        private var nextRenderID: UInt = 0

        init(
            onOpenUser: ((UserSummary) -> Void)?,
            onPlainTextTap: (() -> Void)?
        ) {
            self.onOpenUser = onOpenUser
            self.onPlainTextTap = onPlainTextTap
        }

        deinit {
            stopObservingArtwork()
        }

        func observeArtwork(
            imageNames: Set<String>,
            rerender: @escaping () -> Void
        ) {
            observedArtworkImageNames = imageNames
            rerenderArtwork = rerender
            guard imageNames.isEmpty == false else {
                stopObservingArtwork()
                return
            }
            guard artworkNotificationToken == nil else { return }
            artworkNotificationToken = NotificationCenter.default.addObserver(
                forName: TiebaEmoticonArtwork.didChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self,
                      self.observedArtworkImageNames.isDisjoint(
                        with: TiebaEmoticonArtwork.imageNames(from: notification)
                      ) == false else {
                    return
                }
                self.invalidateRenderedContent()
                self.rerenderArtwork?()
            }
        }

        fileprivate func renderedContent(
            for key: RenderKey,
            emoticonImageNames: Set<String>,
            makeAttributedString: () -> NSAttributedString,
            makeAccessibilityText: () -> String
        ) -> RenderedContent {
            if cachedRenderKey == key, let cachedRenderedContent {
                return cachedRenderedContent
            }
            nextRenderID &+= 1
            let content = RenderedContent(
                id: nextRenderID,
                attributedString: makeAttributedString(),
                accessibilityText: makeAccessibilityText(),
                emoticonImageNames: emoticonImageNames
            )
            cachedRenderKey = key
            cachedRenderedContent = content
            return content
        }

        private func invalidateRenderedContent() {
            cachedRenderKey = nil
            cachedRenderedContent = nil
        }

        /// Called when the representable goes away, so a late artwork
        /// notification cannot redraw this run into a view another row now owns.
        func detachFromTextView() {
            stopObservingArtwork()
            rerenderArtwork = nil
            observedArtworkImageNames = []
            textView = nil
        }

        private func stopObservingArtwork() {
            if let artworkNotificationToken {
                NotificationCenter.default.removeObserver(artworkNotificationToken)
                self.artworkNotificationToken = nil
            }
        }

        // UITextView activates links from its own recognizers. A second tap
        // recognizer on the same view makes them fail unless it is declared
        // cooperative, which silently kills every link inside the run.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handlePlainTextTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let textView,
                  textView.tapTarget(at: recognizer.location(in: textView)) == .plainText else {
                return
            }
            onPlainTextTap?()
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

    private func renderedContent(using coordinator: Coordinator) -> RenderedContent {
        coordinator.renderedContent(
            for: renderKey,
            emoticonImageNames: emoticonImageNames,
            makeAttributedString: attributedString,
            makeAccessibilityText: accessibilityText
        )
    }

    private var renderKey: RenderKey {
        let font = style.font(readerFontSize: readerFontSize)
        return RenderKey(
            blocks: blocks,
            style: style,
            readerFontSize: readerFontSize.rawValue,
            readerLineSpacing: readerLineSpacing.rawValue,
            prefix: prefix,
            prefixParts: prefixParts,
            highlightKeyword: highlightKeyword,
            userLinksEnabled: onOpenUser != nil,
            fontName: font.fontName,
            fontPointSize: font.pointSize,
            fontLineHeight: font.lineHeight
        )
    }

    func attributedString() -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = style.font(readerFontSize: readerFontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = ReaderTypographyPolicy.lineSpacing(
            readerLineSpacing,
            context: style == .subpost ? .subpost : .body
        )
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
            case .voice:
                result.append(NSAttributedString(string: "[语音]", attributes: baseAttributes))
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
            case .voice:
                result.append("[语音]")
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

    private var emoticonImageNames: Set<String> {
        Set(blocks.compactMap { block in
            guard case let .emoticon(code) = block else { return nil }
            return TiebaEmoticon.imageName(for: code)
        })
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

        let scale = max(displayScale, 1)
        let fractionalBaselineGuard: CGFloat = 1
        let physicalPixel = 1 / scale
        let rasterizationGuard = fractionalBaselineGuard + physicalPixel * 2
        let baselineInsets = UIEdgeInsets(
            top: rasterizationGuard,
            left: 0,
            bottom: rasterizationGuard,
            right: 0
        )
        guard requiresGlyphOutlineMeasurement(attributedText.string) else {
            return baselineInsets
        }

        let line = CTLineCreateWithAttributedString(attributedText)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        let inkBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        let topOverflow = max(inkBounds.maxY - ascent, 0)
        let bottomOverflow = max(-inkBounds.minY - descent, 0)
        // Glyph-path bounds are vector bounds. TextKit can shift a fallback
        // font's live baseline by as much as the adjacent logical point. One
        // physical pixel absorbs fractional raster rounding and a second keeps
        // the final antialiased pixel inside (rather than on) the clip edge.
        // Keeping those two quantities separate avoids a scale-dependent edge
        // clip: on a 2x iPad, a plain 1pt inset leaves the last two pixels of a
        // tall script on the clipping boundary even though it is sufficient on
        // a 3x phone.
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

    static func requiresGlyphOutlineMeasurement(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            CharacterSet.nonBaseCharacters.contains($0)
        }
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
        case voice(VoiceContent)
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
            case let .voice(voice):
                flushInline()
                flushMedia()
                result.append(InlineContentGroup(id: index, kind: .voice(voice)))
                index += 1
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
