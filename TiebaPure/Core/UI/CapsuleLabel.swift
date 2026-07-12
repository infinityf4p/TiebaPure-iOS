import SwiftUI

struct CapsuleLabel: View {
    let text: String
    let systemImage: String?
    let isSelected: Bool

    init(_ text: String, systemImage: String? = nil, isSelected: Bool = false) {
        self.text = text
        self.systemImage = systemImage
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(spacing: TiebaPureTheme.Spacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .accessibilityHidden(true)
            }

            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? Color.white : TiebaPureTheme.ColorToken.primaryAccent)
        .padding(.horizontal, TiebaPureTheme.Spacing.xs)
        .padding(.vertical, TiebaPureTheme.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: TiebaPureTheme.Radius.chip, style: .continuous)
                .fill(isSelected ? TiebaPureTheme.ColorToken.primaryAccent : TiebaPureTheme.ColorToken.readerSecondarySurface)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
