import SwiftUI

struct ReaderCard<Content: View>: View {
    private let showsDivider: Bool
    private let cornerRadius: CGFloat
    private let action: (() -> Void)?
    private let content: Content

    init(
        showsDivider: Bool = true,
        cornerRadius: CGFloat = 0,
        action: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.showsDivider = showsDivider
        self.cornerRadius = cornerRadius
        self.action = action
        self.content = content()
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    cardContent
                }
                .buttonStyle(.plain)
            } else {
                cardContent
            }
        }
    }

    private var cardContent: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, TiebaPureTheme.Spacing.md)
                .padding(.vertical, TiebaPureTheme.Spacing.sm)
                .contentShape(Rectangle())

            if showsDivider {
                Divider()
                    .padding(.leading, TiebaPureTheme.Spacing.md)
            }
        }
        .background(
            Color(uiColor: .systemBackground),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
