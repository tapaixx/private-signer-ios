import Foundation

/// One resignable build that a client could upgrade to, or install alongside itself.
public struct ReleaseCandidate: Equatable {
    /// The version string as the source publishes it, e.g. `v1.0.5-0006`.
    public let version: String
    /// HTTPS location of the unsigned/resignable IPA.
    public let ipaURL: URL
    /// Bare lowercase 64-character hex, or `nil` when the source cannot vouch for the bytes.
    public let expectedSHA256: String?
    public let notes: String?

    public init(version: String, ipaURL: URL, expectedSHA256: String? = nil, notes: String? = nil) {
        self.version = version
        self.ipaURL = ipaURL
        self.expectedSHA256 = expectedSHA256
        self.notes = notes
    }
}

/// Where a client discovers its own newer builds.
///
/// This is the whole application-specific surface of self-updating: implement one method and the
/// rest of the flow — signing, polling, delivery, OTA install — is identical for every app.
public protocol ReleaseSource {
    /// Returns the newest candidate that is strictly newer than `currentVersion`, or `nil` when
    /// the client is already current.
    ///
    /// Implementations own version comparison, because only they know their own version format.
    func latestRelease(currentVersion: String) async throws -> ReleaseCandidate?
}
