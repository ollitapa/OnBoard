import SwiftUI

/// The colour tone a ``StatusPill`` renders in, pairing the app's status
/// foreground colours with their tint backgrounds. The storyboard's
/// `status-pill` defines the amber delay and red cancelled variants; the
/// green variant marks a vehicle running ahead of schedule.
enum PillTone {

    /// Yellow text on the yellow tint: a delayed departure.
    case amber

    /// Green text on the green tint: an early departure.
    case green

    /// Red text on the red tint: a cancelled departure or a delay on the
    /// Live Trip screen.
    case red

    /// The pill's foreground colour.
    var foreground: Color {
        switch self {
        case .amber: .statusYellow
        case .green: .statusGreen
        case .red: .statusRed
        }
    }

    /// The pill's background tint.
    var background: Color {
        switch self {
        case .amber: .statusYellowTint
        case .green: .statusGreenTint
        case .red: .statusRedTint
        }
    }
}

/// The tinted capsule pill shared by the Stop board and Live Trip screens,
/// matching the storyboard's `status-pill` spec: a bold caption on a rounded
/// tint background with 8/2 pt padding. The caller renders it only when
/// there is something to show, keeping the "hidden when on time" rule at
/// the call site.
struct StatusPill: View {

    /// The pill's text, e.g. "Delayed 3 min" or "Cancelled".
    let label: String

    /// The colour tone driving the pill's colours.
    let tone: PillTone

    var body: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tone.background, in: Capsule())
    }
}

#Preview("Delayed") {
    StatusPill(label: "Delayed 3 min", tone: .amber)
        .padding()
}

#Preview("Early") {
    StatusPill(label: "Early 2 min", tone: .green)
        .padding()
}

#Preview("Cancelled") {
    StatusPill(label: "Cancelled", tone: .red)
        .padding()
}
