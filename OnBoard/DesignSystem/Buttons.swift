import SwiftUI

/// The app's primary action button, matching the storyboard's `btn-primary`:
/// a large, prominent button for a screen's single main action (e.g. "Open
/// Settings", "Try Again"). Wraps the system bordered-prominent style so the
/// button keeps native platform behaviour and theming.
struct PrimaryButton: View {

    private let title: String
    private let action: () -> Void

    init(_ title: String, action: @escaping () -> Void = {}) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
    }
}

/// The app's secondary text button, matching the storyboard's `btn-text`:
/// a large borderless button for a screen's fallback action (e.g. "Search
/// manually instead"). Always paired below a ``PrimaryButton``.
struct TextButton: View {

    private let title: String
    private let action: () -> Void

    init(_ title: String, action: @escaping () -> Void = {}) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .controlSize(.large)
    }
}

#Preview("Buttons") {
    VStack(spacing: 24) {
        PrimaryButton("Open Settings")
        TextButton("Search manually instead")
    }
    .padding(32)
}
