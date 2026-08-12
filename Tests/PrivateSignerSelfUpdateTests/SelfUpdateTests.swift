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

struct StubReleaseSource: ReleaseSource {
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

final class InstalledSignatureTests: XCTestCase {
    private func wrapped(
        expiresInDays: Double,
        createdDaysAgo: Double = 65,
        name: String = "Personal Profile",
        team: String = "4JJ849C5Q2"
    ) -> Data {
        let plist: [String: Any] = [
            "Name": name,
            "UUID": "11111111-2222-3333-4444-555555555555",
            "ExpirationDate": Date().addingTimeInterval(expiresInDays * 86_400),
            "CreationDate": Date().addingTimeInterval(-createdDaysAgo * 86_400),
            "Entitlements": [
                "application-identifier": "\(team).com.example.app",
                "com.apple.developer.team-identifier": team,
            ],
        ]
        let payload = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        // A CMS envelope wraps the plist; the parser has to find it rather than assume an offset.
        var data = Data([0x30, 0x82, 0x0A, 0xBC, 0x06, 0x09])
        data.append(Data(repeating: 0, count: 48))
        data.append(payload)
        data.append(Data(repeating: 0, count: 96))
        return data
    }

    func testReadsTheProfileOutOfACMSEnvelope() throws {
        let signature = try XCTUnwrap(InstalledSignatureReader.parse(wrapped(expiresInDays: 200)))

        XCTAssertEqual(signature.profileName, "Personal Profile")
        XCTAssertEqual(signature.teamIdentifier, "4JJ849C5Q2")
        XCTAssertEqual(signature.applicationIdentifier, "4JJ849C5Q2.com.example.app")
        XCTAssertFalse(signature.isExpired)
        XCTAssertEqual(signature.daysRemaining, 200, accuracy: 0.1)
    }

    func testASevenDayProfileIsRecognizedAsUnrenewable() throws {
        let signature = try XCTUnwrap(
            InstalledSignatureReader.parse(wrapped(expiresInDays: 5, createdDaysAgo: 2))
        )

        XCTAssertTrue(signature.isShortLived)
    }

    func testAYearLongProfileIsNotShortLived() throws {
        let signature = try XCTUnwrap(InstalledSignatureReader.parse(wrapped(expiresInDays: 200)))

        XCTAssertFalse(signature.isShortLived)
    }

    func testExpiryWindowDrivesTheRenewalDecision() throws {
        let soon = try XCTUnwrap(InstalledSignatureReader.parse(wrapped(expiresInDays: 2)))
        let later = try XCTUnwrap(InstalledSignatureReader.parse(wrapped(expiresInDays: 30)))

        XCTAssertTrue(soon.expires(within: 3))
        XCTAssertFalse(later.expires(within: 3))
    }

    func testAnExpiredSignatureIsReportedAsExpired() throws {
        let signature = try XCTUnwrap(InstalledSignatureReader.parse(wrapped(expiresInDays: -1)))

        XCTAssertTrue(signature.isExpired)
        XCTAssertLessThan(signature.daysRemaining, 0)
    }

    func testGarbageIsRejectedRatherThanGuessedAt() {
        XCTAssertNil(InstalledSignatureReader.parse(Data("not a provisioning profile".utf8)))
        XCTAssertNil(InstalledSignatureReader.parse(Data()))
    }

    func testAProfileWithoutAnExpiryIsRejected() throws {
        let payload = try PropertyListSerialization.data(
            fromPropertyList: ["Name": "No expiry"], format: .xml, options: 0
        )

        XCTAssertNil(InstalledSignatureReader.parse(payload))
    }

    func testAMissingProfileIsNotAnError() {
        XCTAssertNil(InstalledSignatureReader.read(bundle: Bundle(for: InstalledSignatureTests.self)))
    }
}

final class SignatureRenewalTests: XCTestCase {
    private func coordinator(source: ReleaseSource) -> SelfUpdateCoordinator {
        SelfUpdateCoordinator(
            store: SignerConfigurationStore(
                keychain: SignerKeychainConfiguration(
                    service: "com.example.app.private-signer",
                    configurationAccessGroup: "TEAM.com.example.app"
                )
            ),
            releaseSource: source,
            currentVersion: "v1.0.5-0006",
            userAgent: "TestApp/1.0.0",
            installedBundleIdentifier: "com.example.app"
        )
    }

    func testASourceThatCannotFindItsOwnVersionDisablesRenewalRatherThanFailingOddly() async {
        do {
            _ = try await coordinator(source: StubReleaseSource()).requestRenewal()
            XCTFail("renewal should report that there is nothing to re-sign from")
        } catch let error as SelfUpdateError {
            XCTAssertEqual(error.code, "current_version_source_unavailable")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testGitHubSourceFindsTheInstalledVersionForReSigning() async throws {
        let json = """
        [{"tag_name":"v1.0.5-0006","draft":false,"prerelease":false,"body":"current",
          "assets":[{"name":"App-v1.0.5-0006-unsigned.ipa","browser_download_url":"https://example.com/6.ipa","digest":null}]}]
        """
        let source = GitHubReleaseSource(
            repository: "owner/name",
            assetNameTemplate: "App-{tag}-unsigned.ipa",
            userAgent: "TestApp/1.0.0",
            transport: RecordingTransport(response: json)
        )

        let candidate = try await source.release(matching: "v1.0.5-0006")

        XCTAssertEqual(candidate?.version, "v1.0.5-0006")
        XCTAssertEqual(candidate?.ipaURL, URL(string: "https://example.com/6.ipa"))
    }

    func testTheVersionMatchIgnoresALeadingV() async throws {
        let json = """
        [{"tag_name":"v1.0.5-0006","draft":false,"prerelease":false,"body":null,
          "assets":[{"name":"App-v1.0.5-0006-unsigned.ipa","browser_download_url":"https://example.com/6.ipa","digest":null}]}]
        """
        let source = GitHubReleaseSource(
            repository: "owner/name",
            assetNameTemplate: "App-{tag}-unsigned.ipa",
            userAgent: "TestApp/1.0.0",
            transport: RecordingTransport(response: json)
        )

        XCTAssertNotNil(try await source.release(matching: "1.0.5-0006"))
    }

    /// The invariant 0.1.1 callers depend on: a non-nil candidate means a newer version exists.
    /// Renewal must never make `checkForUpdate` return the version already installed.
    func testRenewalIsNotReportedAsAnUpdate() async throws {
        let json = """
        [{"tag_name":"v1.0.5-0006","draft":false,"prerelease":false,"body":null,
          "assets":[{"name":"App-v1.0.5-0006-unsigned.ipa","browser_download_url":"https://example.com/6.ipa","digest":null}]}]
        """
        let source = GitHubReleaseSource(
            repository: "owner/name",
            assetNameTemplate: "App-{tag}-unsigned.ipa",
            userAgent: "TestApp/1.0.0",
            transport: RecordingTransport(response: json)
        )

        let update = try await source.latestRelease(currentVersion: "v1.0.5-0006")
        let renewal = try await source.release(matching: "v1.0.5-0006")

        XCTAssertNil(update, "the installed version must not be offered as an update")
        XCTAssertNotNil(renewal, "but it must still be findable for re-signing")
    }
}
