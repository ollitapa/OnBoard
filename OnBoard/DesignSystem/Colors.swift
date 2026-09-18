import SwiftUI

/// Color tokens from the design storyboard (`Designs/storyboard.html`).
/// 
/// These colors are defined in the asset catalog with light/dark mode variants
/// and should be used throughout the app instead of system colors.
/// 
/// - Light mode: Neutral ramp from Ink (#102A43) to Paper (#F0F4F8)
/// - Dark mode: Inverted neutral ramp with brighter accent/status colors
/// - Brand: Magenta family (#7C1A87, #4E0754, #F5E1F7)
/// - Status: Green (on time), Yellow (delayed), Red (cancelled)

extension Color {
    // MARK: - Neutral Colors

    /// Primary text color. In light mode: #102A43. In dark mode: #F0F4F8.
    static let ink = Color("Ink")

    /// Secondary text color. In light mode: #334E68. In dark mode: #D9E2EC.
    static let inkSoft = Color("InkSoft")

    /// Tertiary/placeholder text. In light mode: #829AB1. In dark mode: #9FB3C8.
    static let mist = Color("Mist")

    /// Border/divider color. In light mode: #BCCCDC. In dark mode: #334E68.
    static let hairline = Color("Hairline")

    /// Grouped content background. In light mode: #F0F4F8. In dark mode: #243B53.
    static let paper = Color("Paper")

    /// Card/row background. In light mode: #FFFFFF. In dark mode: #243B53.
    static let panel = Color("Panel")

    // MARK: - Brand Colors

    /// Primary brand accent. In light mode: #7C1A87. In dark mode: #BB61C7.
    static let accent = Color("Accent")

    /// Dark brand accent for badges. In light mode: #4E0754. In dark mode: #90279C.
    static let accentDeep = Color("AccentDeep")

    /// Light brand accent for highlights. In light mode: #F5E1F7. In dark mode: rgba(187,97,199,0.28).
    static let accentTint = Color("AccentTint")

    // MARK: - Status Colors

    /// On-time status text. In light mode: #0F8613. In dark mode: #91E697.
    static let statusGreen = Color("StatusGreen")

    /// On-time status background. In light mode: #E3F9E5. In dark mode: #07600E.
    static let statusGreenTint = Color("StatusGreenTint")

    /// Delayed status text. In light mode: #F0B429. In dark mode: #F7C948.
    static let statusYellow = Color("StatusYellow")

    /// Delayed status background. In light mode: #FFF3C4. In dark mode: #8D2B0B.
    static let statusYellowTint = Color("StatusYellowTint")

    /// Cancelled status text. In light mode: #CF1124. In dark mode: #F86A6A.
    static let statusRed = Color("StatusRed")

    /// Cancelled status background. In light mode: #FFE3E3. In dark mode: #610316.
    static let statusRedTint = Color("StatusRedTint")

    // MARK: - Favorite Star

    /// Favorite star color. In light mode: #F0B429. In dark mode: #F7C948.
    static let star = Color("Star")
}
