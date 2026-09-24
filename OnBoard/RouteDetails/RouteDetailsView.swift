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

    @Environment(LineColoursModel.self) private var lineColours

    @Environment(TripFavoritesModel.self) private var tripFavoritesModel

    @State private var model = RouteDetailsModel()

    @State private var loadingTrigger = 0

    /// How often the rows are recomputed from the loaded schedule so the
    /// marker's position and the countdown subtitles track the clock between
    /// network polls. Trafiklab only refreshes its realtime data every 60 s,
    /// so recomputing every second keeps the marker moving smoothly along the
    /// leg between two stops.
    private static let rowRefreshInterval = 1.0

    var body: some View {
        Group {
            if let failure = model.failure {
                UnavailableScreen(
                    title: "Couldn't load the trip",
                    systemImage: "wifi.exclamationmark",
                    message: failure
                )
            } else if model.calls.isEmpty {
                if model.isLoading {
                    LoadingIndicator()
                } else {
                    UnavailableScreen(
                        title: "No stops",
                        systemImage: "tray",
                        message: "This trip has no scheduled stops."
                    )
                }
            } else {
                TimelineView(.periodic(from: .now, by: Self.rowRefreshInterval)) { context in
                    TripTrack(
                        route: route,
                        rows: model.rows,
                        lineColour: lineColours.badgeColour(
                            designation: route.lineLabel,
                            transportMode: route.transportMode
                        )
                    )
                    .onChange(of: context.date) {
                        model.recalculateRows(now: context.date)
                    }
                }
            }
        }
        .navigationTitle(route.lineTitle)
        .navigationBarTitleDisplayMode(.inline)
        .background(Color.paper)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                TripFavoriteToggle(route: route, model: tripFavoritesModel)
            }
        }
        .task(id: loadingTrigger) {
            await model.loadTrip(
                network: network,
                tripId: route.tripId,
                startDate: route.startDate
            )
            // Trafiklab's realtime data only updates every 60 s, so poll on
            // that cadence; the rows between polls are refreshed by the
            // track's TimelineView instead.
            try? await Task.sleep(for: .seconds(60))
            loadingTrigger += 1
        }
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
    let rows: [TripStopRow]

    /// The line's design-token colour, looked up from the shared
    /// ``LineColoursModel`` by the owning view, so the deep child rendering
    /// the vehicle marker doesn't read the environment itself.
    let lineColour: Color

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TripNodes(
                        route: route,
                        rows: rows,
                        lineColour: lineColour
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 24)
                }
            }
            .onAppear {
                /// Scrolls the track so the stop the vehicle is at or heading to — the row
                /// carrying the bus marker — sits in the middle of the screen, jumping
                /// straight to the vehicle when the view opens. Reads the target off the
                /// model's row snapshot, so the scroll and the marker can never disagree.
                guard let target = rows.target else { return }
                proxy.scrollTo(target.id, anchor: .center)
            }
        }
    }
}

// MARK: - Stop nodes

/// The x position of the track's line center, measured from a row's leading
/// edge: the connector is 3 pt wide inset 4.5 pt, and every node marker and
/// the bus marker offset themselves so their centers sit exactly on it.
private let trackCenterX: CGFloat = 6

/// A row's height. A node sits at the vertical center of its row, and every
/// row is the same height so the spacing between the stations' nodes never
/// drifts as the vehicle moves along the track.
private let stopRowHeight: CGFloat = 72

/// The share of the inter-station distance the marker skips at each end of
/// a leg: it leaves the node directly to the 10%-of-the-way mark and pulls up
/// at the 90% mark, so the time spent moving between the stations stays
/// real-time — only the ends are instantaneous, covered by the spring
/// animation as the at-stop position hands over to the travelling one.
private let markerEaseFraction: Double = 0.1

/// Maps a leg's raw 0→1 timeline onto the marker's position along the
/// inter-station distance: a linear 5%→95% of the way, per
/// ``markerEaseFraction`` — the marker never sits on the nodes while
/// travelling, and the at-stop position on either side supplies the bump.
private func travelPosition(_ progress: Double) -> Double {
    markerEaseFraction + progress * (1 - 2 * markerEaseFraction)
}

/// The list of stop nodes joined by a vertical line, with the bus marker on
/// the stop the vehicle is at or heading to. Takes precomputed ``TripStopRow``
/// snapshots so no row compares indices or re-derives the vehicle's position;
/// the track's single connector line runs behind the stack, from the first
/// node's center to the last marker's.
private struct TripNodes: View {

    let route: RouteDetails
    let rows: [TripStopRow]

    /// The line's design-token colour, threaded down from ``TripTrack`` for
    /// the bus marker's fill.
    let lineColour: Color

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
                        if row.isTarget, let delayMinutes = route.delayMinutes {
                            StatusPill(
                                label: delayMinutes.label,
                                tone: delayMinutes.minutes < 0 ? .green : .red
                            )
                            .transition(.opacity)
                        }
                    }
                    .overlay(alignment: .leading) {
                        if row.isCarryingMarker {
                            TransportModeMarker(
                                mode: route.transportMode,
                                colour: lineColour,
                                isRealtime: row.isRealtime
                            )
                                .matchedGeometryEffect(id: Self.markerID, in: markerSpace)
                                .transition(.identity)
                                .offset(y: markerOffset(for: row))
                        }
                    }
            }
        }
        .background(alignment: .topLeading) {
            /// The track's vertical connector, drawn once behind every row
            /// instead of as per-row slices: a slice living in a row's
            /// background is part of that row's subtree, so a marker riding
            /// the row above sinks below the next row's slice when it crosses
            /// the midpoint. Behind the whole stack the line stays under the
            /// marker everywhere along it. Inset half a row at each end so it
            /// runs exactly from the first node's center to the last's — a
            /// one-stop trip draws no line at all.
            if rows.count > 1 {
                Rectangle()
                    .fill(Color.hairline)
                    .frame(width: 3)
                    .padding(.leading, 4.5)
                    .padding(.top, stopRowHeight / 2)
                    .padding(.bottom, stopRowHeight / 2)
                    .frame(maxHeight: .infinity)
            }
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: rows)
    }

    /// The marker's vertical offset within the row it currently rides: resting
    /// on the node while the vehicle is at the stop, and travelling from the
    /// 5% mark to the 95% mark of the inter-station distance while between
    /// stops — real-time along the leg, with the spring animation covering
    /// the instantaneous ends. The row the marker rides switches at the leg's
    /// midpoint (see the model's `markerRow`), and both rows' formulas agree
    /// at the boundary they share, so the handoff is seamless.
    private func markerOffset(for row: TripStopRow) -> CGFloat {
        guard let progress = row.travelProgress else { return 0 }
        let position = travelPosition(progress)
        return row.isTarget
            ? position * stopRowHeight - stopRowHeight
            : position * stopRowHeight
    }
}

/// The transport mode marker shown at the stop the vehicle is at or heading
/// to, matching the storyboard's `bus-marker` • a small square with the mode
/// icon, sitting on the line over the node. It is part of the target row and
/// matched by geometry across rows, so SwiftUI animates it sliding along the
/// track as the journey progresses. When the trip carries no realtime data a
/// small crossed-out-wifi badge sits on the marker's top-right corner, so the
/// rider can see the position is driven by the schedule alone.
private struct TransportModeMarker: View {

    let mode: TransportMode?

    /// The line's badge colour, so the vehicle marker wears the same colour
    /// as the line badge the rider tapped on the stop board.
    let colour: Color

    /// Whether the trip carries realtime data; when false the marker wears
    /// the disconnected badge.
    let isRealtime: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(colour)
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
            .overlay(alignment: .topTrailing) {
                if !isRealtime {
                    DisconnectedBadge()
                }
            }
            .offset(x: trackCenterX - 14)
            .accessibilityLabel("Vehicle is here")
    }
}

/// The small badge on the bus marker's top-right corner when the trip has no
/// realtime data: a paper disc with a crossed-out wifi glyph in the hairline
/// grey, sized to read as an overlay without hiding the mode icon.
private struct DisconnectedBadge: View {

    var body: some View {
        Circle()
            .fill(Color.paper)
            .frame(width: 14, height: 14)
            .overlay(
                Image(systemName: "wifi.slash")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.inkSoft)
            )
            .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
            .offset(x: 5, y: -5)
            .accessibilityLabel("Not realtime")
    }
}

/// One `stop-node` from the storyboard: a dot on the line, the stop name, and
/// an optional subtitle. Renders straight from a precomputed ``TripStopRow``;
/// passed rows fade, the target row carries the bus marker, the first row
/// wears a hollow origin ring and the last a filled terminus disc. The track's
/// connector line is drawn by ``TripNodes`` behind the stack, so it always
/// sits under the bus marker.
private struct StopNode: View {

    let row: TripStopRow

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            /// The stop's graphic on the track: the hollow origin ring on the first
            /// stop, the filled terminus disc on the last, and the storyboard's dot
            /// states in between. Every marker is offset so its center sits exactly
            /// on the track's line.
            if row.isFinal {
                TerminusDisc(isPassed: row.isPassed)
            } else if row.isFirst {
                OriginRing(isPassed: row.isPassed, isCurrent: row.isCurrent)
            } else {
                StopDot(isPassed: row.isPassed, isCurrent: row.isCurrent)
            }

            // Route name and optional subtitle.
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
            if let trailingTime = row.trailingTime {
                Text(trailingTime)
                    .font(.subheadline)
                    .foregroundStyle(.inkSoft)
            }
        }
        .frame(minHeight: stopRowHeight)
    }
}

// MARK: - Saved-trip toggle

/// The toolbar star on the Live Trip screen that saves/removes the current
/// journey to the Trips tab, mirroring the Stop board's ``FavoriteToggle``:
/// the filled state reflects the shared ``TripFavoritesModel``, and the line
/// label, direction, and transport mode are captured at save time so the
/// saved row renders without a network round trip.
private struct TripFavoriteToggle: View {

    @Environment(\.modelContext) var modelContext

    let route: RouteDetails
    let model: TripFavoritesModel

    var body: some View {
        Button {
            model.toggle(route, context: modelContext)
        } label: {
            Image(systemName: model.contains(route) ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(model.contains(route) ? .star : .inkSoft)
                .accessibilityLabel(model.contains(route) ? "Remove saved trip" : "Save trip")
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
            .offset(x: trackCenterX - (isCurrent ? 17.0 : 12.0) / 2)
    }
}

/// A hollow ring in a supporting color marking the journey's first stop, so
/// the origin reads differently from the intermediate dots along the line.
private struct OriginRing: View {

    let isPassed: Bool
    let isCurrent: Bool

    var body: some View {
        Circle()
            .fill(Color.panel)
            .overlay(
                Circle()
                    .strokeBorder(isPassed ? Color.hairline : Color.inkSoft, lineWidth: 3)
            )
            .frame(width: isCurrent ? 17 : 16, height: isCurrent ? 17 : 16)
            .offset(x: trackCenterX - (isCurrent ? 17.0 : 16.0) / 2)
            .accessibilityLabel("First stop")
    }
}

/// A filled disc in a hollow square ring marking the journey's final stop, a
/// clear terminus that caps the track and mirrors the "Final stop" subtitle.
private struct TerminusDisc: View {

    let isPassed: Bool

    var body: some View {
        Circle()
            .fill(isPassed ? Color.hairline : Color.accentDeep)
            .frame(width: 16, height: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(isPassed ? Color.hairline : Color.accentDeep, lineWidth: 3)
                    .padding(-5)
            )
            .offset(x: trackCenterX - 8)
            .accessibilityLabel("Final stop")
    }
}

#Preview("Live trip") {
    @Previewable @State var tripFavoritesModel = TripFavoritesModel()
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
    .environment(previewLineColours())
    .environment(tripFavoritesModel)
    .modelContainer(emptyModelContainer())
}

#Preview("Delayed") {
    @Previewable @State var tripFavoritesModel = TripFavoritesModel()
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
    .environment(previewLineColours())
    .environment(tripFavoritesModel)
    .modelContainer(emptyModelContainer())
}
