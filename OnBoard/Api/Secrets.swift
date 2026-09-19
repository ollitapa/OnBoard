import Foundation

/// The app's API keys, loaded from an env file bundled with the build.
///
/// Create a git-ignored `OnBoard/Secrets.env` with your keys from
/// https://developer.trafiklab.se (see the README's "API keys" section); the
/// file is copied into the app bundle as a resource and parsed here. A missing
/// file leaves `values` empty, so each key accessor throws
/// ``SecretMissingForKey`` and the failure surfaces on the screen that loads.
///
/// Format: one `KEY=VALUE` per line. Blank lines and lines starting with `#`
/// are ignored; surrounding whitespace is trimmed; `export KEY=VALUE` is
/// accepted; values may be wrapped in double quotes.
struct Secrets {
    /// The bundled file the app reads its keys from.
    private static let fileName = "Secrets"
    /// The file extension Xcode gives the bundled env file.
    private static let fileExtension = "env"

    /// Keys parsed from the bundled env file, keyed by name.
    let values: [String: String]

    /// Loads the keys from `Secrets.env` in the given bundle.
    /// - Parameter bundle: The bundle containing the env file resource.
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
    /// Throws ``SecretMissingForKey`` when the env file has no value.
    var realtimeKey: String {
        get throws { try value(for: "TRAFIKLAB_REALTIME_KEY") }
    }

    /// The key for ResRobot v2.1 (Nearby Stops).
    /// Throws ``SecretMissingForKey`` when the env file has no value.
    var resrobotKey: String {
        get throws { try value(for: "TRAFIKLAB_RESROBOT_KEY") }
    }

    /// Returns the value for a key, or an empty string when it is not present.
    subscript(key: String) -> String {
        values[key] ?? ""
    }

    /// Returns the value for a key, throwing when it is missing or empty.
    /// - Parameter name: The env-file key name, e.g. `TRAFIKLAB_REALTIME_KEY`.
    /// - Throws: ``SecretMissingForKey`` when no non-empty value exists.
    private func value(for name: String) throws -> String {
        guard let value = values[name], !value.isEmpty else {
            throw SecretMissingForKey(key: name)
        }
        return value
    }

    /// Reads and parses the bundle's env file, returning no values when the
    /// file is not bundled.
    private static func load(from bundle: Bundle) -> [String: String] {
        guard let url = bundle.url(forResource: fileName, withExtension: fileExtension),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        return Secrets(parsing: source).values
    }
}

/// The bundled env file has no non-empty value for ``Secrets``' `key`.
struct SecretMissingForKey: Error, Equatable {
    /// The env-file key name that has no non-empty value.
    let key: String
}
