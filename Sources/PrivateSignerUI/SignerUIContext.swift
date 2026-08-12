import Foundation
import PrivateSignerKit

/// Everything the shipped screens need from the host application.
///
/// These views are a convenience, not the contract. Anything they do can be done directly against
/// `PrivateSignerKit`, which is the right move for an app that needs its own wording or layout.
public struct SignerUIContext {
    public let keychain: SignerKeychainConfiguration
    /// Environments offered in the configuration screen. A single-environment app can leave this
    /// at `[.default]` and no picker is shown.
    public let environments: [SignerEnvironment]
    /// Identifies the calling app in Worker logs, e.g. `"MyApp/1.2.3"`.
    public let userAgent: String
    public let defaultProfileID: String?

    public init(
        keychain: SignerKeychainConfiguration,
        environments: [SignerEnvironment] = [.default],
        userAgent: String,
        defaultProfileID: String? = nil
    ) {
        self.keychain = keychain
        self.environments = environments.isEmpty ? [.default] : environments
        self.userAgent = userAgent
        self.defaultProfileID = defaultProfileID
    }

    public func store(for environment: SignerEnvironment) -> SignerConfigurationStore {
        SignerConfigurationStore(keychain: keychain, environment: environment)
    }
}

enum UIStrings {
    /// Resolved once against the user's language, not the host app's declared localizations.
    /// See `PackageLocalization`.
    private static let bundle = PackageLocalization.bundle(for: .module)

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        guard !arguments.isEmpty else { return format }
        return String(format: format, arguments: arguments)
    }
}
