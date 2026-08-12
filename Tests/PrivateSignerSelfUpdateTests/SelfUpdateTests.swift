import XCTest
import PrivateSignerKit
@testable import PrivateSignerSelfUpdate

final class VersionOrderingTests: XCTestCase {
    func testBuildTaggedVersionRoundTripsThePublishedTag() {
        let version = BuildTaggedVersion("v1.0.5-0006")

        XCTAssertEqual(version?.description, "1.0.5-0006")
        XCTAssertEqual(version?.tagName, "v1.0.5-0006")
        XCTAssertEqual(version?.build, 6)
    }

    func testBuildTaggedVersionRejectsTagsItCannotOrder() {
        XCTAssertNil(BuildTaggedVersion("1.0.5"))
        XCTAssertNil(BuildTaggedVersion("1.0-0001"))
        XCTAssertNil(BuildTaggedVersion("1.0.5-beta"))
        XCTAssertNil(BuildTaggedVersion("1.0.5-000000001"))
    }

    func testBuildTaggedOrderingComparesBuildNumbersNumerically() {
        let ordering = BuildTaggedVersionOrdering()

        XCTAssertEqual(ordering.compare("v1.0.5-0009", "v1.0.5-0010"), .orderedAscending)
        XCTAssertEqual(ordering.compare("v1.0.5-0006", "v1.0.4-9999"), .orderedDescending)
        XCTAssertEqual(ordering.compare("v1.0.5-0006", "1.0.5-0006"), .orderedSame)
        XCTAssertNil(ordering.compare("v1.0.5-0006", "not-a-version"))
    }

    func testDottedOrderingHandlesDifferingComponentCounts() {
        let ordering = DottedVersionOrdering()

        XCTAssertEqual(ordering.compare("1.2", "1.2.0"), .orderedSame)
        XCTAssertEqual(ordering.compare("1.2", "1.10"), .orderedAscending)
        XCTAssertEqual(ordering.compare("v2.0", "1.99.99"), .orderedDescending)
        XCTAssertNil(ordering.compare("1.2", "1.2-rc1"))
    }
}

final class GitHubReleaseSourceTests: XCTestCase {
    private let releasesJSON = """
    [
      {"tag_name":"v1.0.5-0004","draft":false,"prerelease":false,"body":"older",
       "assets":[{"name":"App-v1.0.5-0004-unsigned.ipa","browser_download_url":"https://example.com/4.ipa","digest":null}]},
      {"tag_name":"v1.0.5-0006","draft":false,"prerelease":false,"body":"newest",
       "assets":[{"name":"App-v1.0.5-0006-unsigned.ipa","browser_download_url":"https://example.com/6.ipa","digest":"sha256:\(String(repeating: "a", count: 64))"}]},
      {"tag_name":"v1.0.5-0007","draft":true,"prerelease":false,"body":"draft",
       "assets":[{"name":"App-v1.0.5-0007-unsigned.ipa","browser_download_url":"https://example.com/7.ipa","digest":null}]},
      {"tag_name":"nightly","draft":false,"prerelease":false,"body":"unparseable",
       "assets":[]}
    ]
    """

    private func makeSource(_ transport: RecordingTransport) -> GitHubReleaseSource {
        GitHubReleaseSource(
            repository: "owner/name",
            assetNameTemplate: "App-{tag}-unsigned.ipa",
            userAgent: "TestApp/1.0.0",
            transport: transport
        )
    }

    func testPicksTheNewestPublishedReleaseAndSkipsDraftsAndUnparseableTags() async throws {
        let transport = RecordingTransport(response: releasesJSON)

        let candidate = try await makeSource(transport).latestRelease(currentVersion: "v1.0.5-0004")

        XCTAssertEqual(candidate?.version, "v1.0.5-0006")
        XCTAssertEqual(candidate?.ipaURL, URL(string: "https://example.com/6.ipa"))
        XCTAssertEqual(candidate?.expectedSHA256, String(repeating: "a", count: 64))
        XCTAssertEqual(candidate?.notes, "newest")
    }

    func testReturnsNilWhenTheInstalledBuildIsAlreadyCurrent() async throws {
        let transport = RecordingTransport(response: releasesJSON)

        let candidate = try await makeSource(transport).latestRelease(currentVersion: "v1.0.5-0006")

        XCTAssertNil(candidate)
    }

    func testAnUnparseableInstalledVersionIsReportedRatherThanTreatedAsOld() async {
        let transport = RecordingTransport(response: releasesJSON)

        do {
            _ = try await makeSource(transport).latestRelease(currentVersion: "whatever")
            XCTFail("an unparseable installed version should be reported")
        } catch GitHubReleaseSourceError.invalidCurrentVersion(let value) {
            XCTAssertEqual(value, "whatever")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAMissingAssetIsReportedWithItsTag() async {
        let transport = RecordingTransport(response: releasesJSON)
        let source = GitHubReleaseSource(
            repository: "owner/name",
            assetNameTemplate: "Other-{tag}.ipa",
            userAgent: "TestApp/1.0.0",
            transport: transport
        )

        do {
            _ = try await source.latestRelease(currentVersion: "v1.0.5-0004")
            XCTFail("a missing asset should be reported")
        } catch GitHubReleaseSourceError.missingAsset(let tag) {
            XCTAssertEqual(tag, "v1.0.5-0006")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testAssetNameTemplateSubstitutesBothPlaceholders() {
        XCTAssertEqual(
            GitHubReleaseSource.assetName(template: "App-{tag}-unsigned.ipa", tag: "v1.2.3-0004"),
            "App-v1.2.3-0004-unsigned.ipa"
        )
        XCTAssertEqual(
            GitHubReleaseSource.assetName(template: "App_{version}.ipa", tag: "v1.2.3-0004"),
            "App_1.2.3-0004.ipa"
        )
    }

    func testRequestIdentifiesTheCallingApp() async throws {
        let transport = RecordingTransport(response: releasesJSON)

        _ = try await makeSource(transport).latestRelease(currentVersion: "v1.0.5-0004")

        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.github.com/repos/owner/name/releases?per_page=30")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "TestApp/1.0.0")
    }
}

final class SelfUpdateTargetTests: XCTestCase {
    private func makeCoordinator(installed: String) -> SelfUpdateCoordinator {
        SelfUpdateCoordinator(
            store: SignerConfigurationStore(
                keychain: SignerKeychainConfiguration(
                    service: "com.example.app.private-signer",
                    configurationAccessGroup: "TEAM.com.example.app"
                )
            ),
            releaseSource: StubReleaseSource(),
            currentVersion: "v1.0.0-0001",
            userAgent: "TestApp/1.0.0",
            installedBundleIdentifier: installed
        )
    }

    func testInstalledAppTargetResolvesToTheRunningBundleIdentifier() throws {
        let resolved = try makeCoordinator(installed: "com.example.app")
            .resolvedBundleIdentifier(for: .installedApp)

        XCTAssertEqual(resolved, "com.example.app")
    }

    func testCloneTargetResolvesToTheRequestedIdentifier() throws {
        let resolved = try makeCoordinator(installed: "com.example.app")
            .resolvedBundleIdentifier(for: .sideBySideClone(bundleID: "  com.example.app.clone2  "))

        XCTAssertEqual(resolved, "com.example.app.clone2")
    }

    func testAnAppWithoutABundleIdentifierCannotSelfUpdate() {
        XCTAssertThrowsError(
            try makeCoordinator(installed: "  ").resolvedBundleIdentifier(for: .installedApp)
        ) { error in
            XCTAssertEqual(error as? SelfUpdateError, .missingBundleIdentifier)
        }
    }

    func testWillReplaceInstalledAppIsFalseForACloneAndTrueForTheSameIdentifier() {
        let job = SigningJob.stub()

        let clone = SelfUpdateResult(
            job: job,
            links: nil,
            targetBundleIdentifier: "com.example.app.clone2",
            willReplaceInstalledApp: false
        )
        let upgrade = SelfUpdateResult(
            job: job,
            links: nil,
            targetBundleIdentifier: "com.example.app",
            willReplaceInstalledApp: true
        )

        XCTAssertFalse(clone.willReplaceInstalledApp)
        XCTAssertTrue(upgrade.willReplaceInstalledApp)
        XCTAssertFalse(clone.isReadyToInstall)
        XCTAssertNil(upgrade.installationURL)
    }
}

private struct StubReleaseSource: ReleaseSource {
    func latestRelease(currentVersion: String) async throws -> ReleaseCandidate? { nil }
}

private extension SigningJob {
    static func stub() -> SigningJob {
        let json = Data(#"{"job_id":"job-1","status":"queued"}"#.utf8)
        return try! JSONDecoder().decode(SigningJob.self, from: json)
    }
}

final class RecordingTransport: SigningTransport, @unchecked Sendable {
    private(set) var requests: [URLRequest] = []
    private var responses: [String]
    private var statusCodes: [Int]

    init(response: String) {
        responses = [response]
        statusCodes = []
    }

    init(responses: [String], statusCodes: [Int] = []) {
        self.responses = responses
        self.statusCodes = statusCodes
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let payload = responses.isEmpty ? "{}" : responses.removeFirst()
        let statusCode = statusCodes.isEmpty ? 200 : statusCodes.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(payload.utf8), response)
    }
}
