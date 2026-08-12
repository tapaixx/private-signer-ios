import Foundation

/// What the running app's own signature says about itself.
///
/// Read from the `embedded.mobileprovision` inside the app bundle. It is a CMS envelope around an
/// XML plist, and the plist is located inside the DER rather than parsed out of it — the same
/// technique the signing service uses server-side, and the only one available on iOS, where
/// `CMSDecoder` does not exist.
public struct InstalledSignature: Equatable {
    public let expiresAt: Date
    public let profileName: String?
    public let profileUUID: String?
    public let teamIdentifier: String?
    public let applicationIdentifier: String?
    /// Apple issues free-account profiles with a seven-day life. They cannot be renewed by this
    /// package or by any API — only reissued by Xcode — so a client that finds one should say so
    /// rather than offer a renewal that will fail.
    public let isShortLived: Bool

    public init(
        expiresAt: Date,
        profileName: String? = nil,
        profileUUID: String? = nil,
        teamIdentifier: String? = nil,
        applicationIdentifier: String? = nil,
        isShortLived: Bool = false
    ) {
        self.expiresAt = expiresAt
        self.profileName = profileName
        self.profileUUID = profileUUID
        self.teamIdentifier = teamIdentifier
        self.applicationIdentifier = applicationIdentifier
        self.isShortLived = isShortLived
    }

    public var isExpired: Bool { expiresAt <= Date() }

    public var daysRemaining: Double {
        expiresAt.timeIntervalSinceNow / 86_400
    }

    /// Whether the signature runs out soon enough to act on.
    public func expires(within days: Double) -> Bool {
        daysRemaining <= days
    }
}

public enum InstalledSignatureReader {
    /// Reads the running app's provisioning profile.
    ///
    /// Returns `nil` when there is no profile to read — a simulator build, or an app signed
    /// without one. That is not an error: a client with no profile simply has no expiry to act on.
    public static func read(bundle: Bundle = .main) -> InstalledSignature? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return parse(data)
    }

    static func parse(_ data: Data) -> InstalledSignature? {
        guard let plist = extractPlist(from: data) as? [String: Any] else { return nil }
        guard let expiration = plist["ExpirationDate"] as? Date else { return nil }

        let creation = plist["CreationDate"] as? Date
        let entitlements = plist["Entitlements"] as? [String: Any]
        let applicationIdentifier = entitlements?["application-identifier"] as? String
        let teamIdentifier = (entitlements?["com.apple.developer.team-identifier"] as? String)
            ?? applicationIdentifier?.split(separator: ".", maxSplits: 1).first.map(String.init)

        var shortLived = false
        if let creation {
            shortLived = expiration.timeIntervalSince(creation) <= 8 * 86_400
        }

        return InstalledSignature(
            expiresAt: expiration,
            profileName: plist["Name"] as? String,
            profileUUID: plist["UUID"] as? String,
            teamIdentifier: teamIdentifier,
            applicationIdentifier: applicationIdentifier,
            isShortLived: shortLived
        )
    }

    static func extractPlist(from data: Data) -> Any? {
        guard let start = data.range(of: Data("<?xml".utf8)) else { return nil }
        let terminator = Data("</plist>".utf8)
        guard let end = data.range(of: terminator, options: [], in: start.lowerBound..<data.endIndex) else {
            return nil
        }
        let slice = data[start.lowerBound..<end.upperBound]
        return try? PropertyListSerialization.propertyList(from: slice, options: [], format: nil)
    }
}
