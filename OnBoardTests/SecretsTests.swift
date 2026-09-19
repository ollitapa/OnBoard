import Testing
import Foundation
@testable import OnBoard

struct SecretsTests {
    /// A type whose bundle is the test bundle, which bundles no env file.
    private final class EmptyBundleMarker {}
    // MARK: - init(parsing:)

    @Test func parsingReadsSimpleKeys() {
        let secrets = Secrets(parsing: """
            TRAFIKLAB_REALTIME_KEY=abc123
            TRAFIKLAB_RESROBOT_KEY=def456
            """)
        #expect(secrets.realtimeKey == "abc123")
        #expect(secrets.resrobotKey == "def456")
    }

    @Test func parsingSkipsCommentsAndBlankLines() {
        let secrets = Secrets(parsing: """
            # The realtime key
            TRAFIKLAB_REALTIME_KEY=abc123


            #TRAFIKLAB_FAKE_KEY=nope
            """)
        #expect(secrets.realtimeKey == "abc123")
        #expect(secrets["TRAFIKLAB_FAKE_KEY"] == "")
    }

    @Test func parsingTrimsWhitespaceAndSupportsExportAndQuotes() {
        let secrets = Secrets(parsing: """
              export   TRAFIKLAB_REALTIME_KEY =   abc123
              TRAFIKLAB_RESROBOT_KEY="def456"
            """)
        #expect(secrets.realtimeKey == "abc123")
        #expect(secrets.resrobotKey == "def456")
    }

    @Test func parsingSkipsLinesWithoutSeparator() {
        let secrets = Secrets(parsing: """
            TRAFIKLAB_REALTIME_KEY
            TRAFIKLAB_RESROBOT_KEY=def456
            """)
        #expect(secrets.realtimeKey == "")
        #expect(secrets.resrobotKey == "def456")
    }

    // MARK: - init(bundle:)

    @Test func bundleFallsBackToExampleFile() {
        // Given: the test host is the app, which bundles no Secrets.env in CI
        // but does bundle the committed Secrets.example.env.
        let secrets = Secrets()
        #expect(!secrets.realtimeKey.isEmpty)
        #expect(!secrets.resrobotKey.isEmpty)
    }

    @Test func missingFileYieldsEmptyValues() {
        // A bundle with no env file resources at all.
        let secrets = Secrets(bundle: Bundle(for: EmptyBundleMarker.self))
        #expect(secrets.values.isEmpty)
        #expect(secrets.realtimeKey == "")
    }
}
