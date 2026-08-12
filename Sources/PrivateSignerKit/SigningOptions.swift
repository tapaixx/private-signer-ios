import Foundation

/// The explicit identity policy for a Signing Job.
///
/// `standard` keeps bundle and application identities conventionally aligned. `split` keeps the
/// final bundle identity separate from the profile-derived application identity, which is what
/// makes side-by-side clones possible. The server never infers this — always send it.
public enum SigningMode: String, Codable, CaseIterable, Identifiable {
    case split
    case standard

    public var id: String { rawValue }
}

/// How the signer should treat source material the selected profile cannot authorize.
public enum CompatibilityPolicy: String, Codable {
    case stripUnsupported = "strip_unsupported"
    case requireAll = "require_all"
}

public struct SigningOptions: Encodable, Equatable {
    public var signingMode: SigningMode
    /// The requested identity of the signed main app. When `nil`, the Source IPA's main bundle
    /// identifier is preserved.
    public var targetBundleIdentifier: String?
    /// Selects one configured certificate and provisioning-profile set. `nil` selects the default.
    public var profileID: String?
    public var keychainAccessGroups: [String]
    public var embeddedBundlePolicy: CompatibilityPolicy
    public var entitlementPolicy: CompatibilityPolicy
    public var expectedSHA256: String?
    public var expectedVersion: String?
    public var expectedBuild: String?

    public init(
        signingMode: SigningMode = .split,
        targetBundleIdentifier: String? = nil,
        profileID: String? = nil,
        keychainAccessGroups: [String] = [],
        embeddedBundlePolicy: CompatibilityPolicy = .stripUnsupported,
        entitlementPolicy: CompatibilityPolicy = .stripUnsupported,
        expectedSHA256: String? = nil,
        expectedVersion: String? = nil,
        expectedBuild: String? = nil
    ) {
        self.signingMode = signingMode
        self.targetBundleIdentifier = targetBundleIdentifier
        self.profileID = profileID
        self.keychainAccessGroups = keychainAccessGroups
        self.embeddedBundlePolicy = embeddedBundlePolicy
        self.entitlementPolicy = entitlementPolicy
        self.expectedSHA256 = expectedSHA256
        self.expectedVersion = expectedVersion
        self.expectedBuild = expectedBuild
    }

    private enum CodingKeys: String, CodingKey {
        case signingMode = "signing_mode"
        case targetBundleIdentifier = "target_bundle_id"
        case profileID = "profile_id"
        case keychainAccessGroups = "keychain_access_groups"
        case embeddedBundlePolicy = "embedded_bundle_policy"
        case entitlementPolicy = "entitlement_policy"
        case expectedSHA256 = "expected_sha256"
        case expectedVersion = "expected_version"
        case expectedBuild = "expected_build"
    }
}

/// Normalizes a GitHub-style asset digest (`sha256:<hex>`) into the bare lowercase hex the
/// `expected_sha256` option requires. Returns `nil` for anything that is not 64 hex characters,
/// because sending a malformed digest fails the job rather than protecting it.
public func normalizedSHA256(_ rawValue: String?) -> String? {
    guard let digest = rawValue?.lowercased() else { return nil }
    let value = digest.hasPrefix("sha256:") ? String(digest.dropFirst(7)) : digest
    return value.count == 64 && value.allSatisfy { $0.isHexDigit } ? value : nil
}
