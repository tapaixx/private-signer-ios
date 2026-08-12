import Foundation
import PrivateSignerKit

/// What a self-update run is aiming at.
///
/// The two cases exist because they have different outcomes on the home screen, and a plain
/// `String?` parameter cannot say which one the caller meant. Passing a different Bundle ID by
/// accident installs a second copy of the app while the old one keeps running — the caller has
/// to name that outcome to get it.
public enum SelfUpdateTarget: Equatable {
    /// Replace the running app. The signed build keeps the installed Bundle ID, so iOS treats it
    /// as an upgrade.
    case installedApp
    /// Install a separately identified copy next to the running app. Used for multi-instance
    /// setups and for testing a build without losing the working one.
    case sideBySideClone(bundleID: String)
}

public enum SelfUpdateError: LocalizedError, Equatable {
    case notConfigured
    case missingBundleIdentifier
    case unauthorized
    case unexpectedBundleIdentifier(expected: String, actual: String)
    case invalidManifest
    case network(String)
    case signatureNotReadable
    case sourceForCurrentVersionUnavailable(String)

    public var code: String {
        switch self {
        case .notConfigured: return "not_configured"
        case .missingBundleIdentifier: return "missing_bundle_identifier"
        case .unauthorized: return "unauthorized"
        case .unexpectedBundleIdentifier: return "unexpected_bundle_identifier"
        case .invalidManifest: return "invalid_manifest"
        case .network: return "network"
        case .signatureNotReadable: return "signature_not_readable"
        case .sourceForCurrentVersionUnavailable: return "current_version_source_unavailable"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            return SelfUpdateStrings.string("update.not_configured")
        case .missingBundleIdentifier:
            return SelfUpdateStrings.string("update.missing_bundle_identifier")
        case .unauthorized:
            return SelfUpdateStrings.string("update.unauthorized")
        case .unexpectedBundleIdentifier(let expected, let actual):
            return SelfUpdateStrings.string("update.unexpected_bundle_identifier", expected, actual)
        case .invalidManifest:
            return SelfUpdateStrings.string("update.invalid_manifest")
        case .network(let message):
            return SelfUpdateStrings.string("update.network", message)
        case .signatureNotReadable:
            return SelfUpdateStrings.string("update.signature_not_readable")
        case .sourceForCurrentVersionUnavailable(let version):
            return SelfUpdateStrings.string("update.current_version_source_unavailable", version)
        }
    }
}

public struct SelfUpdateResult: Equatable {
    public let job: SigningJob
    public let links: DeliveryLinks?
    /// The Bundle ID the signed build will carry.
    public let targetBundleIdentifier: String
    /// `false` means installing this build adds a second app instead of upgrading this one.
    public let willReplaceInstalledApp: Bool

    public var isReadyToInstall: Bool { links != nil }

    /// The `itms-services://` URL to open once the job completes.
    public var installationURL: URL? {
        guard let links else { return nil }
        return OTAInstallation.installationURL(manifestURL: links.manifestURL)
    }
}

/// Drives the whole self-update flow: discover a newer build, request a signed copy of it, poll,
/// and hand back an installable link.
public struct SelfUpdateCoordinator {
    private let store: SignerConfigurationStore
    private let releaseSource: ReleaseSource
    private let installedBundleIdentifier: String
    private let currentVersion: String
    private let userAgent: String
    private let profileID: String?
    private let signingMode: SigningMode
    private let embeddedBundlePolicy: CompatibilityPolicy
    private let entitlementPolicy: CompatibilityPolicy
    private let transport: SigningTransport?

    public init(
        store: SignerConfigurationStore,
        releaseSource: ReleaseSource,
        currentVersion: String,
        userAgent: String,
        installedBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
        profileID: String? = nil,
        signingMode: SigningMode = .split,
        embeddedBundlePolicy: CompatibilityPolicy = .stripUnsupported,
        entitlementPolicy: CompatibilityPolicy = .stripUnsupported,
        transport: SigningTransport? = nil
    ) {
        self.store = store
        self.releaseSource = releaseSource
        self.currentVersion = currentVersion
        self.userAgent = userAgent
        self.installedBundleIdentifier = installedBundleIdentifier
        self.profileID = profileID
        self.signingMode = signingMode
        self.embeddedBundlePolicy = embeddedBundlePolicy
        self.entitlementPolicy = entitlementPolicy
        self.transport = transport
    }

    /// `nil` when the installed build is already current.
    public func checkForUpdate() async throws -> ReleaseCandidate? {
        try await releaseSource.latestRelease(currentVersion: currentVersion)
    }

    /// Submits a Signing Request for `candidate` and reports the job's state right away. The job
    /// is usually still queued at this point — poll with ``refresh(jobID:target:)``.
    public func requestSignedBuild(
        of candidate: ReleaseCandidate,
        target: SelfUpdateTarget = .installedApp
    ) async throws -> SelfUpdateResult {
        let configuration = try loadConfiguration()
        let resolved = try resolvedBundleIdentifier(for: target)
        let client = makeClient(configuration)

        let options = SigningOptions(
            signingMode: signingMode,
            targetBundleIdentifier: resolved,
            profileID: profileID,
            // A clone that does not carry the Stable Configuration Group cannot read the Worker
            // URL and token it was signed with, so every signed build requests the same groups.
            keychainAccessGroups: store.authorizedAccessGroups,
            embeddedBundlePolicy: embeddedBundlePolicy,
            entitlementPolicy: entitlementPolicy,
            expectedSHA256: candidate.expectedSHA256
        )

        let created: SigningJob
        do {
            created = try await client.createURLJob(sourceURL: candidate.ipaURL, options: options)
        } catch SigningClientError.unauthorized {
            throw SelfUpdateError.unauthorized
        } catch {
            throw SelfUpdateError.network(error.localizedDescription)
        }

        let job = (try? await client.job(id: created.jobID)) ?? created
        return try await finish(job: job, client: client, resolved: resolved)
    }

    // MARK: - Signature renewal

    /// The running app's own signature, or `nil` when there is no provisioning profile to read.
    public func installedSignature(bundle: Bundle = .main) -> InstalledSignature? {
        InstalledSignatureReader.read(bundle: bundle)
    }

    /// Whether the installed signature runs out soon enough to act on.
    ///
    /// Deliberately separate from ``checkForUpdate()``. A signature expiring is not a new version,
    /// and folding it into update discovery would make that method return a candidate whose
    /// version equals the installed one — breaking every caller that reads a non-nil result as
    /// "there is something newer".
    public func needsRenewal(within days: Double = 3, bundle: Bundle = .main) -> Bool {
        guard let signature = installedSignature(bundle: bundle) else { return false }
        return signature.expires(within: days)
    }

    /// Re-signs the version that is already installed, because its signature is about to expire.
    ///
    /// This installs the same build again rather than a newer one. It is the only thing that
    /// keeps an app signed with a seven-day free-account profile usable without a Mac — and even
    /// then only while that profile itself is still valid.
    public func requestRenewal(target: SelfUpdateTarget = .installedApp) async throws -> SelfUpdateResult {
        guard let candidate = try await releaseSource.release(matching: currentVersion) else {
            throw SelfUpdateError.sourceForCurrentVersionUnavailable(currentVersion)
        }
        return try await requestSignedBuild(of: candidate, target: target)
    }

    /// Polls one job and re-checks the identity guarantee.
    public func refresh(jobID: String, target: SelfUpdateTarget = .installedApp) async throws -> SelfUpdateResult {
        let configuration = try loadConfiguration()
        let resolved = try resolvedBundleIdentifier(for: target)
        let client = makeClient(configuration)
        let job: SigningJob
        do {
            job = try await client.job(id: jobID)
        } catch SigningClientError.unauthorized {
            throw SelfUpdateError.unauthorized
        } catch {
            throw SelfUpdateError.network(error.localizedDescription)
        }
        return try await finish(job: job, client: client, resolved: resolved)
    }

    private func finish(
        job: SigningJob,
        client: SigningClient,
        resolved: String
    ) async throws -> SelfUpdateResult {
        // Checked before the links are handed out: a build whose identity drifted must never
        // reach an install prompt.
        if let returned = job.actualBundleIdentifier, returned != resolved {
            throw SelfUpdateError.unexpectedBundleIdentifier(expected: resolved, actual: returned)
        }

        var links: DeliveryLinks?
        if job.status == .completed {
            do {
                links = try await client.links(jobID: job.jobID)
            } catch SigningClientError.unauthorized {
                throw SelfUpdateError.unauthorized
            } catch {
                throw SelfUpdateError.network(error.localizedDescription)
            }
            guard links?.manifestURL.scheme?.lowercased() == "https" else {
                throw SelfUpdateError.invalidManifest
            }
        }

        return SelfUpdateResult(
            job: job,
            links: links,
            targetBundleIdentifier: resolved,
            willReplaceInstalledApp: resolved == installedBundleIdentifier
        )
    }

    private func makeClient(_ configuration: SignerConfiguration) -> SigningClient {
        SigningClient(configuration: configuration, userAgent: userAgent, transport: transport)
    }

    private func loadConfiguration() throws -> SignerConfiguration {
        guard let configuration = try store.load() else { throw SelfUpdateError.notConfigured }
        return configuration
    }

    func resolvedBundleIdentifier(for target: SelfUpdateTarget) throws -> String {
        switch target {
        case .installedApp:
            let trimmed = installedBundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw SelfUpdateError.missingBundleIdentifier }
            return trimmed
        case .sideBySideClone(let bundleID):
            let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw SelfUpdateError.missingBundleIdentifier }
            return trimmed
        }
    }
}
