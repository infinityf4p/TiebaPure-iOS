import Foundation
import SwiftUI

@main
struct TiebaPureApp: App {
    @StateObject private var environment = AppEnvironment.live()
    @StateObject private var appearanceStore = AppAppearanceStore.live()

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("UITEST_IMAGE_VIEWER") {
                    ImageViewerUITestHost()
                } else {
                    RootView()
                }
#else
                RootView()
#endif
            }
            .environmentObject(environment)
            .environmentObject(appearanceStore)
            .preferredColorScheme(appearanceStore.selection.preferredColorScheme)
        }
    }
}
