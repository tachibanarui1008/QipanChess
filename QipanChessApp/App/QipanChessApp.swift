import Interface
import SwiftUI

@main
struct QipanChessApp: App {
    var body: some Scene {
        WindowGroup {
            QipanRootView()
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 780)
        #endif
    }
}
