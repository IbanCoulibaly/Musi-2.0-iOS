import SwiftUI

@main
struct SaucyMusiApp: App {
    init() {
        AppTypography.configureNavigationAppearance()
    }

    var body: some Scene {
        WindowGroup {
            TabContentView()
                .appFont(.body)
                .background { KeyboardDismissalInstaller() }
        }
    }
}
