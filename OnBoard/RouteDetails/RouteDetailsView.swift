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
        TimelineView(.periodic(byMinute: 1)) { context in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TripNodes(route: route, calls: calls, now: context.date)
                            .padding(.horizontal, 18)
                            .padding(.bottom, 24)
                    }
                }
                .onChange(
                    of: calls.currentStopIndex(now: context.date)?.targetIndex,
                    initial: true
                ) { oldIndex, newIndex in
                    scrollTo(newIndex, from: proxy, animated: oldIndex != nil)
                }
            }
        }
    }

    /// Scrolls the track so the stop the vehicle is at or heading to sits in
    /// the middle of the screen: un-animated when the position first becomes
    /// known (opening the view mid-journey jumps straight to the vehicle),
    /// animated afterwards so the view follows the vehicle as it moves to the
    /// next part of the journey.
    private func scrollTo(_ index: Int?, from proxy: ScrollViewProxy, animated: Bool) {
        guard let index, calls.indices.contains(index) else { return }
        if animated {
            withAnimation {
                proxy.scrollTo(calls[index].id, anchor: .center)
            }
        } else {
            proxy.scrollTo(calls[index].id, anchor: .center)
        }
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

/// The list of stop nodes joined by a vertical line, with the bus marker on
/// the stop the vehicle is at or heading to. Extracted as a struct so each
/// node's passed/current state is computed once from the schedule.
private struct TripNodes: View {

    let route: RouteDetails
    let calls: [TripCall]
    let now: Date

    @State private var markerOffset: CGFloat?

    private var currentPosition: TransportPosition? { calls.currentStopIndex(now: now) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            line
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(calls.enumerated()), id: \.element.id) { index, call in
                    StopNode(
                        call: call,
                        isPassed: calls.isPassed(at: index, now: now),
                        isCurrent: isCurrent(index),
                        isFirst: index == 0,
                        isFinal: index == calls.count - 1,
                        now: now
                    )
                    .overlay(alignment: .trailing) {
                        if isTarget(index) {
                            DelayPill(delayMinutes: route.delayMinutes)
                                .transition(.opacity)
                        }
                    }
                    .background(MarkerAnchor(isActive: isTarget(index)))
                }
            }
            if let markerOffset {
                TransportModeMarker(mode: route.transportMode)
                    .offset(y: markerOffset - 14)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: currentPosition)
        .coordinateSpace(name: "TripTrack")
        .onPreferenceChange(MarkerOffsetKey.self) { offset in
            guard let offset else {
                markerOffset = nil
                return
            }
            if markerOffset == offset { return }
            if markerOffset == nil {
                markerOffset = offset
            } else {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) {
                    markerOffset = offset
                }
            }
        }
    }

    /// Whether this row is the stop the vehicle is at or heading to next — the
    /// row the bus marker sits on and the delay pill trails.
    private func isTarget(_ index: Int) -> Bool {
        currentPosition?.targetIndex == index
    }

    /// Whether this row is the stop the vehicle is standing at right now, as
    /// opposed to one it is merely heading to (``isTarget``).
    private func isCurrent(_ index: Int) -> Bool {
        if case .atStop(let currentIndex) = currentPosition {
            return index == currentIndex
        }
        return false
    }

    /// The vertical connector running through every node's dot, matching the
    /// storyboard's `track-line`. Inset top/bottom so it doesn't run past the
    /// first/last node.
    private var line: some View {
        Capsule()
            .fill(Color.hairline)
            .frame(width: 3)
            .padding(.leading, 4)
            .padding(.top, 16)
            .padding(.bottom, 16)
    }
}

/// The transport mode marker shown at the current stop, matching the storyboard's
/// `bus-marker` • a small square with the mode icon, sitting on the line over
/// the node. Rendered once for the whole track (not as an overlay on every
/// node) and offset to the stop the vehicle is at or heading to, so a single
/// marker animates sliding along the track as the journey progresses.
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

/// The vertical midpoint of the node the vehicle is at or heading to, measured
/// in the track's coordinate space, reported by ``MarkerAnchor`` so the marker
/// can sit on that node.
private struct MarkerOffsetKey: PreferenceKey {

    static var defaultValue: CGFloat? = nil

    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

/// A clear background reporting the vertical midpoint of the node it is
/// attached to via ``MarkerOffsetKey``; inactive on every node but the one
/// the marker targets.
private struct MarkerAnchor: View {

    let isActive: Bool

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: MarkerOffsetKey.self,
                value: isActive ? proxy.frame(in: .named("TripTrack")).midY : nil
            )
        }
    }
}

/// One `stop-node` from the storyboard: a dot on the line, the stop name, and
/// an optional subtitle. Passed nodes fade; the current node carries the bus
/// marker and an "in X min" subtitle; the first node wears a hollow origin
/// ring and the last a flag pin, making the journey's extent readable at a
/// glance.
private struct StopNode: View {

    let call: TripCall
    let isPassed: Bool
    let isCurrent: Bool
    let isFirst: Bool
    let isFinal: Bool
    let now: Date

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if isFinal {
                TerminusFlag(isPassed: isPassed)
            } else if isFirst {
                OriginRing(isPassed: isPassed, isCurrent: isCurrent)
            } else {
                StopDot(isPassed: isPassed, isCurrent: isCurrent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(call.stop?.name ?? "")
                    .font(.body.weight(isPassed ? .regular : .semibold))
                    .foregroundStyle(isPassed ? .inkSoft : .ink)
                    .strikethrough(call.isCanceled)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.inkSoft)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 62)
    }

    /// The subtitle text for a node: the final stop shows "Final stop"; the
    /// current stop shows "Arriving in X min"; cancelled calls show "Cancelled".
    private var subtitle: String? {
        if call.isCanceled {
            return "Cancelled"
        }
        if isFinal {
            return "Final stop"
        }
        if isCurrent, let minutes = Self.minutesUntil(call, now: now) {
            return minutes <= 0 ? "Departing now" : "Arriving in \(minutes) min"
        }
        return nil
    }

    /// Whole minutes until the call's departure from `now`, or `nil` when the
    /// time can't be parsed.
    static func minutesUntil(_ call: TripCall, now: Date) -> Int? {
        guard let date = call.date else { return nil }
        let minutes = Calendar.current.dateComponents([.minute], from: now, to: date).minute
        return minutes
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

/// A hollow double ring marking the journey's first stop, so the origin reads
/// differently from the intermediate dots along the line.
private struct OriginRing: View {

    let isPassed: Bool
    let isCurrent: Bool

    var body: some View {
        Circle()
            .fill(isPassed ? Color.hairline : Color.panel)
            .overlay(
                Circle()
                    .strokeBorder(isPassed ? Color.hairline : Color.accent, lineWidth: 3)
            )
            .overlay(
                Circle()
                    .strokeBorder(isPassed ? Color.hairline : Color.accent, lineWidth: 3)
                    .padding(5)
            )
            .frame(width: isCurrent ? 17 : 16, height: isCurrent ? 17 : 16)
            .offset(x: -2)
            .accessibilityLabel("First stop")
    }
}

/// A filled flag pin marking the journey's final stop, mirroring the
/// "Final stop" subtitle on the row.
private struct TerminusFlag: View {

    let isPassed: Bool

    var body: some View {
        Image(systemName: "flag.fill")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(isPassed ? Color.hairline : Color.accent)
            .frame(width: 28, height: 28)
            .offset(x: -3)
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
