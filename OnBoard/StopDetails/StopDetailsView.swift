import SwiftUI

/// The Stop board screen ("Step 2 \u2014 Tap a stop \u2192 live departure board" in
/// `Designs/storyboard.html`).
///
/// Shows a dark header with the stop name and an "updated just now" meta line,
/// followed by a list of realtime departures. Each row matches the storyboard's
/// `dep-row`: a filled line badge with a transport-mode blip, a destination plus
/// an optional delay/cancelled status pill, and a right-aligned minute countdown.
///
/// The view is driven by ``StopDetailsModel`` and reads its network dependency
/// from the SwiftUI environment, mirroring ``NearbyView``.
struct StopDetailsView: View {

    /// The group id of the stop to display, fed to `Trafiklab.departures`.
    let stopId: String

    /// The stop name shown in the header.
    let stopName: String

    @Environment(\.network) private var network

    @State private var model = StopDetailsModel()

    var body: some View {
        Group {
            if let failure = model.failure {
                ContentUnavailableView {
                    Label("Couldn't load departures", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(failure)
                }
            } else if model.departures.isEmpty {
                if model.isLoading {
                    ProgressView()
                } else {
                    ContentUnavailableView(
                        "No departures",
                        systemImage: "tray",
                        description: Text("There are no departures in the next hour.")
                    )
                }
            } else {
                departuresList
            }
        }
        .navigationTitle(stopName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.loadDepartures(network: network, areaId: stopId)
        }
    }

    private var departuresList: some View {
        List {
            ForEach(model.departures) { departure in
                DepartureRow(departure: departure)
                    .listRowSeparator(.visible)
                    .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - Departure row

/// One `dep-row` from the storyboard: line badge with a mode blip, destination
/// plus an optional status pill, and a right-aligned countdown.
private struct DepartureRow: View {

    let departure: CallAtLocation

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            LineBadge(departure: departure)
            VStack(alignment: .leading, spacing: 6) {
                Text(StopDetailsModel.destination(for: departure))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                statusPill
            }
            Spacer(minLength: 8)
            countdown
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statusPill: some View {
        if departure.canceled == true {
            Text("Cancelled")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.15), in: Capsule())
        } else if let delay = StopDetailsModel.delayMinutes(for: departure) {
            Text(delayLabel(delay))
                .font(.caption2.weight(.bold))
                .foregroundStyle(delay < 0 ? .green : .orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    Color(delay < 0 ? .green : .orange).opacity(0.15),
                    in: Capsule()
                )
        }
    }

    @ViewBuilder
    private var countdown: some View {
        if departure.canceled == true {
            Text("Cancelled")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .strikethrough()
        } else {
            Text(countdownText)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .trailing)
        }
    }

    /// "2 min" when near, otherwise the wall-clock time HH:mm. Falls back to
    /// the raw scheduled string when no time can be parsed.
    private var countdownText: String {
        let minutes = StopDetailsModel.minutesUntil(
            departure: departure,
            now: Date(),
            timeZone: StopDetailsView.timeZone
        )
        if let minutes, minutes >= 0, minutes < 60 {
            return minutes == 0 ? "Now" : "\(minutes) min"
        }
        if let date = StopDetailsModel.date(
            from: departure.realtime ?? departure.scheduled,
            timeZone: StopDetailsView.timeZone
        ) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return departure.scheduled
    }

    /// Formats a signed delay value as "+3 min" / "-2 min".
    private func delayLabel(_ minutes: Int) -> String {
        let sign = minutes >= 0 ? "+" : ""
        return "\(sign)\(minutes) min"
    }
}

// MARK: - Line badge

/// The filled, rounded line number badge with a small transport-mode "blip"
/// in the corner, matching the storyboard's `line-badge` + `mode-blip`.
private struct LineBadge: View {

    let departure: CallAtLocation

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(StopDetailsModel.lineLabel(for: departure))
                .font(.callout.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 42, minHeight: 40)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 11))
            modeBlip
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var modeBlip: some View {
        if let mode = departure.route?.transport_mode {
            Image(systemName: Self.modeIcon(for: mode))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.primary)
                .padding(2)
                .frame(width: 19, height: 19)
                .background(.background, in: Circle())
                .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                .offset(x: 5, y: 5)
        }
    }

    private var accessibilityLabel: String {
        let line = StopDetailsModel.lineLabel(for: departure)
        let dest = StopDetailsModel.destination(for: departure)
        return [line, dest].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Maps a Trafiklab `transport_mode` to a SF Symbol, matching the icons in
    /// the storyboard (`BUS`/`TRAM`/`METRO`/`TRAIN`/`BOAT`/`TAXI`).
    static func modeIcon(for mode: String) -> String {
        switch mode.uppercased() {
        case "BUS":
            return "bus.fill"
        case "TRAM":
            return "tram.fill"
        case "METRO":
            return "tram.fill"
        case "TRAIN":
            return "train.side.front.car"
        case "BOAT":
            return "ferry.fill"
        case "TAXI":
            return "car.fill"
        default:
            return "questionmark"
        }
    }
}

// MARK: - Helpers

extension StopDetailsView {

    /// The time zone used to interpret and display departure times.
    fileprivate static var timeZone: TimeZone { .current }
}

#Preview("Departures") {
    NavigationStack {
        StopDetailsView(
            stopId: "740000001",
            stopName: "Medborgarplatsen"
        )
    }
    .environment(\.network, MockNetwork())
}
