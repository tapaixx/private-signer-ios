import Foundation
import Security

/// Where a host application keeps its Signer configuration in the Keychain.
///
/// `configurationAccessGroup` is the Stable Configuration Group: the access group that must
/// outlive every future signature. Under Split signing the *default* access group is derived
/// from the provisioning profile's application identifier, so it changes whenever the profile
/// changes — an app that relies on the default loses its Worker URL and token on the first
/// self-update. Naming a stable group and asking the signer to materialize it is what prevents
/// that.
public struct SignerKeychainConfiguration {
    /// `kSecAttrService`. Conventionally `<your.bundle.id>.private-signer`.
    public let service: String
    /// `kSecAttrAccount` for ``SignerEnvironment/default``. Named environments append `.<name>`.
    public let account: String
    /// The Stable Configuration Group, e.g. `TEAMID.com.example.app`. Required.
    public let configurationAccessGroup: String
    /// Access groups previous versions of the app wrote to. Reading falls back to these, and a
    /// hit is migrated into ``configurationAccessGroup`` on the spot.
    public let legacyAccessGroups: [String]

    public init(
        service: String,
        account: String = "worker-configuration",
        configurationAccessGroup: String,
        legacyAccessGroups: [String] = []
    ) {
        self.service = service
        self.account = account
        self.configurationAccessGroup = configurationAccessGroup
        self.legacyAccessGroups = legacyAccessGroups
    }
}

public struct SignerConfigurationStore {
    public let keychain: SignerKeychainConfiguration
    public let environment: SignerEnvironment

    public init(keychain: SignerKeychainConfiguration, environment: SignerEnvironment = .default) {
        self.keychain = keychain
        self.environment = environment
    }

    /// Every access group this client is allowed to read or write.
    ///
    /// Pass this as ``SigningOptions/keychainAccessGroups`` so the signer materializes the same
    /// groups into the signed entitlements. A signed app that does not carry its own
    /// configuration group cannot read the configuration it was signed with.
    public var authorizedAccessGroups: [String] {
        [keychain.configurationAccessGroup] + keychain.legacyAccessGroups
    }

    private var account: String {
        keychain.account + environment.accountSuffix
    }

    private var searchOrder: [String?] {
        authorizedAccessGroups.map { Optional($0) } + [nil]
    }

    public func load() throws -> SignerConfiguration? {
        var firstAccessError: OSStatus?
        for accessGroup in searchOrder {
            do {
                if let configuration = try load(accessGroup: accessGroup) {
                    if accessGroup != keychain.configurationAccessGroup {
                        try saveStable(configuration: configuration)
                    }
                    return configuration
                }
            } catch SignerConfigurationError.keychain(let status) where status == errSecMissingEntitlement {
                firstAccessError = firstAccessError ?? status
                continue
            }
        }
        if let firstAccessError { throw SignerConfigurationError.keychain(firstAccessError) }
        return nil
    }

    private func load(accessGroup: String?) throws -> SignerConfiguration? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ].merging(accessGroup.map { [kSecAttrAccessGroup as String: $0] } ?? [:]) { current, _ in current }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SignerConfigurationError.keychain(status)
        }
        guard let configuration = try? JSONDecoder().decode(SignerConfiguration.self, from: data) else {
            throw SignerConfigurationError.invalidStoredData
        }
        return configuration
    }

    @discardableResult
    public func save(workerURL rawWorkerURL: String, requestToken rawToken: String) throws -> SignerConfiguration {
        let workerURL = try Self.validatedWorkerURL(rawWorkerURL)
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw SignerConfigurationError.emptyToken }
        let configuration = SignerConfiguration(workerURL: workerURL, requestToken: token)
        try saveStable(configuration: configuration)
        return configuration
    }

    private func saveStable(configuration: SignerConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        let matchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecAttrAccessGroup as String: keychain.configurationAccessGroup,
        ]
        let updateStatus = SecItemUpdate(
            matchQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw SignerConfigurationError.keychain(updateStatus)
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecAttrAccessGroup as String: keychain.configurationAccessGroup,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SignerConfigurationError.keychain(status)
        }
    }

    /// Removes this environment's configuration from every access group it could live in.
    public func clear() throws {
        var firstFailure: OSStatus?
        for accessGroup in searchOrder {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychain.service,
                kSecAttrAccount as String: account,
                kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            ].merging(accessGroup.map { [kSecAttrAccessGroup as String: $0] } ?? [:]) { current, _ in current }
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound && status != errSecMissingEntitlement {
                firstFailure = firstFailure ?? status
            }
        }
        if let firstFailure { throw SignerConfigurationError.keychain(firstFailure) }
    }

    /// HTTPS only, no embedded credentials, no query or fragment, no trailing slash.
    static func validatedWorkerURL(_ rawValue: String) throws -> URL {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil else {
            throw SignerConfigurationError.invalidWorkerURL
        }
        components.fragment = nil
        components.query = nil
        if components.path.count > 1 && components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else {
            throw SignerConfigurationError.invalidWorkerURL
        }
        return url
    }
}
