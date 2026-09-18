import SwiftUI

/// The Live Trip screen ("Step 3 • Tap a departure → track the bus stop by
/// stop" in `Designs/storyboard.html`).
///
/// Shows a header with the route line and an optional delay pill, followed by
/// a vertical "track": a line down the left edge with one node per scheduled
/// stop. Stops already passed fade, the stop the vehicle is at or heading to
/// next carries the bus marker and an "in X min" subtitle, and the destination
/// is flagged as the final stop. The view is driven by ``RouteDetailsModel``
/// and reads its network dependency from the SwiftUI environment, mirroring
/// ``StopDetailsView``.
struct RouteDetailsView: View {

    /// The trip to display, carrying `tripId`/`startDate` to load the schedule
    /// and the line label / direction / delay for the header.
    let route: RouteDetails

    @Environment(\.network) private var network

    @State private var model = RouteDetailsModel()

    @State private var loadingTrigger = 0

    var body: some View {
        Group {
            if let failure = model.failure {
                ContentUnavailableView {
                    Label("Couldn't load the trip", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(failure)
                }
            } else if model.stops.isEmpty {
                if model.isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "No stops",
                        systemImage: "tray",
                        description: Text("This trip has no scheduled stops.")
                    )
                }
            } else {
                TripTrack(
                    route: route,
                    stops: model.stops
                )
            }
        }
        .navigationTitle(Self.title(route))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: loadingTrigger) {
            await model.loadTrip(
                network: network,
                tripId: route.tripId,
                startDate: route.startDate
            )
            try? await Task.sleep(for: .seconds(30)) // refresh every 30s
            loadingTrigger += 1
        }
    }

    /// The inline nav title: "Line 55 • Ropsten", matching the storyboard's
    /// `trip-header .route`. The delay pill is rendered inside the track, not
    /// the nav bar, so the title stays short.
    static func title(_ route: RouteDetails) -> String {
        "Line \(route.lineLabel) • \(route.direction)"
    }
}

// MARK: - Track

/// The vertical track of stop nodes for the Live Trip screen: a line down the
/// left edge with one node per scheduled stop, the bus marker on the current
/// stop, and a delay pill in the header area. Extracted as a struct taking
/// only the data it needs so SwiftUI can skip re-rendering it when unrelated
/// parent state changes.
private struct TripTrack: View {

    let route: RouteDetails
    let stops: [TripStop]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DelayPill(delayMinutes: route.delayMinutes)
                    .padding(.horizontal, 18)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                TripNodes(route: route, stops: stops)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
            }
        }
    }
}

/// The optional "Delayed 3 min" pill shown at the top of the track, matching
/// the storyboard's `trip-header .eta`. Hidden when on time or no realtime data.
private struct DelayPill: View {

    let delayMinutes: Int?

    var body: some View {
        if let delayMinutes {
            Text(Self.label(delayMinutes))
                .font(.caption.weight(.bold))
                .foregroundStyle(.red)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.15), in: Capsule())
        }
    }

    /// "Delayed 3 min" for a positive delay, "Early 2 min" for a negative one.
    static func label(_ minutes: Int) -> String {
        if minutes >= 0 {
            return "Delayed \(minutes) min"
        } else {
            return "Early \(-minutes) min"
        }
    }
}

// MARK: - Stop nodes

/// The list of stop nodes joined by a vertical line, with the bus marker on
/// the current stop. Extracted as a struct so each node's passed/current state
/// is computed once from the schedule.
private struct TripNodes: View {

    let route: RouteDetails
    let stops: [TripStop]

    private var currentIndex: Int? { stops.currentStopIndex() }

    var body: some View {
        ZStack(alignment: .topLeading) {
            line
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                    StopNode(
                        stop: stop,
                        isPassed: stops.isPassed(at: index),
                        isCurrent: index == currentIndex,
                        isFinal: index == stops.count - 1
                    )
                    if index == currentIndex {
                        TransportModeMarker(mode: route.transportMode)
                    }
                }
            }
        }
    }

    /// The vertical connector running through every node's dot, matching the
    /// storyboard's `track-line`. Inset top/bottom so it doesn't run past the
    /// first/last node.
    private var line: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 3)
            .padding(.leading, 4)
            .padding(.top, 16)
            .padding(.bottom, 16)
    }
}

/// The transport mode marker shown at the current stop, matching the storyboard's
/// `bus-marker` • a small square with the mode icon, sitting on the line with
/// spacing above and below.
private struct TransportModeMarker: View {

    let mode: TransportMode?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 20)
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.accentColor)
                .frame(width: 26, height: 26)
                .overlay(
                    Group {
                        if let mode {
                            Image(systemName: mode.icon)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                )
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.background, lineWidth: 3))
                .offset(x: -7)
                .accessibilityLabel("Vehicle is here")
            Spacer(minLength: 20)
        }
    }
}

/// One `stop-node` from the storyboard: a dot on the line, the stop name, and
/// an optional subtitle. Passed nodes fade; the current node carries the bus
/// marker and an "in X min" subtitle.
private struct StopNode: View {

    let stop: TripStop
    let isPassed: Bool
    let isCurrent: Bool
    let isFinal: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            nodeDot
            VStack(alignment: .leading, spacing: 1) {
                Text(stop.name ?? "")
                    .font(.subheadline.weight(isPassed ? .regular : .semibold))
                    .foregroundStyle(isPassed ? .secondary : .primary)
                    .strikethrough(stop.canceled == true)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 58)
    }

    /// The node's dot: a filled grey dot for passed stops, a larger ringed
    /// magenta dot with a glow for the current stop, and a plain outlined dot
    /// for upcoming stops • matching the storyboard's `stop-node` states.
    private var nodeDot: some View {
        Circle()
            .fill(isPassed ? Color.secondary.opacity(0.3) : Color.secondary)
            .overlay(
                Circle()
                    .strokeBorder(
                        isCurrent ? Color.accentColor : Color.secondary.opacity(0.5),
                        lineWidth: isCurrent ? 3 : 3
                    )
            )
            .frame(width: isCurrent ? 15 : 11, height: isCurrent ? 15 : 11)
            .shadow(
                color: isCurrent ? Color.accentColor.opacity(0.35) : .clear,
                radius: isCurrent ? 5 : 0
            )
    }

    /// The subtitle text for a node: the final stop shows "Final stop"; the
    /// current stop shows "Arriving in X min"; cancelled stops show "Cancelled".
    private var subtitle: String? {
        if stop.canceled == true {
            return "Cancelled"
        }
        if isFinal {
            return "Final stop"
        }
        if isCurrent, let minutes = Self.minutesUntil(stop) {
            return minutes <= 0 ? "Departing now" : "Arriving in \(minutes) min"
        }
        return nil
    }

    /// Whole minutes until the stop's departure from now, or `nil` when the
    /// time can't be parsed.
    static func minutesUntil(_ stop: TripStop) -> Int? {
        guard let date = stop.date else { return nil }
        let minutes = Calendar.current.dateComponents([.minute], from: Date(), to: date).minute
        return minutes
    }
}

#Preview("Live trip") {
    NavigationStack {
        RouteDetailsView(
            route: RouteDetails(
                tripId: "900001",
                startDate: "2099-01-01",
                lineLabel: "3",
                direction: "Karolinska sjukhuset",
                delayMinutes: 0,
                transportMode: "BUS"
            )
        )
    }
    .environment(\.network, MockTrafiklabService())
}

#Preview("Delayed") {
    NavigationStack {
        RouteDetailsView(
            route: RouteDetails(
                tripId: "900002",
                startDate: "2099-01-01",
                lineLabel: "7",
                direction: "Ropsten",
                delayMinutes: 3,
                transportMode: "TRAM"
            )
        )
    }
    .environment(\.network, MockTrafiklabService())
}
