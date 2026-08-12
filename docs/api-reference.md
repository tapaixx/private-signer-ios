# API Reference

**English** · [简体中文](api-reference.zh-CN.md)

The complete public surface of all three products. For **how to integrate**, read the
[integration guide](client-integration-guide.md); this answers "what does this type actually have".

---

## Contents

- [PrivateSignerKit](#privatesignerkit) — the contract
- [PrivateSignerSelfUpdate](#privatesignerselfupdate) — self-update and signature renewal
- [PrivateSignerUI](#privatesignerui) — ready-made screens
- [Error codes](#error-codes)

---

## PrivateSignerKit

The only contract. The UI and self-update products are built on it and can do nothing it cannot.

### `SignerConfiguration`

The Worker URL and the Signing Request Token.

```swift
public struct SignerConfiguration: Codable, Equatable {
    public let workerURL: URL
    public let requestToken: String
    public init(workerURL: URL, requestToken: String)
}
```

⚠️ The stored JSON pins the token under `personalToken`. That is what keeps configuration readable for clients installed before this package existed. Do not "fix" it.

### `SignerEnvironment`

A named environment, so one installed app can hold production and staging credentials at once.

```swift
public struct SignerEnvironment: Hashable, CustomStringConvertible {
    public static let `default`: SignerEnvironment
    public let name: String
    public init?(name: String)   // accepts [A-Za-z0-9_-] only, max 64
}
```

The `default` environment's Keychain account carries **no suffix**, which is what keeps already-installed clients readable. Named environments append `.<name>`.

### `SignerKeychainConfiguration`

```swift
public struct SignerKeychainConfiguration {
    public let service: String                    // convention: <your.bundle.id>.private-signer
    public let account: String                    // defaults to "worker-configuration"
    public let configurationAccessGroup: String   // Stable Configuration Group, required
    public let legacyAccessGroups: [String]       // groups a shipped build already wrote to

    public init(service: String,
                account: String = "worker-configuration",
                configurationAccessGroup: String,
                legacyAccessGroups: [String] = [])
}
```

**`configurationAccessGroup` is the step integrations get wrong.** See [guide §3](client-integration-guide.md#3-decide-the-stable-configuration-group).

### `SignerConfigurationStore`

```swift
public struct SignerConfigurationStore {
    public let keychain: SignerKeychainConfiguration
    public let environment: SignerEnvironment
    public init(keychain: SignerKeychainConfiguration, environment: SignerEnvironment = .default)

    /// Send these with every signing request, or the signed app cannot read its own configuration.
    public var authorizedAccessGroups: [String] { get }

    public func load() throws -> SignerConfiguration?
    @discardableResult
    public func save(workerURL: String, requestToken: String) throws -> SignerConfiguration
    public func clear() throws

    /// Validates a hand-entered URL without storing it: HTTPS only, no credentials, no query.
    public static func validatedWorkerURL(_ rawValue: String) throws -> URL
}
```

`load()` tries the stable group, then the legacy ones, then the default, migrating a hit into the stable group on the spot.

### `SigningOptions`

```swift
public struct SigningOptions: Encodable, Equatable {
    public var signingMode: SigningMode                  // defaults to .split
    public var targetBundleIdentifier: String?           // nil preserves the source's identity
    public var profileID: String?                        // nil selects the service's default set
    public var keychainAccessGroups: [String]
    public var embeddedBundlePolicy: CompatibilityPolicy // defaults to .stripUnsupported
    public var entitlementPolicy: CompatibilityPolicy    // defaults to .stripUnsupported
    public var expectedSHA256: String?
    public var expectedVersion: String?
    public var expectedBuild: String?
}

public enum SigningMode: String, Codable, CaseIterable, Identifiable { case split, standard }
public enum CompatibilityPolicy: String, Codable {
    case stripUnsupported = "strip_unsupported"
    case requireAll = "require_all"
}
```

**Always send `signingMode` explicitly.** The service never infers it, and split and standard produce different artifacts.

```swift
/// Normalizes GitHub's `sha256:<hex>` to bare hex; returns nil for anything not 64 hex chars.
public func normalizedSHA256(_ rawValue: String?) -> String?
```

### `SigningClient`

```swift
public struct SigningClient {
    public static let maximumSourceBytes: Int   // 100 MiB
    public static let maximumPartBytes: Int     // 8 MiB

    public init(configuration: SignerConfiguration,
                userAgent: String,
                transport: SigningTransport? = nil)

    // creating jobs
    public func createURLJob(sourceURL: URL, options: SigningOptions) async throws -> SigningJob
    public func uploadAndCreateJob(filename: String, data: Data, options: SigningOptions) async throws -> SigningJob
    public func uploadAndCreateJob(fileURL: URL, options: SigningOptions) async throws -> SigningJob

    // polling and lifecycle
    public func job(id: String) async throws -> SigningJob
    public func history() async throws -> [SigningJob]      // walks every page
    public func retry(jobID: String) async throws -> SigningJob
    public func cancel(jobID: String) async throws -> SigningJob
    public func links(jobID: String) async throws -> DeliveryLinks

    // configuration self-check
    public func health() async throws -> ServiceHealth
    public func verifyConfiguration() async -> ConfigurationVerification
}
```

`transport` is the test seam:

```swift
public protocol SigningTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
```

`URLSession` already conforms.

### `SigningJob` / `SigningJobStatus` / `DeliveryLinks`

```swift
public struct SigningJob: Decodable, Identifiable, Equatable {
    public let jobID, status, signingMode, source, createdAt, updatedAt: /* see source */
    public let attempt: Int?
    public let errorCode, message: String?
    public let actualBundleIdentifier, actualVersion, actualBuild, actualTitle, finalSHA256: String?
    public let warnings: [String]?
    public var isActive: Bool
}

public enum SigningJobStatus: Equatable, Decodable {
    case dispatching, queued, dispatchFailed, signing, following, completed, failed, cancelled
    case unknown(String)          // so a server that learned a new state does not crash the client
    public var isActive: Bool     // dispatching / queued / signing / following
    public var isFailure: Bool    // failed / dispatchFailed
}

public struct DeliveryLinks: Decodable, Equatable {
    public let manifestURL, installURL, exportURL: URL
    public let expiresAt: String   // 15 minutes; call links() again when it lapses
}
```

⚠️ **Treat `.unknown` as neither active nor failed and keep polling.** A new server state must not break an installed client.

### `ServiceHealth` / `ConfigurationVerification`

```swift
public struct ServiceHealth: Decodable, Equatable {
    public static let supportedContracts: Set<String>   // ["v2"]
    public let ok: Bool
    public let contract: String?
}

public enum ConfigurationVerification: Equatable {
    case usable
    case usableWithUndeclaredContract   // works, but the Worker predates the contract field
    case notASigner                     // wrong address
    case unsupportedContract(String)
    case invalidToken                   // right address, rejected token
    case unreachable(String)

    public var isUsable: Bool
    public var code: String       // stable identifier; branch on this
    public var message: String    // localized text; display this
}
```

**This is the only place those two failures are distinguishable.** A configuration screen should use it.

### `OTAInstallation`

```swift
public enum OTAInstallation {
    /// Wraps an HTTPS manifest in the itms-services:// URL iOS needs; nil for non-HTTPS.
    public static func installationURL(manifestURL: URL) -> URL?
}
```

---

## PrivateSignerSelfUpdate

### `ReleaseSource`

**The only thing an integration has to implement.**

```swift
public protocol ReleaseSource {
    /// The newest candidate strictly newer than currentVersion; nil when already current.
    func latestRelease(currentVersion: String) async throws -> ReleaseCandidate?

    /// The release matching an exact version, used only for signature renewal.
    /// Defaults to nil, which disables renewal for that source.
    func release(matching version: String) async throws -> ReleaseCandidate?
}

public struct ReleaseCandidate: Equatable {
    public let version: String
    public let ipaURL: URL
    public let expectedSHA256: String?
    public let notes: String?
}
```

### `GitHubReleaseSource`

The built-in implementation covering the common case.

```swift
public struct GitHubReleaseSource: ReleaseSource {
    public init(repository: String,                    // "owner/name"
                assetNameTemplate: String,             // "MyApp-{tag}-unsigned.ipa"
                userAgent: String,
                includePrereleases: Bool = false,
                ordering: VersionOrdering = BuildTaggedVersionOrdering(),
                pageSize: Int = 30,
                transport: SigningTransport? = nil)
}
```

Template placeholders: `{tag}` is the published tag verbatim (`v1.0.5-0006`); `{version}` is the same without a leading `v`.

### `VersionOrdering`

```swift
public protocol VersionOrdering {
    /// Returns nil when either side cannot be parsed, so callers skip rather than guess.
    func compare(_ lhs: String, _ rhs: String) -> ComparisonResult?
}

public struct BuildTaggedVersionOrdering: VersionOrdering {}  // vX.Y.Z-NNNN (default)
public struct DottedVersionOrdering: VersionOrdering {}       // 1.2.3 / v2.0

public struct BuildTaggedVersion: Comparable, CustomStringConvertible {
    public init?(_ rawValue: String)
    public let major, minor, patch, build, buildDigits: Int
    public var tagName: String   // round-trips the published tag exactly
}
```

**Do not change your tag scheme to satisfy this package** — implement `VersionOrdering` instead.

### `SelfUpdateCoordinator`

```swift
public struct SelfUpdateCoordinator {
    public init(store: SignerConfigurationStore,
                releaseSource: ReleaseSource,
                currentVersion: String,
                userAgent: String,
                installedBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
                profileID: String? = nil,
                signingMode: SigningMode = .split,
                embeddedBundlePolicy: CompatibilityPolicy = .stripUnsupported,
                entitlementPolicy: CompatibilityPolicy = .stripUnsupported,
                transport: SigningTransport? = nil)

    // updating
    public func checkForUpdate() async throws -> ReleaseCandidate?
    public func requestSignedBuild(of candidate: ReleaseCandidate,
                                   target: SelfUpdateTarget = .installedApp) async throws -> SelfUpdateResult
    public func refresh(jobID: String, target: SelfUpdateTarget = .installedApp) async throws -> SelfUpdateResult

    // signature renewal
    public func installedSignature(bundle: Bundle = .main) -> InstalledSignature?
    public func needsRenewal(within days: Double = 3, bundle: Bundle = .main) -> Bool
    public func requestRenewal(target: SelfUpdateTarget = .installedApp) async throws -> SelfUpdateResult
}
```

### `SelfUpdateTarget` / `SelfUpdateResult`

```swift
public enum SelfUpdateTarget: Equatable {
    case installedApp                       // replaces the running app
    case sideBySideClone(bundleID: String)  // installs a second app alongside it
}

public struct SelfUpdateResult: Equatable {
    public let job: SigningJob
    public let links: DeliveryLinks?
    public let targetBundleIdentifier: String
    public let willReplaceInstalledApp: Bool   // false means installing adds a second icon
    public var isReadyToInstall: Bool
    public var installationURL: URL?
}
```

**Check `willReplaceInstalledApp` before showing an install prompt**, and say which one is about to happen.

### `InstalledSignature`

```swift
public struct InstalledSignature: Equatable {
    public let expiresAt: Date
    public let profileName, profileUUID, teamIdentifier, applicationIdentifier: String?
    public let isShortLived: Bool     // Apple's 7-day free-account profile
    public var isExpired: Bool
    public var daysRemaining: Double
    public func expires(within days: Double) -> Bool
}

public enum InstalledSignatureReader {
    public static func read(bundle: Bundle = .main) -> InstalledSignature?
}
```

When `isShortLived` is true, **do not offer renewal** — a 7-day profile cannot be renewed by any API, only reissued by Xcode.

---

## PrivateSignerUI

A convenience, not the contract. Build your own on Kit if you need different wording or layout.

```swift
public struct SignerUIContext {
    public init(keychain: SignerKeychainConfiguration,
                environments: [SignerEnvironment] = [.default],
                userAgent: String,
                defaultProfileID: String? = nil)
    public func store(for environment: SignerEnvironment) -> SignerConfigurationStore
}

public struct SignerConfigurationEditorView: View {
    public init(context: SignerUIContext,
                environment: SignerEnvironment = .default,
                onSaved: @escaping (SignerConfiguration, SignerEnvironment) -> Void)
}

public struct SigningJobsView: View {
    public init(context: SignerUIContext, environment: SignerEnvironment = .default)
}

public struct SelfUpdateView: View {
    public init(context: SignerUIContext,
                releaseSource: ReleaseSource,
                currentVersion: String,
                installedBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
                environment: SignerEnvironment = .default,
                signingMode: SigningMode = .split)
}
```

Ships Simplified Chinese and English, following the system language. iOS only.

---

## Error codes

Every error type carries a **stable `code`** alongside a **localized `errorDescription`**.
**Branch on `code`, display `errorDescription`, and never parse the message.**

### `SignerConfigurationError`

| code | Meaning |
|---|---|
| `invalid_worker_url` | Not a valid HTTPS URL, or credentials were embedded |
| `empty_token` | The token was empty |
| `keychain` | A Keychain operation failed, carrying its `OSStatus` |
| `invalid_stored_data` | The stored configuration could not be decoded |

### `SigningClientError`

| code | Meaning |
|---|---|
| `invalid_url` | The request URL could not be built, or is not HTTPS |
| `invalid_response` | The service returned data that could not be parsed |
| `unauthorized` | The token was rejected (HTTP 401/403) |
| `source_too_large` | Larger than 100 MiB |
| `server` | Any other HTTP error, with its status and the service's message |

### `SelfUpdateError`

| code | Meaning |
|---|---|
| `not_configured` | The signing service is not configured yet |
| `missing_bundle_identifier` | No Bundle ID is available |
| `unauthorized` | Authentication failed |
| `unexpected_bundle_identifier` | **The signed identity does not match the request; it must not be installed** |
| `invalid_manifest` | No valid HTTPS manifest was returned |
| `network` | Network failure |
| `signature_not_readable` | The installed signature's expiry could not be read |
| `current_version_source_unavailable` | No release matches the installed version, so it cannot be re-signed |

### `GitHubReleaseSourceError`

| code | Meaning |
|---|---|
| `invalid_current_version` | The installed version could not be parsed by the ordering |
| `invalid_response` | GitHub returned unrecognizable data |
| `no_valid_release` | No published release carried a recognizable version |
| `missing_asset` | **The release exists but no asset matched — the template is wrong, not the release** |
| `network` | Network failure |
