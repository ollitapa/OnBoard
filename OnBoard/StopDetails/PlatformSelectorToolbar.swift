import SwiftUI

/// A horizontal scrollable toolbar for selecting between platforms at a combined stop.
/// - Displays a button for each platform showing its most common destinations.
/// - **Toggle behavior:** Tapping the selected platform deselects it (shows all).
/// - Automatically scrolls to center the selected platform.
/// - Uses the app's design tokens (colors, typography).
struct PlatformSelectorToolbar: View {
    @Binding var selectedPlatformId: String?
    let platforms: [StopPlatform]
    let departures: [CallAtLocation]
    let onToggle: (String?) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Platform buttons
                    ForEach(platforms) { platform in
                        PlatformButton(
                            platform: platform,
                            departures: departures,
                            isSelected: selectedPlatformId == platform.id,
                            action: { onToggle(platform.id) }
                        )
                        .id(platform.id)
                    }
                }
                .padding(.horizontal, 8)
                .onChange(of: selectedPlatformId, initial: true) { _, selectedPlatformId  in
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
    }
}

/// A pill-style button for platform selection showing route destinations.
/// **Toggle behavior:** Tapping a selected button deselects it.
private struct PlatformButton: View {
    let platform: StopPlatform
    let departures: [CallAtLocation]
    let isSelected: Bool
    let action: () -> Void

    /// Extracts the most common destinations from departures for this platform.
    private var destinationSummary: String {
        let platformDepartures = departures.filter { $0.stop?.id == platform.id }
        let directions = platformDepartures.compactMap { $0.route?.direction }
        
        // Group by direction and count
        let directionCounts = Dictionary(directions.map { ($0, 1) }, uniquingKeysWith: +)
        
        // Sort by count (most common first), then alphabetically
        let sortedDirections = directionCounts.sorted { a, b in
            if a.value != b.value {
                return a.value > b.value
            }
            return a.key < b.key
        }
        
        // Take top 2-3 destinations
        let topDirections = sortedDirections.prefix(3).map { $0.key }
        
        // Format as "→ Dest1, Dest2" or just "→ Dest1" if only one
        if topDirections.count == 1 {
            return "→ \(topDirections[0])"
        } else {
            return "→ \(topDirections.joined(separator: ", "))"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(destinationSummary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? .white : .ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
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
        .accessibilityLabel("Platform to \(destinationSummary), \(isSelected ? "selected" : "not selected")")
        .accessibilityHint(isSelected ? "Tap to show all platforms" : "Tap to filter to this platform")
    }
}
