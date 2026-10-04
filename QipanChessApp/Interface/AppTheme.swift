import SwiftUI

enum AppTheme {
    static let boardLight = Color(red: 0.88, green: 0.82, blue: 0.70)
    static let boardDark = Color(red: 0.43, green: 0.31, blue: 0.24)
    static let accent = Color(red: 0.95, green: 0.64, blue: 0.20)
    static let treeWhite = Color(red: 0.97, green: 0.92, blue: 0.82)
    static let treeBlack = Color(red: 0.25, green: 0.30, blue: 0.34)
    static let whiteControl = Color(red: 0.08, green: 0.42, blue: 1.00)
    static let blackControl = Color(red: 1.00, green: 0.14, blue: 0.20)
    static let overlapControl = Color(red: 0.64, green: 0.18, blue: 0.90)
    static let primaryRoute = Color(red: 1.00, green: 0.68, blue: 0.12)
    static let replyRoute = Color(red: 0.16, green: 0.78, blue: 0.96)
    static let aggressiveStrategy = Color(red: 0.74, green: 0.10, blue: 0.13)
    static let balancedStrategy = Color(red: 0.96, green: 0.48, blue: 0.08)
    static let conservativeStrategy = Color(red: 0.98, green: 0.79, blue: 0.24)
    static let openingHint = Color(red: 0.72, green: 0.36, blue: 0.96)

    static var appBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }

    static var panelBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
}
