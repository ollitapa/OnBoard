import SwiftUI

/// The app's primary action button style: the storyboard's `btn-primary`
/// re-rendered as Liquid Glass (iOS 26). The label sits on a capsule of
/// accent-tinted interactive glass instead of a flat accent fill, so the
/// button picks up the light and content behind it while keeping the magenta
/// brand colour as the tint. The glass's built-in interactive press response
/// replaces the old accent-to-accentDeep fill swap, so the tint stays stable
/// (rebuilding `Glass` with a different tint per press state drops the
/// system press interaction).
///
/// Used as `Button("Open Settings", action: ...).buttonStyle(.primary)`.
struct PrimaryButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 11)
            .glassEffect(.regular.tint(.accent).interactive(), in: Capsule())
    }
}

/// The app's secondary text button style, matching the storyboard's
/// `btn-text`: ink-soft semibold text with no background. Pressing dims the
/// text. Always paired below a primary button. Deliberately *not* glass —
/// Apple's Liquid Glass guidance reserves the material for navigation-layer
/// and floating controls, not text links in content.
///
/// Used as `Button("Search manually instead", action: ...).buttonStyle(.text)`.
struct TextButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.inkSoft)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.default, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {

    /// The primary action button style; see ``PrimaryButtonStyle``.
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == TextButtonStyle {

    /// The secondary text button style; see ``TextButtonStyle``.
    static var text: TextButtonStyle { TextButtonStyle() }
}

#Preview("Buttons") {
    VStack(spacing: 24) {
        Button("Open Settings") {}
            .buttonStyle(.primary)
        Button("Search manually instead") {}
            .buttonStyle(.text)
    }
    .padding(32)
    .background(Color.paper)
}
