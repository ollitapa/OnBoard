import Foundation

extension Error {

    /// A plain-language failure message for an error that surfaced from a
    /// screen's load, replacing the raw `String(describing:)` dump the views
    /// used to render. A 401 (bad key), a 429 (exhausted quota), an
    /// `URLError` from a dead connection, or an HTML error page fed to the
    /// JSON decoder each map to a message that tells the user what went wrong
    /// and what (if anything) to do about it; the secret-missing case names
    /// the missing env-file key. Anything unmapped keeps the raw description,
    /// so unexpected failures stay debuggable rather than silently generic.
    var loadFailureMessage: String {
        switch self {
        case let error as TrafiklabHTTPError:
            error.loadFailureMessage
        case let error as SecretMissingForKey:
            "Missing API key: no value for \"\(error.key)\" in Secrets.env. See the README's \"API keys\" section."
        case let error as URLError:
            error.loadFailureMessage
        case let error as DecodingError:
            "The server sent a response the app couldn't read. Try again in a moment."
        default:
            String(describing: self)
        }
    }
}

extension TrafiklabHTTPError {

    /// A plain-language message for a non-2xx Trafiklab response.
    var loadFailureMessage: String {
        switch statusCode {
        case 401:
            "The API key was rejected (HTTP 401). Check the keys in Secrets.env; see the README's \"API keys\" section."
        case 403:
            "The API key doesn't cover this product (HTTP 403). Check the keys in Secrets.env; see the README's \"API keys\" section."
        case 404:
            "The stop wasn't found (HTTP 404)."
        case 429:
            "API quota exceeded (HTTP 429). The key's request limit is used up — try again later."
        case 500...599:
            "Trafiklab's server hit an error (HTTP \(statusCode)). Try again in a moment."
        default:
            "The request failed (HTTP \(statusCode))."
        }
    }
}

extension URLError {

    /// A plain-language message for a `URLError`, covering the failures a
    /// phone on a flaky connection produces. Unmapped codes fall back to
    /// the raw description.
    var loadFailureMessage: String {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
             .timedOut, .internationalRoamingOff:
            "No internet connection. Check your connection and try again."
        case .cancelled:
            "The request was cancelled."
        default:
            String(describing: self)
        }
    }
}
