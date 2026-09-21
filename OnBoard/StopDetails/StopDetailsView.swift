import SwiftUI
import SwiftData

/// The Stop board screen ("Step 2 → Tap a stop → live departure board" in
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

    @Environment(FavoritesModel.self) private var favoritesModel

    @State private var model = StopDetailsModel()

    /// Bumped after each poll cycle so `.task(id:)` restarts the loop and the
    /// screen keeps refreshing while it is on screen; the task (and therefore
    /// the polling) is cancelled when the view disappears. Mirrors
    /// ``RouteDetailsView``'s refresh trigger.
    @State private var refreshTrigger = 0

    var body: some View {
        Group {
            if let failure = model.failure {
                ContentUnavailableView {
                    Label("Couldn't load departures", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(.ink)
                } description: {
                    Text(failure)
                        .foregroundStyle(.inkSoft)
                }
            } else if model.departures.isEmpty {
                if model.isLoading {
                    ProgressView()
                        .tint(.accent)
                } else {
                    ContentUnavailableView(
                        "No departures",
                        systemImage: "tray",
                        description: Text("There are no departures in the next hour.")
                    )
                    .foregroundStyle(.ink, .inkSoft)
                }
            } else {
                DeparturesList(departures: model.departures)
            }
        }
        .background(Color.paper)
        .navigationSubtitle(model.lastUpdatedText)
        .navigationTitle(stopName)
        .navigationDestination(for: RouteDetails.self) { route in
            RouteDetailsView(route: route)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FavoriteToggle(
                    stopId: stopId,
                    stopName: stopName,
                    departures: model.departures,
                    model: favoritesModel
                )
            }
        }
        .task(id: refreshTrigger) {
            await model.loadDepartures(network: network, areaId: stopId)
            // Refresh every 60 seconds
            try? await Task.sleep(for: .seconds(60))
            refreshTrigger += 1
        }
    }
}

// MARK: - Departures list

/// The plain list of departure rows for the Stop board. A departure with a
/// `trip` reference is tappable and pushes the Live Trip screen
/// (``RouteDetailsView``); a departure without one renders as a plain row.
private struct DeparturesList: View {

    let departures: [CallAtLocation]

    var body: some View {
        List {
            ForEach(departures) { departure in
                if let route = departure.routeDetails {
                    NavigationLink(value: route) {
                        DepartureRow(departure: departure)
                    }
                } else {
                    DepartureRow(departure: departure)
                }
            }
            .listRowSeparator(.visible)
            .listRowInsets(EdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16))
            .listRowBackground(Color.panel)
        }
        .listStyle(.plain)
        .background(Color.paper)
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
                Text(departure.destination)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                StatusPill(departure: departure)
            }
            Spacer(minLength: 8)
            Countdown(departure: departure)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Status pill

/// The delay or cancelled status pill under a departure's destination,
/// matching the storyboard's `status-pill`.
private struct StatusPill: View {

    let departure: CallAtLocation

    var body: some View {
        if departure.canceled == true {
            Text("Cancelled")
                .font(.caption.weight(.bold))
                .foregroundStyle(.statusRed)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.statusRedTint, in: Capsule())
        } else if let delay = departure.delayMinutes {
            Text(delay.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(delay.minutes < 0 ? .statusGreen : .statusYellow)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(
                    delay.minutes < 0 ? Color.statusGreenTint : Color.statusYellowTint,
                    in: Capsule()
                )
        }
    }
}

// MARK: - Countdown

/// The right-aligned departure countdown: "2 min" when near, the wall-clock
/// time HH:mm otherwise, or a strikethrough "Cancelled" for canceled trips.
private struct Countdown: View {

    let departure: CallAtLocation

    var body: some View {
        if departure.canceled == true {
            Text("Cancelled")
                .font(.body.weight(.semibold))
                .foregroundStyle(.inkSoft)
                .strikethrough()
        } else {
            Text(Self.text(for: departure))
                .font(.title2.weight(.bold))
                .foregroundStyle(.ink)
                .monospacedDigit()
                .frame(minWidth: 48, alignment: .trailing)
        }
    }

    /// "2 min" when near, otherwise the wall-clock time HH:mm. Falls back to
    /// the raw scheduled string when no time can be parsed.
    static func text(for departure: CallAtLocation) -> String {
        if let date = departure.date {
            let minutes = Calendar.current.dateComponents(
                [.minute],
                from: Date(),
                to: date
            ).minute
            if let minutes, minutes >= 0, minutes < 60 {
                return minutes == 0 ? "Now" : "\(minutes) min"
            }
            return date.formatted(date: .omitted, time: .shortened)
        }
        return departure.scheduled.date.formatted()
    }
}

// MARK: - Line badge

/// The filled, rounded line number badge with a small transport-mode "blip"
/// in the corner, matching the storyboard's `line-badge` + `mode-blip`.
private struct LineBadge: View {

    let departure: CallAtLocation

    @Environment(LineColoursModel.self) private var lineColours

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text(departure.lineLabel)
                .font(.body.weight(.heavy))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(minWidth: 46, minHeight: 44)
                .background(
                    lineColours.badgeColour(
                        designation: departure.route?.designation,
                        transportMode: departure.route?.transport_mode
                    ),
                    in: RoundedRectangle(cornerRadius: 11)
                )
            ModeBlip(mode: departure.route?.transport_mode)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: departure))
    }

    /// Combines the line label and destination into a single accessibility label.
    static func accessibilityLabel(for departure: CallAtLocation) -> String {
        [departure.lineLabel, departure.destination]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

// MARK: - Mode blip

/// The small transport-mode icon overlapping a `LineBadge`'s corner,
/// matching the storyboard's `mode-blip`.
private struct ModeBlip: View {

    let mode: TransportMode?

    var body: some View {
        if let mode {
            Image(systemName: mode.icon)
                .resizable()
                .font(.title.weight(.heavy))
                .aspectRatio(contentMode: .fit)
                .padding(5)
                .frame(width: 30, height: 30)
                .foregroundStyle(.accentDeep)
                .background(Color.panel, in: Circle())
                .overlay(Circle().strokeBorder(Color.hairline, lineWidth: 1))
                .offset(x: 10, y: 15)
        }
    }
}

extension TransportMode {
    /// Maps a Trafiklab `transport_mode` to a SF Symbol, matching the icons in
    /// the storyboard (`BUS`/`TRAM`/`METRO`/`TRAIN`/`BOAT`/`TAXI`).
    var icon: String {
        switch rawMode {
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

// MARK: - Favorite toggle

/// The toolbar star on the Stop board that saves/removes the current stop as a
/// favourite, matching the storyboard's "tap the star on any stop page". The
/// filled state reflects the shared ``FavoritesModel``; the line labels seen
/// on the board are captured into the favourite so the row shows a "Lines …"
/// subtitle.
private struct FavoriteToggle: View {
    @Environment(\.modelContext) var modelContext
    let stopId: String
    let stopName: String
    let departures: [CallAtLocation]
    let model: FavoritesModel

    var body: some View {
        Button {
            model.toggle(
                stopId,
                name: stopName,
                lines: departures.lineLabels,
                context: modelContext
            )
        } label: {
            Image(systemName: model.contains(stopId) ? "star.fill" : "star")
                .font(.title3)
                .foregroundStyle(model.contains(stopId) ? .star : .inkSoft)
                .accessibilityLabel(model.contains(stopId) ? "Remove favourite" : "Add favourite")
        }
    }
}

#Preview("Departures") {
    @Previewable @State var model = FavoritesModel()
    NavigationStack {
        StopDetailsView(
            stopId: "740000001",
            stopName: "Medborgarplatsen"
        )
    }
    .environment(\.network, MockTrafiklabService())
    .environment(model)
    .environment(previewLineColours())
    .modelContainer(mockModelContainer())
}
