import Foundation

public struct SignerProject: Decodable, Equatable, Identifiable {
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

public enum ProjectVersionState: String, Decodable, Equatable {
    case published
    case disabled
    case sourceUnavailable = "source_unavailable"
    case sourceConflict = "source_conflict"
    case invalidVersion = "invalid_version"
}

public struct ProjectVersion: Decodable, Equatable, Identifiable {
    public let projectID: String
    public let versionID: String
    public let version: String
    public let tag: String
    public let assetName: String
    public let size: Int
    public let sha256: String?
    public let digestStatus: String
    public let publishedAt: String
    public let state: ProjectVersionState
    public let stateMessage: String?

    public var id: String { versionID }
    public var isSignable: Bool { state == .published }

    private enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case versionID = "version_id"
        case version, tag, size, sha256, state
        case assetName = "asset_name"
        case digestStatus = "digest_status"
        case publishedAt = "published_at"
        case stateMessage = "state_message"
    }
}

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

public struct ProjectUpdate: Decodable, Equatable {
    public let project: SignerProject
    public let currentVersion: String?
    public let currentKnown: Bool
    public let updateAvailable: Bool
    public let targetVersion: ProjectVersion?
    public let profiles: [ProfileCapability]

    public var defaultProfile: ProfileCapability? {
        profiles.first(where: { $0.isDefault })
    }

    private enum CodingKeys: String, CodingKey {
        case project, profiles
        case currentVersion = "current_version"
        case currentKnown = "current_known"
        case updateAvailable = "update_available"
        case targetVersion = "target_version"
    }
}
