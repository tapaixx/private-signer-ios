import Foundation
import PrivateSignerKit

public enum SelfUpdateTarget: Equatable {
    case installedApp
    case sideBySideClone(bundleID: String)
}

public enum SelfUpdateError: LocalizedError, Equatable {
    case notConfigured
    case missingBundleIdentifier
    case unauthorized
    case unexpectedBundleIdentifier(expected: String, actual: String)
    case unexpectedProjectVersion(expected: String, actual: String)
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
        case .unexpectedProjectVersion: return "unexpected_project_version"
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
        case .unexpectedProjectVersion(let expected, let actual):
            return "Worker returned a version for project \(actual); expected \(expected)."
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
    public let targetBundleIdentifier: String
    public let willReplaceInstalledApp: Bool

    public var isReadyToInstall: Bool { links != nil }

    public var installationURL: URL? {
        guard let links else { return nil }
        return OTAInstallation.installationURL(manifestURL: links.manifestURL)
    }
}

/// Drives self-update from the Worker's project/version registry.
///
/// The coordinator never talks to GitHub and never sees an unsigned IPA URL. The only application
/// identity compiled into the host is `projectID`; release selection and profile policy live on
/// the Worker.
public struct SelfUpdateCoordinator {
    private let store: SignerConfigurationStore
    private let projectID: String
    private let installedBundleIdentifier: String
    private let currentVersion: String
    private let userAgent: String
    private let signingMode: SigningMode
    private let embeddedBundlePolicy: CompatibilityPolicy
    private let entitlementPolicy: CompatibilityPolicy
    private let transport: SigningTransport?

    public init(
        store: SignerConfigurationStore,
        projectID: String,
        currentVersion: String,
        userAgent: String,
        installedBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "",
        signingMode: SigningMode = .split,
        embeddedBundlePolicy: CompatibilityPolicy = .stripUnsupported,
        entitlementPolicy: CompatibilityPolicy = .stripUnsupported,
        transport: SigningTransport? = nil
    ) {
        self.store = store
        self.projectID = projectID
        self.currentVersion = currentVersion
        self.userAgent = userAgent
        self.installedBundleIdentifier = installedBundleIdentifier
        self.signingMode = signingMode
        self.embeddedBundlePolicy = embeddedBundlePolicy
        self.entitlementPolicy = entitlementPolicy
        self.transport = transport
    }

    /// The complete authoritative update response, including the profiles this project may use.
    public func updateStatus() async throws -> ProjectUpdate {
        let client = makeClient(try loadConfiguration())
        do {
            return try await client.projectUpdate(projectID: projectID, currentVersion: currentVersion)
        } catch SigningClientError.unauthorized {
            throw SelfUpdateError.unauthorized
        } catch {
            throw SelfUpdateError.network(error.localizedDescription)
        }
    }

    /// `nil` when the Worker says the installed build is already current.
    public func checkForUpdate() async throws -> SelfUpdateCandidate? {
        let update = try await updateStatus()
        guard update.updateAvailable, let candidate = update.targetVersion else { return nil }
        guard candidate.projectID == projectID else {
            throw SelfUpdateError.unexpectedProjectVersion(expected: projectID, actual: candidate.projectID)
        }
        return candidate
    }

    /// Safe profile metadata for this project. The Worker's default is marked with `isDefault`.
    public func availableProfiles() async throws -> [ProfileCapability] {
        let client = makeClient(try loadConfiguration())
        do {
            return try await client.profiles(projectID: projectID)
        } catch SigningClientError.unauthorized {
            throw SelfUpdateError.unauthorized
        } catch {
            throw SelfUpdateError.network(error.localizedDescription)
        }
    }

    public func requestSignedBuild(
        of candidate: SelfUpdateCandidate,
        target: SelfUpdateTarget = .installedApp,
        profileID: String? = nil
    ) async throws -> SelfUpdateResult {
        guard candidate.projectID == projectID else {
            throw SelfUpdateError.unexpectedProjectVersion(expected: projectID, actual: candidate.projectID)
        }
        let configuration = try loadConfiguration()
        let resolved = try resolvedBundleIdentifier(for: target)
        let client = makeClient(configuration)
        let options = ProjectSigningOptions(
            signingMode: signingMode,
            targetBundleIdentifier: resolved,
            profileID: profileID,
            keychainAccessGroups: store.authorizedAccessGroups,
            embeddedBundlePolicy: embeddedBundlePolicy,
            entitlementPolicy: entitlementPolicy
        )

        let created: SigningJob
        do {
            created = try await client.createProjectJob(
                projectID: projectID,
                versionID: candidate.versionID,
                options: options
            )
        } catch SigningClientError.unauthorized {
            throw SelfUpdateError.unauthorized
        } catch {
            throw SelfUpdateError.network(error.localizedDescription)
        }

        let job = (try? await client.job(id: created.jobID)) ?? created
        return try await finish(job: job, client: client, resolved: resolved)
    }

    // MARK: - Signature renewal

    public func installedSignature(bundle: Bundle = .main) -> InstalledSignature? {
        InstalledSignatureReader.read(bundle: bundle)
    }

    public func needsRenewal(within days: Double = 3, bundle: Bundle = .main) -> Bool {
        guard let signature = installedSignature(bundle: bundle) else { return false }
        return signature.expires(within: days)
    }

    /// Re-signs the exact ProjectVersion that is already installed.
    public func requestRenewal(
        target: SelfUpdateTarget = .installedApp,
        profileID: String? = nil
    ) async throws -> SelfUpdateResult {
        let client = makeClient(try loadConfiguration())
        let versions: [ProjectVersion]
        do {
            versions = try await client.projectVersions(projectID: projectID)
        } catch SigningClientError.unauthorized {
            throw SelfUpdateError.unauthorized
        } catch {
            throw SelfUpdateError.network(error.localizedDescription)
        }
        guard let candidate = versions.first(where: { $0.version == currentVersion && $0.isSignable }) else {
            throw SelfUpdateError.sourceForCurrentVersionUnavailable(currentVersion)
        }
        return try await requestSignedBuild(of: candidate, target: target, profileID: profileID)
    }

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
