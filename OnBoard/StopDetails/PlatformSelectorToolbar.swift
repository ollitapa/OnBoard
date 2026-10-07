import SwiftUI

/// A horizontal scrollable toolbar for selecting between platforms at a combined stop.
/// - Displays a button for each platform.
/// - **Toggle behavior:** Tapping the selected platform deselects it (shows all).
/// - Automatically scrolls to center the selected platform.
/// - Uses the app's design tokens (colors, typography).
struct PlatformSelectorToolbar: View {
    @Binding var selectedPlatformId: String?
    let platforms: [StopPlatform]
    let onToggle: (String?) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Platform buttons
                    ForEach(platforms) { platform in
                        PlatformButton(
                            label: platform.name,
                            isSelected: selectedPlatformId == platform.id,
                            action: { onToggle(platform.id) }
                        )
                        .id(platform.id)
                    }
                }
                .padding(.horizontal, 8)
                .onChange(of: selectedPlatformId) { _ in
                    // Scroll to the selected button (or first button if deselected)
                    withAnimation {
                        let targetId = selectedPlatformId ?? platforms.first?.id
                        if let targetId {
                            proxy.scrollTo(targetId, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(height: 44) // Match tab bar height
        .background(Color.panel.shadow(.drop(color: .black.opacity(0.1), radius: 2)))
    }
}

/// A pill-style button for platform selection.
/// **Toggle behavior:** Tapping a selected button deselects it.
private struct PlatformButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .ink)
                
                if isSelected {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected 
                    ? Color.accent 
                    : Color.panel
            )
            .clipShape(Capsule())
            .shadow(
                color: isSelected ? .accent.opacity(0.3) : .clear,
                radius: 2,
                y: 1
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Platform \(label), \(isSelected ? "selected" : "not selected")")
        .accessibilityHint(isSelected ? "Tap to show all platforms" : "Tap to filter to this platform")
    }
}
