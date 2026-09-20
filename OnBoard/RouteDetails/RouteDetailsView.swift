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
                        .foregroundStyle(.ink)
                } description: {
                    Text(failure)
                        .foregroundStyle(.inkSoft)
                }
            } else if model.calls.isEmpty {
                if model.isLoading {
                    ProgressView()
                        .tint(.accent)
                } else {
                    ContentUnavailableView(
                        "No stops",
                        systemImage: "tray",
                        description: Text("This trip has no scheduled stops.")
                    )
                    .foregroundStyle(.ink, .inkSoft)
                }
            } else {
                TripTrack(
                    route: route,
                    calls: model.calls
                )
            }
        }
        .navigationTitle(Self.title(route))
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.paper)
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
/// left edge with one node per scheduled stop, the bus marker on the stop the
/// vehicle is at or heading to, and the delay pill on that stop's row.
/// Extracted as a struct taking only the data it needs so SwiftUI can skip
/// re-rendering it when unrelated parent state changes.
private struct TripTrack: View {

    let route: RouteDetails
    let calls: [TripCall]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TripNodes(
                        route: route,
                        rows: calls.stopRows(now: Date())
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }
            .onAppear {
                scrollToTarget(from: proxy)
            }
        }
    }

    /// Scrolls the track so the stop the vehicle is at or heading to — the row
    /// carrying the bus marker — sits in the middle of the screen, jumping
    /// straight to the vehicle when the view opens.
    private func scrollToTarget(from proxy: ScrollViewProxy) {
        guard let target = calls.currentStopIndex()?.targetIndex, calls.indices.contains(target) else { return }
        proxy.scrollTo(calls[target].id, anchor: .center)
    }
}

/// The optional "Delayed 3 min" pill, shown trailing the stop the vehicle
/// is at or heading to. Hidden when on time or no realtime data.
private struct DelayPill: View {

    let delayMinutes: DelayTime?

    var body: some View {
        if let delayMinutes {
            Text(delayMinutes.label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(delayMinutes.minutes < 0 ? .statusGreen : .statusRed)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    delayMinutes.minutes < 0 ? Color.statusGreenTint : Color.statusRedTint,
                    in: Capsule()
                )
        }
    }
}

// MARK: - Stop nodes

/// Half of a row's minimum height: the distance from a row's edge to its
/// node's center, used both to inset the connector at the track's ends and to
/// lift the bus marker to the row boundary while the vehicle is between
/// stops.
private let rowHalfHeight: CGFloat = 31

/// The list of stop nodes joined by a vertical line, with the bus marker on
/// the stop the vehicle is at or heading to. Takes precomputed ``TripStopRow``
/// snapshots so no row compares indices or re-derives the vehicle's position;
/// each row draws the connector to the next node, so the track ends exactly at
/// the first and last markers instead of dangling past them.
private struct TripNodes: View {

    let route: RouteDetails
    let rows: [TripStopRow]

    @Namespace private var markerSpace

    /// The identity shared by the marker wherever it appears, so SwiftUI
    /// animates it moving from one row to the next rather than fading out
    /// and back in.
    private static let markerID = "vehicleMarker"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                StopNode(row: row)
                    .overlay(alignment: .trailing) {
                        if row.isTarget {
                            DelayPill(delayMinutes: route.delayMinutes)
                                .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .leading) {
                        if row.isTarget {
                            TransportModeMarker(mode: route.transportMode)
                                .matchedGeometryEffect(id: Self.markerID, in: markerSpace)
                                .transition(.opacity)
                                .offset(y: row.isBetweenStops ? -rowHalfHeight : 0)
                        }
                    }
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: rows)
    }
}

/// The transport mode marker shown at the stop the vehicle is at or heading
/// to, matching the storyboard's `bus-marker` • a small square with the mode
/// icon, sitting on the line over the node. It is part of the target row and
/// matched by geometry across rows, so SwiftUI animates it sliding along the
/// track as the journey progresses.
private struct TransportModeMarker: View {

    let mode: TransportMode?

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Color.accent)
            .frame(width: 28, height: 28)
            .overlay(
                Group {
                    if let mode {
                        Image(systemName: mode.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            )
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.panel, lineWidth: 3))
            .offset(x: -7)
            .accessibilityLabel("Vehicle is here")
    }
}

/// One `stop-node` from the storyboard: a dot on the line, the stop name, and
/// an optional subtitle. Renders straight from a precomputed ``TripStopRow``;
/// passed rows fade, the target row carries the bus marker, the first row
/// wears a hollow origin ring and the last a filled terminus disc. Each row
/// also draws its slice of the connector, inset so the track runs exactly
/// from the first node's center to the last node's center.
private struct StopNode: View {

    let row: TripStopRow

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            nodeMarker
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.body.weight(row.isPassed ? .regular : .semibold))
                    .foregroundStyle(row.isPassed ? .inkSoft : .ink)
                    .strikethrough(row.isCanceled)
                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 62)
        .background(alignment: .topLeading) { connector }
    }

    /// The stop's graphic on the track: the hollow origin ring on the first
    /// stop, the filled terminus disc on the last, and the storyboard's dot
    /// states in between.
    private var nodeMarker: some View {
        if row.isFinal {
            TerminusDisc(isPassed: row.isPassed)
        } else if row.isFirst {
            OriginRing(isPassed: row.isPassed, isCurrent: row.isCurrent)
        } else {
            StopDot(isPassed: row.isPassed, isCurrent: row.isCurrent)
        }
    }

    /// This row's slice of the track's vertical connector, matching the
    /// storyboard's `track-line`. It spans the full row so consecutive rows'
    /// slices join up, but is inset at the track's ends so the line starts
    /// and stops exactly at the first and last node's centers — a one-stop
    /// trip draws no line at all.
    private var connector: some View {
        Group {
            if row.isFirst && row.isFinal {
                EmptyView()
            } else {
                Capsule()
                    .fill(Color.hairline)
                    .frame(width: 3)
                    .padding(.leading, 4)
                    .padding(.top, row.isFirst ? rowHalfHeight : 0)
                    .padding(.bottom, row.isFinal ? rowHalfHeight : 0)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Node dots

/// The dot for an intermediate stop: a filled grey dot when passed, a larger
/// ringed magenta dot with a glow when the vehicle is standing there, and a
/// plain outlined dot when upcoming — matching the storyboard's `stop-node`
/// states.
private struct StopDot: View {

    let isPassed: Bool
    let isCurrent: Bool

    var body: some View {
        Circle()
            .fill(isPassed ? Color.hairline : Color.panel)
            .overlay(
                Circle()
                    .strokeBorder(
                        isCurrent ? Color.accent : Color.hairline,
                        lineWidth: 3
                    )
            )
            .frame(width: isCurrent ? 17 : 12, height: isCurrent ? 17 : 12)
            .shadow(
                color: isCurrent ? Color.accentTint : .clear,
                radius: isCurrent ? 5 : 0
            )
    }
}

/// A hollow ring marking the journey's first stop, so the origin reads
/// differently from the intermediate dots along the line.
private struct OriginRing: View {

    let isPassed: Bool
    let isCurrent: Bool

    var body: some View {
        Circle()
            .fill(Color.panel)
            .overlay(
                Circle()
                    .strokeBorder(isPassed ? Color.hairline : Color.accent, lineWidth: 3)
            )
            .frame(width: isCurrent ? 17 : 16, height: isCurrent ? 17 : 16)
            .accessibilityLabel("First stop")
    }
}

/// A filled disc in a hollow square ring marking the journey's final stop, a
/// clear terminus that caps the track and mirrors the "Final stop" subtitle.
private struct TerminusDisc: View {

    let isPassed: Bool

    var body: some View {
        Circle()
            .fill(isPassed ? Color.hairline : Color.accent)
            .frame(width: 16, height: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isPassed ? Color.hairline : Color.accent, lineWidth: 3)
                    .padding(-5)
            )
            .accessibilityLabel("Final stop")
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
                delayMinutes: DelayTime(seconds: 0),
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
                delayMinutes: DelayTime(seconds: 180),
                transportMode: "TRAM"
            )
        )
    }
    .environment(\.network, MockTrafiklabService())
}
