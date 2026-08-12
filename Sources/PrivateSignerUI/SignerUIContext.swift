import Foundation
import PrivateSignerKit

/// Everything the shipped screens need from the host application.
///
/// Profile identifiers are intentionally absent. They are deployment state discovered from the
/// Worker, not values a host app should compile in.
public struct SignerUIContext {
    public let keychain: SignerKeychainConfiguration
    public let environments: [SignerEnvironment]
    public let userAgent: String

    public init(
        keychain: SignerKeychainConfiguration,
        environments: [SignerEnvironment] = [.default],
        userAgent: String
    ) {
        self.keychain = keychain
        self.environments = environments.isEmpty ? [.default] : environments
        self.userAgent = userAgent
    }

    public func store(for environment: SignerEnvironment) -> SignerConfigurationStore {
        SignerConfigurationStore(keychain: keychain, environment: environment)
    }
}

enum UIStrings {
    private static let bundle = PackageLocalization.bundle(for: .module)

    static func string(_ key: String, _ arguments: CVarArg...) -> String {
        let format = NSLocalizedString(key, bundle: bundle, comment: "")
        guard !arguments.isEmpty else { return format }
        return String(format: format, arguments: arguments)
    }
}
