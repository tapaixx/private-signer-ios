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

    func testBuildTaggedOrderingComparesBuildNumbersNumerically() {
        let ordering = BuildTaggedVersionOrdering()
        XCTAssertEqual(ordering.compare("v1.0.5-0009", "v1.0.5-0010"), .orderedAscending)
        XCTAssertEqual(ordering.compare("v1.0.5-0006", "v1.0.4-9999"), .orderedDescending)
        XCTAssertEqual(ordering.compare("v1.0.5-0006", "1.0.5-0006"), .orderedSame)
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
            projectID: "location-spoofer",
            currentVersion: "1.0.5-0008",
            userAgent: "TestApp/1.0.0",
            installedBundleIdentifier: installed
        )
    }

    func testInstalledAppTargetResolvesToTheRunningBundleIdentifier() throws {
        XCTAssertEqual(
            try makeCoordinator(installed: "com.example.app").resolvedBundleIdentifier(for: .installedApp),
            "com.example.app"
        )
    }

    func testCloneTargetResolvesToTheRequestedIdentifier() throws {
        XCTAssertEqual(
            try makeCoordinator(installed: "com.example.app")
                .resolvedBundleIdentifier(for: .sideBySideClone(bundleID: "  com.example.app.clone2  ")),
            "com.example.app.clone2"
        )
    }

    func testAnAppWithoutABundleIdentifierCannotSelfUpdate() {
        XCTAssertThrowsError(
            try makeCoordinator(installed: "  ").resolvedBundleIdentifier(for: .installedApp)
        ) { error in
            XCTAssertEqual(error as? SelfUpdateError, .missingBundleIdentifier)
        }
    }

    func testResultDistinguishesUpgradeFromSideBySideClone() {
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

private extension SigningJob {
    static func stub() -> SigningJob {
        let json = Data(#"{"job_id":"job-1","status":"queued"}"#.utf8)
        return try! JSONDecoder().decode(SigningJob.self, from: json)
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

    func testASevenDayProfileIsRecognizedAsShortLived() throws {
        let signature = try XCTUnwrap(
            InstalledSignatureReader.parse(wrapped(expiresInDays: 5, createdDaysAgo: 2))
        )
        XCTAssertTrue(signature.isShortLived)
    }

    func testExpiryWindowDrivesTheRenewalDecision() throws {
        let soon = try XCTUnwrap(InstalledSignatureReader.parse(wrapped(expiresInDays: 2)))
        let later = try XCTUnwrap(InstalledSignatureReader.parse(wrapped(expiresInDays: 30)))
        XCTAssertTrue(soon.expires(within: 3))
        XCTAssertFalse(later.expires(within: 3))
    }

    func testGarbageIsRejectedRatherThanGuessedAt() {
        XCTAssertNil(InstalledSignatureReader.parse(Data("not a provisioning profile".utf8)))
        XCTAssertNil(InstalledSignatureReader.parse(Data()))
    }
}
