import Foundation

public enum SigningJobStatus: Equatable, Decodable {
    case dispatching
    case queued
    case dispatchFailed
    case signing
    case following
    case completed
    case failed
    case cancelled
    /// A state this client does not know about. Treat it as neither active nor failed and keep
    /// polling; do not crash on a server that learned a new state.
    case unknown(String)

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = switch value {
        case "dispatching": .dispatching
        case "queued": .queued
        case "dispatch_failed": .dispatchFailed
        case "signing": .signing
        case "following": .following
        case "completed": .completed
        case "failed": .failed
        case "cancelled": .cancelled
        default: .unknown(value)
        }
    }

    public var rawValue: String {
        switch self {
        case .dispatching: "dispatching"
        case .queued: "queued"
        case .dispatchFailed: "dispatch_failed"
        case .signing: "signing"
        case .following: "following"
        case .completed: "completed"
        case .failed: "failed"
        case .cancelled: "cancelled"
        case .unknown(let value): value
        }
    }

    public var isActive: Bool {
        self == .dispatching || self == .queued || self == .signing || self == .following
    }

    public var isFailure: Bool {
        self == .failed || self == .dispatchFailed
    }
}

public struct SigningJob: Decodable, Identifiable, Equatable {
    public let jobID: String
    public let status: SigningJobStatus
    public let signingMode: SigningMode?
    public let source: String?
    public let createdAt: String?
    public let updatedAt: String?
    public let attempt: Int?
    public let errorCode: String?
    public let message: String?
    public let actualBundleIdentifier: String?
    public let actualVersion: String?
    public let actualBuild: String?
    public let actualTitle: String?
    public let finalSHA256: String?
    public let warnings: [String]?

    public var id: String { jobID }
    public var isActive: Bool { status.isActive }

    private enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status, source, attempt, message, warnings
        case signingMode = "signing_mode"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case errorCode = "error_code"
        case actualBundleIdentifier = "actual_bundle_id"
        case actualVersion = "actual_version"
        case actualBuild = "actual_build"
        case actualTitle = "actual_title"
        case finalSHA256 = "final_sha256"
    }
}

/// Renewable, purpose-bound URLs for one completed job. They expire quickly; request them again
/// rather than persisting them.
public struct DeliveryLinks: Decodable, Equatable {
    public let manifestURL: URL
    public let installURL: URL
    public let exportURL: URL
    public let expiresAt: String

    private enum CodingKeys: String, CodingKey {
        case manifestURL = "manifest_url"
        case installURL = "install_url"
        case exportURL = "export_url"
        case expiresAt = "expires_at"
    }
}
