import Testing
import Foundation
@testable import OnBoard

/// Tests the error-to-message mapping the models render on screen
/// (`Error.loadFailureMessage`), which replaces raw
/// `String(describing: error)` dumps with plain-language text.
struct LoadFailureMessageTests {
    @Test func mapsQuotaExceeded() {
        let message = TrafiklabHTTPError(
            response: Self.response(statusCode: 429)
        ).loadFailureMessage
        #expect(message.localizedCaseInsensitiveContains("quota"))
    }

    @Test func mapsRejectedKey() {
        let message = TrafiklabHTTPError(
            response: Self.response(statusCode: 401)
        ).loadFailureMessage
        #expect(message.localizedCaseInsensitiveContains("key"))
        #expect(message.localizedCaseInsensitiveContains("Secrets.env"))
    }

    @Test func mapsServerErrors() {
        let message = TrafiklabHTTPError(
            response: Self.response(statusCode: 503)
        ).loadFailureMessage
        #expect(message.localizedCaseInsensitiveContains("server"))
        #expect(message.contains("503"))
    }

    @Test func mapsMissingSecretByName() {
        let message = SecretMissingForKey(key: "TRAFIKLAB_REALTIME_KEY").loadFailureMessage
        #expect(message.contains("TRAFIKLAB_REALTIME_KEY"))
        #expect(message.localizedCaseInsensitiveContains("Secrets.env"))
    }

    @Test func mapsOfflineURLErrors() {
        #expect(
            URLError(.notConnectedToInternet).loadFailureMessage
                .localizedCaseInsensitiveContains("internet")
        )
        #expect(
            URLError(.timedOut).loadFailureMessage
                .localizedCaseInsensitiveContains("internet")
        )
        #expect(
            URLError(.networkConnectionLost).loadFailureMessage
                .localizedCaseInsensitiveContains("internet")
        )
    }

    @Test func mapsDecodingErrorsWithoutTheRawDump() {
        let error = DecodingError.dataCorrupted(
            .init(codingPath: [], debugDescription: "payload is not valid JSON")
        )
        #expect(error.loadFailureMessage.localizedCaseInsensitiveContains("couldn't read"))
    }

    @Test func keepsUnknownErrorsDebuggable() {
        struct Unexpected: Error {}
        let error = Unexpected()
        #expect(error.loadFailureMessage == String(describing: error))
    }

    @Test func missingKeyDoesNotSurfaceAsADecodingDump() {
        // The README's story: a missing key surfaces as a load failure naming
        // the key, not as an opaque decoder or generic error dump. The message
        // must not leak the raw SwiftDecodingError shape.
        let message = SecretMissingForKey(key: "TRAFIKLAB_RESROBOT_KEY").loadFailureMessage
        #expect(!message.contains("SwiftDecodingError"))
    }

    /// A non-2xx response for the departures path, the realistic shape the
    /// mapping is exercised with.
    private static func response(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: URL(string: "https://realtime-api.trafiklab.se/v1/departures/740000001")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}
