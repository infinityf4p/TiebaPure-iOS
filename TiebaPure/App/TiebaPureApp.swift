import Foundation
import SwiftUI

@main
struct TiebaPureApp: App {
    @StateObject private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("UITEST_IMAGE_VIEWER") {
                ImageViewerUITestHost()
            } else {
                RootView()
                    .environmentObject(environment)
            }
#else
            RootView()
                .environmentObject(environment)
#endif
        }
    }
}
