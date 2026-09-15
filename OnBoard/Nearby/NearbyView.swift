import SwiftUI

struct NearbyView: View {

    // Dependencies
    @Environment(\.network) var network

    // Model
    @State var model = NearbyModel()

    var body: some View {
        Text("Nearby")
            .padding()
            .task {
                await model.loadStops(network: network)
            }
    }
}
