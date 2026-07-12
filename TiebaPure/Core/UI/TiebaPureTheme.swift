import SwiftUI
import UIKit

enum TiebaPureTheme {
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
    }

    enum Radius {
        static let chip: CGFloat = 6
        static let media: CGFloat = 8
        static let card: CGFloat = 8
    }

    enum AvatarSize {
        static let small: CGFloat = 32
        static let medium: CGFloat = 40
        static let large: CGFloat = 48
    }

    enum IconSize {
        static let inline: CGFloat = 17
        static let toolbar: CGFloat = 22
        static let play: CGFloat = 48
    }

    enum ReadableWidth {
        static let maxPhone: CGFloat = .infinity
        static let maxTablet: CGFloat = 680
    }

    enum ColorToken {
        static let primaryAccent = Color(uiColor: .systemBlue)
        static let videoAccent = Color(red: 0.96, green: 0.62, blue: 0.04)
        static let readerGroupedBackground = Color(uiColor: .systemGroupedBackground)
        static let readerSecondarySurface = Color(uiColor: .secondarySystemGroupedBackground)
        static let readerTertiarySurface = Color(uiColor: .tertiarySystemGroupedBackground)
        static let readerSeparator = Color(uiColor: .separator)
    }
}

extension View {
    func readableWidth(alignment: Alignment = .center) -> some View {
        frame(maxWidth: TiebaPureTheme.ReadableWidth.maxTablet, alignment: alignment)
    }

    func minTouchTarget() -> some View {
        frame(minWidth: 44, minHeight: 44)
    }

}

enum PaginationPrefetchPolicy {
    static func shouldLoadMore(currentIndex: Int, totalCount: Int, threshold: Int = 5) -> Bool {
        guard totalCount > 0, currentIndex >= 0, currentIndex < totalCount else { return false }
        return currentIndex >= max(totalCount - max(threshold, 1), 0)
    }
}
