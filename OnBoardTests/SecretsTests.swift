import Testing
import Foundation
@testable import OnBoard

struct SecretsTests {
    /// A type whose bundle is the test bundle, which bundles no env file.
    private final class EmptyBundleMarker {}
    // MARK: - init(parsing:)

    @Test func parsingReadsSimpleKeys() throws {
        let secrets = Secrets(parsing: """
            TRAFIKLAB_REALTIME_KEY=abc123
            TRAFIKLAB_RESROBOT_KEY=def456
            """)
        #expect(try secrets.realtimeKey == "abc123")
        #expect(try secrets.resrobotKey == "def456")
    }

    @Test func parsingSkipsCommentsAndBlankLines() throws {
        let secrets = Secrets(parsing: """
            # The realtime key
            TRAFIKLAB_REALTIME_KEY=abc123


            #TRAFIKLAB_FAKE_KEY=nope
            """)
        #expect(try secrets.realtimeKey == "abc123")
        #expect(secrets["TRAFIKLAB_FAKE_KEY"] == "")
    }

    @Test func parsingTrimsWhitespaceAndSupportsExportAndQuotes() throws {
        let secrets = Secrets(parsing: """
              export   TRAFIKLAB_REALTIME_KEY =   abc123
              TRAFIKLAB_RESROBOT_KEY="def456"
            """)
        #expect(try secrets.realtimeKey == "abc123")
        #expect(try secrets.resrobotKey == "def456")
    }

    @Test func parsingSkipsLinesWithoutSeparator() async {
        let secrets = Secrets(parsing: """
            TRAFIKLAB_REALTIME_KEY
            TRAFIKLAB_RESROBOT_KEY=def456
            """)
        await #expect(throws: SecretMissingForKey(key: "TRAFIKLAB_REALTIME_KEY")) {
            _ = try secrets.realtimeKey
        }
        #expect(try secrets.resrobotKey == "def456")
    }

    @Test func missingOrEmptyKeyThrows() async {
        let missing = Secrets(parsing: "TRAFIKLAB_RESROBOT_KEY=def456")
        await #expect(throws: SecretMissingForKey(key: "TRAFIKLAB_REALTIME_KEY")) {
            _ = try missing.realtimeKey
        }
        let empty = Secrets(parsing: "TRAFIKLAB_REALTIME_KEY=")
        await #expect(throws: SecretMissingForKey(key: "TRAFIKLAB_REALTIME_KEY")) {
            _ = try empty.realtimeKey
        }
    }

    // MARK: - init(bundle:)

    @Test func bundleFallsBackToExampleFile() throws {
        // Given: the test host is the app, which bundles no Secrets.env in CI
        // but does bundle the committed Secrets.example.env.
        let secrets = Secrets()
        #expect(try !secrets.realtimeKey.isEmpty)
        #expect(try !secrets.resrobotKey.isEmpty)
    }

    @Test func missingFileThrowsOnEveryKey() async {
        // A bundle with no env file resources at all.
        let secrets = Secrets(bundle: Bundle(for: EmptyBundleMarker.self))
        #expect(secrets.values.isEmpty)
        await #expect(throws: SecretMissingForKey(key: "TRAFIKLAB_REALTIME_KEY")) {
            _ = try secrets.realtimeKey
        }
    }
}
