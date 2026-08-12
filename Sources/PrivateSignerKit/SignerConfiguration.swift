import Foundation

/// The Worker endpoint and Signing Request Token a client uses to submit Signing Requests.
///
/// The token is full-authority user configuration. It is entered by the person operating the app,
/// stored in the device Keychain, and must never be compiled into a public application.
public struct SignerConfiguration: Codable, Equatable {
    public let workerURL: URL
    public let requestToken: String

    public init(workerURL: URL, requestToken: String) {
        self.workerURL = workerURL
        self.requestToken = requestToken
    }

    /// Storage compatibility: clients shipped before this package existed persisted the token
    /// under the key `personalToken`. Changing the Swift property name must not orphan the
    /// Keychain item those clients already wrote, so the coding key is pinned.
    private enum CodingKeys: String, CodingKey {
        case workerURL
        case requestToken = "personalToken"
    }
}

/// A named set of stored credentials, so one installed app can hold several Signer
/// configurations (for example a production Worker and a staging Worker) at the same time.
public struct SignerEnvironment: Hashable, CustomStringConvertible {
    /// The environment used when a client never asks for a named one.
    ///
    /// Its Keychain account carries no suffix, which is what keeps already-installed clients
    /// readable after they adopt this package.
    public static let `default` = SignerEnvironment(unchecked: "default")

    public let name: String

    private init(unchecked name: String) {
        self.name = name
    }

    /// Returns `nil` when the name would produce an ambiguous Keychain account.
    public init?(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 64,
              trimmed.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            return nil
        }
        self.name = trimmed
    }

    var accountSuffix: String {
        self == .default ? "" : ".\(name)"
    }

    public var description: String { name }
}

public enum SignerConfigurationError: LocalizedError, Equatable {
    case invalidWorkerURL
    case emptyToken
    case keychain(OSStatus)
    case invalidStoredData

    /// Stable, non-localized identifier. Log or branch on this, never on `errorDescription`.
    public var code: String {
        switch self {
        case .invalidWorkerURL: return "invalid_worker_url"
        case .emptyToken: return "empty_token"
        case .keychain: return "keychain"
        case .invalidStoredData: return "invalid_stored_data"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidWorkerURL:
            return KitStrings.string("error.invalid_worker_url")
        case .emptyToken:
            return KitStrings.string("error.empty_token")
        case .keychain(let status):
            return KitStrings.string("error.keychain", String(status))
        case .invalidStoredData:
            return KitStrings.string("error.invalid_stored_data")
        }
    }
}
