import Foundation

/// Every error the Mealie client throws. `errorDescription` is written for
/// users and can be shown as-is (ErrorState views, alerts).
enum MealieError: LocalizedError, Equatable, Sendable {
    /// The entered server address is not a valid URL.
    case invalidServerURL
    /// Network failure: host not found, connection refused, offline, ...
    case unreachable(String)
    case timedOut
    /// TLS problem (self-signed / expired certificate, http vs https mismatch).
    case insecureConnection(String)
    /// 401: token missing, expired or revoked. The session signs out.
    case unauthorized
    /// 403: signed in but not allowed (e.g. not an admin, locked recipe).
    case forbidden(String?)
    case notFound(String?)
    /// Any other non-2xx status, with Mealie's `detail` message when present.
    case server(status: Int, message: String?)
    /// The response was not what the app expected (wrong server / API change).
    case decoding(String)
    /// The URL answered, but it does not look like a Mealie server.
    case notMealie
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "That doesn’t look like a server address. Try something like https://mealie.example.com."
        case .unreachable(let reason):
            "Can’t reach your Mealie server. Check your connection and the server address.\n\(reason)"
        case .timedOut:
            "Your Mealie server took too long to answer. Check your connection and try again."
        case .insecureConnection(let reason):
            "A secure connection to the server couldn’t be established. If your server uses plain HTTP, enter the address with http://.\n\(reason)"
        case .unauthorized:
            "Your session has expired. Please sign in again."
        case .forbidden(let message):
            message ?? "You don’t have permission to do that on this server."
        case .notFound(let message):
            message ?? "That item doesn’t exist on the server anymore."
        case .server(let status, let message):
            message ?? "The server returned an error (\(status))."
        case .decoding:
            "The server sent a response MealMate doesn’t understand. Is the server up to date?"
        case .notMealie:
            "This address answered, but it doesn’t look like a Mealie server."
        case .cancelled:
            "The request was cancelled."
        }
    }

    var isUnauthorized: Bool { self == .unauthorized }
    var isCancelled: Bool { self == .cancelled }
    /// True for errors where showing cached data and a "you're offline" hint makes sense.
    var isConnectivityProblem: Bool {
        switch self {
        case .unreachable, .timedOut: true
        default: false
        }
    }

    /// Maps any error (URLError, DecodingError, CancellationError, ...) to a `MealieError`.
    static func wrap(_ error: Error) -> MealieError {
        if let error = error as? MealieError { return error }
        if error is CancellationError { return .cancelled }
        if let error = error as? URLError { return MealieError(urlError: error) }
        if let error = error as? DecodingError { return .decoding(Self.describe(error)) }
        return .unreachable(error.localizedDescription)
    }

    init(urlError: URLError) {
        switch urlError.code {
        case .cancelled:
            self = .cancelled
        case .timedOut:
            self = .timedOut
        case .badURL, .unsupportedURL:
            self = .invalidServerURL
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected,
             .clientCertificateRequired, .appTransportSecurityRequiresSecureConnection:
            self = .insecureConnection(urlError.localizedDescription)
        default:
            self = .unreachable(urlError.localizedDescription)
        }
    }

    /// Builds an error from an HTTP status and Mealie's error body.
    ///
    /// Mealie's `detail` comes in three shapes:
    /// `"text"`, `{"message": "text", "error": true}` and FastAPI validation
    /// arrays `[{"loc": [...], "msg": "text"}]`.
    init(status: Int, body: Data) {
        let message = Self.detailMessage(from: body)
        switch status {
        case 401: self = .unauthorized
        case 403: self = .forbidden(message)
        case 404: self = .notFound(message)
        default: self = .server(status: status, message: message)
        }
    }

    static func detailMessage(from body: Data) -> String? {
        guard !body.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        let detail = object["detail"] ?? object["message"]
        switch detail {
        case let text as String:
            return text.isEmpty ? nil : text
        case let dict as [String: Any]:
            return (dict["message"] as? String) ?? (dict["detail"] as? String)
        case let list as [[String: Any]]:
            let messages = list.compactMap { entry -> String? in
                guard let msg = entry["msg"] as? String else { return nil }
                if let loc = entry["loc"] as? [Any], let field = loc.last.map({ "\($0)" }), field != "body" {
                    return "\(field): \(msg)"
                }
                return msg
            }
            return messages.isEmpty ? nil : messages.joined(separator: "\n")
        default:
            return nil
        }
    }

    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
        }
        switch error {
        case .typeMismatch(let type, let context):
            return "Type mismatch (\(type)) at \(path(context)): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Missing value (\(type)) at \(path(context))"
        case .keyNotFound(let key, let context):
            return "Missing key \(key.stringValue) at \(path(context))"
        case .dataCorrupted(let context):
            return "Corrupted data at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}
