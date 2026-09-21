import SwiftUI

/// The app's standard loading placeholder, an accent-tinted spinner shown
/// while a screen's first load is in flight.
struct LoadingIndicator: View {

    var body: some View {
        ProgressView()
            .tint(.accent)
    }
}

#Preview("Loading") {
    LoadingIndicator()
}
