import SwiftUI

/// The colour tone a ``StatusPill`` renders in, pairing the app's status
/// foreground colours with their tint backgrounds. The storyboard's
/// `status-pill` defines the amber delay and red cancelled variants; the
/// green variant marks a vehicle running ahead of schedule.
enum PillTone {

    /// Yellow text on the yellow tint: a delayed departure on the Stop board.
    case amber

    /// Green text on the green tint: an early departure.
    case green

    /// Red text on the red tint: a cancelled departure, or a delay on the
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

/// The tinted capsule pill used across the Stop board and Live Trip screens,
/// matching the storyboard's `status-pill`: a bold label on a rounded tint
/// background. The caller renders it only when there is something to show,
/// keeping the "hidden when on time" rule at the call site.
struct StatusPill: View {

    /// The pill's text size: `.compact` for the Stop board's caption-sized
    /// pill, `.regular` for the Live Trip's slightly larger delay pill.
    enum Size {

        /// The Stop board's departure-row pill: a bold caption with 8/2 pt
        /// padding.
        case compact

        /// The Live Trip's delay pill: a bold subheadline with 9/3 pt
        /// padding, so it reads against the track's larger stop labels.
        case regular

        var font: Font {
            switch self {
            case .compact: .caption.weight(.bold)
            case .regular: .subheadline.weight(.bold)
            }
        }

        var horizontalPadding: CGFloat {
            self == .compact ? 8 : 9
        }

        var verticalPadding: CGFloat {
            self == .compact ? 2 : 3
        }
    }

    /// The pill's text, e.g. "Delayed 3 min" or "Cancelled".
    let label: String

    /// The colour tone driving the pill's colours.
    let tone: PillTone

    /// The pill's size; defaults to the Stop board's compact pill.
    var size: Size = .compact

    var body: some View {
        Text(label)
            .font(size.font)
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
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

#Preview("Live trip delay") {
    StatusPill(label: "Delayed 3 min", tone: .red, size: .regular)
        .padding()
}
