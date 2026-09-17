import Testing
import Foundation
@testable import OnBoard

@MainActor
struct CallAtLocationFavoritesTests {
    // MARK: - lineLabels

    @Test func lineLabelsEmptyForEmptyBoard() {
        let departures: [CallAtLocation] = []
        #expect(departures.lineLabels == [])
    }

    @Test func lineLabelsCollectsDistinctDesignations() {
        let departures = [
            Self.departure(designation: "3"),
            Self.departure(designation: "7"),
            Self.departure(designation: "55")
        ]
        #expect(departures.lineLabels == ["3", "7", "55"])
    }

    @Test func lineLabelsDeduplicatesRepeatedLines() {
        let departures = [
            Self.departure(designation: "3"),
            Self.departure(designation: "3"),
            Self.departure(designation: "7")
        ]
        #expect(departures.lineLabels == ["3", "7"])
    }

    @Test func lineLabelsPreservesFirstSeenOrder() {
        let departures = [
            Self.departure(designation: "7"),
            Self.departure(designation: "3"),
            Self.departure(designation: "7")
        ]
        #expect(departures.lineLabels == ["7", "3"])
    }

    @Test func lineLabelsDropsPlaceholder() {
        let departures = [
            Self.departure(designation: nil, name: nil),
            Self.departure(designation: "3")
        ]
        #expect(departures.lineLabels == ["3"])
    }

    @Test func lineLabelsFallsBackToRouteName() {
        let departures = [
            Self.departure(designation: nil, name: "Saltsjöbanan")
        ]
        #expect(departures.lineLabels == ["Saltsjöbanan"])
    }

    // MARK: - Helpers

    /// Builds a `CallAtLocation` with the line-label-relevant fields set and
    /// sensible defaults elsewhere, mirroring `StopDetailsModelTests.departure`.
    private static func departure(
        designation: String?,
        name: String? = nil
    ) -> CallAtLocation {
        CallAtLocation(
            scheduled: "2099-01-01T12:00:00",
            realtime: nil,
            delay: nil,
            canceled: nil,
            is_realtime: nil,
            route: Route(
                designation: designation,
                transport_mode: nil,
                direction: "Destination",
                name: name
            ),
            agency: nil,
            trip: nil,
            stop: nil,
            scheduled_platform: nil,
            realtime_platform: nil,
            alerts: nil
        )
    }
}
