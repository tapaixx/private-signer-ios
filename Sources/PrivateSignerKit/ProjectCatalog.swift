import Foundation

/// One project the authenticated principal is allowed to discover and sign.
public struct SigningProject: Decodable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String?
    public let homepageURL: URL?
    public let versionScheme: String
    public let defaultProfileID: String?
    public let syncEnabled: Bool
    public let lastSyncedAt: String?

    private enum CodingKeys: String, CodingKey {
        case id, name
        case bundleIdentifier = "bundle_id"
        case homepageURL = "homepage_url"
        case versionScheme = "version_scheme"
        case defaultProfileID = "default_profile_id"
        case syncEnabled = "sync_enabled"
        case lastSyncedAt = "last_synced_at"
    }
}

/// An immutable source release known by the Worker.
///
/// The SDK never receives the unsigned IPA download URL. `versionID` is the stable handle used
/// when asking the Worker to sign this exact source release.
public struct ProjectVersion: Decodable, Equatable, Identifiable {
    public let projectID: String
    public let versionID: String
    public let version: String
    public let tag: String
    public let releaseID: Int
    public let assetID: Int
    public let assetName: String
    public let size: Int
    public let sha256: String?
    public let digestStatus: String
    public let publishedAt: String
    public let state: String
    public let stateMessage: String?

    public var id: String { versionID }
    public var isSignable: Bool { state == "published" }

    private enum CodingKeys: String, CodingKey {
        case version, tag, size, state
        case projectID = "project_id"
        case versionID = "version_id"
        case releaseID = "release_id"
        case assetID = "asset_id"
        case assetName = "asset_name"
        case sha256
        case digestStatus = "digest_status"
        case publishedAt = "published_at"
        case stateMessage = "state_message"
    }
}

/// Safe profile metadata exposed to clients. Certificate material, UDIDs, and raw provisioning
/// profiles remain an Admin Console concern.
public struct ProfileCapability: Decodable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let expiresAt: String
    public let shortLived: Bool
    public let signable: Bool
    public let isDefault: Bool

    private enum CodingKeys: String, CodingKey {
        case id, signable
        case displayName = "display_name"
        case expiresAt = "expires_at"
        case shortLived = "short_lived"
        case isDefault = "is_default"
    }
}

/// The Worker's authoritative answer to an application's update check.
public struct ProjectUpdate: Decodable, Equatable {
    public let project: SigningProject
    public let currentVersion: String?
    public let currentKnown: Bool
    public let updateAvailable: Bool
    public let targetVersion: ProjectVersion?
    public let profiles: [ProfileCapability]

    private enum CodingKeys: String, CodingKey {
        case project, profiles
        case currentVersion = "current_version"
        case currentKnown = "current_known"
        case updateAvailable = "update_available"
        case targetVersion = "target_version"
    }
}
