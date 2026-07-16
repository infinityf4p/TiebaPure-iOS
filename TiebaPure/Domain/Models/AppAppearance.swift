import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .light:
            return "sun.max"
        case .dark:
            return "moon.stars"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

@MainActor
final class AppAppearanceStore: ObservableObject {
    nonisolated static let storageKey = "dev.infinityf4p.tiebapure.appearance"

    @Published private(set) var selection: AppAppearance

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = AppAppearanceStore.storageKey
    ) {
        self.defaults = defaults
        self.key = key

        if let rawValue = defaults.string(forKey: key),
           let storedSelection = AppAppearance(rawValue: rawValue) {
            selection = storedSelection
        } else {
            selection = .system
            if defaults.object(forKey: key) != nil {
                defaults.removeObject(forKey: key)
            }
        }
    }

    func select(_ appearance: AppAppearance) {
        guard appearance != selection else { return }

        if appearance == .system {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(appearance.rawValue, forKey: key)
        }
        selection = appearance
    }

    func reset() {
        defaults.removeObject(forKey: key)
        selection = .system
    }

    static func live() -> AppAppearanceStore {
        let store = AppAppearanceStore()

#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("UITEST_RESET_APPEARANCE") {
            store.reset()
        }
#endif

        return store
    }
}
