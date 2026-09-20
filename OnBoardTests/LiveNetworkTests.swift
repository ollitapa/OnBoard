import Testing
import Foundation
@testable import OnBoard

/// Tests the transient-failure classification `LiveNetwork` retries on. The
/// retry loop itself lives behind `URLSession.shared`, so the classification
/// is the unit under test: a retryable blip (timeout, dropped connection) is
/// distinguished from a failure another attempt can't fix (a cancelled task,
/// a malformed URL) and from anything that isn't a transport error at all.
struct LiveNetworkTests {
    @Test func classifiesTimeoutsAsTransient() {
        #expect(URLError(.timedOut).isTransientTransportFailure)
    }

    @Test func classifiesDroppedConnectionsAsTransient() {
        #expect(URLError(.networkConnectionLost).isTransientTransportFailure)
        #expect(URLError(.notConnectedToInternet).isTransientTransportFailure)
        #expect(URLError(.cannotConnectToHost).isTransientTransportFailure)
        #expect(URLError(.dnsLookupFailed).isTransientTransportFailure)
    }

    @Test func doesNotRetryCancellationOrBadRequests() {
        #expect(!URLError(.cancelled).isTransientTransportFailure)
        #expect(!URLError(.badURL).isTransientTransportFailure)
        #expect(!URLError(.badServerResponse).isTransientTransportFailure)
    }
}
