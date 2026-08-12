import Foundation
import PrivateSignerKit

public enum GitHubReleaseSourceError: LocalizedError, Equatable {
    case invalidCurrentVersion(String)
    case invalidResponse
    case noValidRelease
    case missingAsset(String)
    case network(String)

    public var code: String {
        switch self {
        case .invalidCurrentVersion: return "invalid_current_version"
        case .invalidResponse: return "invalid_response"
        case .noValidRelease: return "no_valid_release"
        case .missingAsset: return "missing_asset"
        case .network: return "network"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion(let version):
            return SelfUpdateStrings.string("release.invalid_current_version", version)
        case .invalidResponse:
            return SelfUpdateStrings.string("release.invalid_response")
        case .noValidRelease:
            return SelfUpdateStrings.string("release.no_valid_release")
        case .missingAsset(let tag):
            return SelfUpdateStrings.string("release.missing_asset", tag)
        case .network(let message):
            return SelfUpdateStrings.string("release.network", message)
        }
    }
}

/// Discovers releases from the GitHub Releases API of a public repository.
///
/// Covers the common case: the project publishes an unsigned IPA as a release asset, and the
/// client signs that asset into itself.
public struct GitHubReleaseSource: ReleaseSource {
    /// `owner/name`.
    public let repository: String
    /// Asset filename with `{tag}` (the published tag, e.g. `v1.0.5-0006`) and/or `{version}`
    /// (the same tag without a leading `v`). Example: `MyApp-{tag}-unsigned.ipa`.
    public let assetNameTemplate: String
    public let includePrereleases: Bool
    public let ordering: VersionOrdering
    private let userAgent: String
    private let transport: SigningTransport
    private let pageSize: Int

    public init(
        repository: String,
        assetNameTemplate: String,
        userAgent: String,
        includePrereleases: Bool = false,
        ordering: VersionOrdering = BuildTaggedVersionOrdering(),
        pageSize: Int = 30,
        transport: SigningTransport? = nil
    ) {
        self.repository = repository
        self.assetNameTemplate = assetNameTemplate
        self.userAgent = userAgent
        self.includePrereleases = includePrereleases
        self.ordering = ordering
        self.pageSize = pageSize
        if let transport {
            self.transport = transport
        } else {
            let settings = URLSessionConfiguration.ephemeral
            settings.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            settings.timeoutIntervalForRequest = 8
            settings.timeoutIntervalForResource = 12
            self.transport = URLSession(configuration: settings)
        }
    }

    func fetchReleases() async throws -> [GitHubRelease] {
        guard let releasesURL = URL(
            string: "https://api.github.com/repos/\(repository)/releases?per_page=\(pageSize)"
        ) else {
            throw GitHubReleaseSourceError.invalidResponse
        }

        var request = URLRequest(url: releasesURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch {
            throw GitHubReleaseSourceError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubReleaseSourceError.invalidResponse
        }
        do {
            return try JSONDecoder().decode([GitHubRelease].self, from: data)
        } catch {
            throw GitHubReleaseSourceError.invalidResponse
        }
    }

    public func latestRelease(currentVersion: String) async throws -> ReleaseCandidate? {
        let releases = try await fetchReleases()

        // A release the ordering cannot parse is skipped, not guessed at.
        let candidates = releases.filter { release in
            guard !release.draft else { return false }
            guard includePrereleases || !release.prerelease else { return false }
            return ordering.compare(release.tagName, release.tagName) != nil
        }
        guard let latest = candidates.max(by: { left, right in
            ordering.compare(left.tagName, right.tagName) == .orderedAscending
        }) else {
            throw GitHubReleaseSourceError.noValidRelease
        }

        guard let comparison = ordering.compare(currentVersion, latest.tagName) else {
            throw GitHubReleaseSourceError.invalidCurrentVersion(currentVersion)
        }
        guard comparison == .orderedAscending else { return nil }

        let expectedName = Self.assetName(template: assetNameTemplate, tag: latest.tagName)
        guard let asset = latest.assets.first(where: { $0.name == expectedName }) else {
            throw GitHubReleaseSourceError.missingAsset(latest.tagName)
        }

        return ReleaseCandidate(
            version: latest.tagName,
            ipaURL: asset.browserDownloadURL,
            expectedSHA256: normalizedSHA256(asset.digest),
            notes: latest.body
        )
    }

    public func release(matching version: String) async throws -> ReleaseCandidate? {
        let releases = try await fetchReleases()
        // Matched through the ordering rather than by string equality, so `1.0.5-0006` and
        // `v1.0.5-0006` are recognized as the same release.
        guard let match = releases.first(where: { ordering.compare($0.tagName, version) == .orderedSame }) else {
            return nil
        }
        let expectedName = Self.assetName(template: assetNameTemplate, tag: match.tagName)
        guard let asset = match.assets.first(where: { $0.name == expectedName }) else {
            throw GitHubReleaseSourceError.missingAsset(match.tagName)
        }
        return ReleaseCandidate(
            version: match.tagName,
            ipaURL: asset.browserDownloadURL,
            expectedSHA256: normalizedSHA256(asset.digest),
            notes: match.body
        )
    }

    static func assetName(template: String, tag: String) -> String {
        var version = tag
        if version.hasPrefix("v") { version.removeFirst() }
        return template
            .replacingOccurrences(of: "{tag}", with: tag)
            .replacingOccurrences(of: "{version}", with: version)
    }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadURL: URL
        let digest: String?

        private enum CodingKeys: String, CodingKey {
            case name, digest
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let body: String?
    let assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case draft, prerelease, assets, body
        case tagName = "tag_name"
    }
}
