import Foundation

/// The app's API keys, loaded from an env file bundled with the build.
///
/// The app target includes a `Secrets.env` file (see `Secrets.example.env`).
/// Copy the example file to `OnBoard/Secrets.env`, replace the bogus keys with
/// your own from https://developer.trafiklab.se, and build: the file is copied
/// into the app bundle as a resource and parsed here. The real `Secrets.env`
/// is git-ignored; the committed `Secrets.example.env` (bogus keys) is the
/// fallback so the project builds and runs with no setup.
///
/// Format: one `KEY=VALUE` per line. Blank lines and lines starting with `#`
/// are ignored; surrounding whitespace is trimmed; `export KEY=VALUE` is
/// accepted; values may be wrapped in double quotes.
struct Secrets {
    /// The bundled file the app reads its keys from, in fallback order: the
    /// git-ignored `Secrets.env` first, then the committed `Secrets.example.env`
    /// with bogus keys.
    private static let fileNames = ["Secrets", "Secrets.example"]
    /// The file extension Xcode gives the bundled env files.
    private static let fileExtension = "env"

    /// Keys parsed from the bundled env file, keyed by name.
    let values: [String: String]

    /// Loads the keys from `Secrets.env` in the given bundle, falling back to
    /// `Secrets.example.env` when no `Secrets.env` is bundled.
    /// - Parameter bundle: The bundle containing the env file resources.
    init(bundle: Bundle = .main) {
        self.values = Self.load(from: bundle)
    }

    /// Loads keys from an env-file source string (see the type doc for the format).
    init(parsing source: String) {
        var parsed: [String: String] = [:]
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let pair = trimmed.hasPrefix("export ")
                ? trimmed.dropFirst("export ".count)
                : trimmed[...]
            guard let separator = pair.firstIndex(of: "=") else { continue }
            let key = pair[..<separator].trimmingCharacters(in: .whitespaces)
            var value = pair[pair.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty else { continue }
            parsed[key] = value
        }
        self.values = parsed
    }

    /// The key for the Trafiklab Realtime APIs (Stop Lookup, Timetables, Trips).
    /// Throws ``SecretsError/missingKey(_:)`` when the env file has no value.
    var realtimeKey: String {
        get throws { try value(for: "TRAFIKLAB_REALTIME_KEY") }
    }

    /// The key for ResRobot v2.1 (Nearby Stops).
    /// Throws ``SecretsError/missingKey(_:)`` when the env file has no value.
    var resrobotKey: String {
        get throws { try value(for: "TRAFIKLAB_RESROBOT_KEY") }
    }

    /// Returns the value for a key, or an empty string when it is not present.
    subscript(key: String) -> String {
        values[key] ?? ""
    }

    /// Returns the value for a key, throwing when it is missing or empty.
    /// - Parameter name: The env-file key name, e.g. `TRAFIKLAB_REALTIME_KEY`.
    /// - Throws: ``SecretsError/missingKey(_:)`` when no non-empty value exists.
    private func value(for name: String) throws -> String {
        guard let value = values[name], !value.isEmpty else {
            throw SecretsError.missingKey(name)
        }
        return value
    }

    /// Reads and parses the first env file the bundle contains, preferring
    /// `Secrets.env` over the example fallback.
    private static func load(from bundle: Bundle) -> [String: String] {
        guard let url = fileNames.lazy.compactMap({
            bundle.url(forResource: $0, withExtension: fileExtension)
        }).first,
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        return Secrets(parsing: source).values
    }
}

/// Errors thrown by ``Secrets``.
enum SecretsError: Error, Equatable {
    /// The bundled env file has no non-empty value for the named key.
    case missingKey(String)
}
