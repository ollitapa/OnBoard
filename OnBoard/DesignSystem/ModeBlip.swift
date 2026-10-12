import SwiftUI

/// The small transport-mode icon overlapping a line badge's corner, matching
/// the storyboard's `mode-blip`. Shared by the Stop board's line badge and
/// the Trips tab's saved-trip badge, so the blip's styling can't drift
/// between them.
struct ModeBlip: View {
    let mode: TransportMode?

    var body: some View {
        if let mode {
            Image(systemName: mode.icon)
                .resizable()
                .font(.title.weight(.heavy))
                .aspectRatio(contentMode: .fit)
                .padding(5)
                .frame(width: 30, height: 30)
                .foregroundStyle(.accentDeep)
                .background(Color.panel, in: Circle())
                .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
                .offset(x: 10, y: 15)
        }
    }
}

#Preview("Mode blips") {
    VStack(spacing: 20) {
        ModeBlip(mode: "BUS")
        ModeBlip(mode: "TRAM")
        ModeBlip(mode: nil)
    }
    .padding()
}
