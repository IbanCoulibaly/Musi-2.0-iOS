import SwiftUI

extension EnvironmentValues {
    /// Opens the Settings sheet. Set once by `TabContentView`.
    @Entry var openSettings: () -> Void = {}
}

/// The Settings button for the leading edge of each tab's root page. It lives
/// in that page's navigation bar (not floating above every page), so pages
/// pushed on top show their own back button in that spot instead.
struct SettingsButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(action: openSettings) {
            Image(systemName: "gearshape.fill")
        }
        .accessibilityLabel("Settings")
    }
}
