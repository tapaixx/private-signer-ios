import XCTest
@testable import PrivateSignerKit

final class SignerConfigurationTests: XCTestCase {
    func testStoredTokenKeyStaysCompatibleWithClientsShippedBeforeThisPackage() throws {
        let legacyPayload = Data(#"{"workerURL":"https://signer.example.com","personalToken":"abc"}"#.utf8)

        let decoded = try JSONDecoder().decode(SignerConfiguration.self, from: legacyPayload)

        XCTAssertEqual(decoded.requestToken, "abc")
        XCTAssertEqual(decoded.workerURL, URL(string: "https://signer.example.com"))

        let reEncoded = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(decoded)
        ) as? [String: Any]
        XCTAssertEqual(reEncoded?["personalToken"] as? String, "abc")
        XCTAssertNil(reEncoded?["requestToken"])
    }

    func testDefaultEnvironmentAddsNoAccountSuffix() {
        XCTAssertEqual(SignerEnvironment.default.accountSuffix, "")
        XCTAssertEqual(SignerEnvironment(name: "staging")?.accountSuffix, ".staging")
    }

    func testEnvironmentNamesThatWouldMakeAmbiguousAccountsAreRejected() {
        XCTAssertNil(SignerEnvironment(name: ""))
        XCTAssertNil(SignerEnvironment(name: "with space"))
        XCTAssertNil(SignerEnvironment(name: "with.dot"))
        XCTAssertNil(SignerEnvironment(name: String(repeating: "a", count: 65)))
        XCTAssertEqual(SignerEnvironment(name: "  staging  ")?.name, "staging")
    }

    func testAuthorizedAccessGroupsPutTheStableGroupFirst() {
        let store = SignerConfigurationStore(
            keychain: SignerKeychainConfiguration(
                service: "com.example.app.private-signer",
                configurationAccessGroup: "TEAM.com.example.app",
                legacyAccessGroups: ["TEAM.com.example.old"]
            )
        )

        XCTAssertEqual(store.authorizedAccessGroups, ["TEAM.com.example.app", "TEAM.com.example.old"])
    }

    func testWorkerURLValidationRejectsEverythingThatCannotBeASigner() {
        XCTAssertThrowsError(try SignerConfigurationStore.validatedWorkerURL("http://signer.example.com"))
        XCTAssertThrowsError(try SignerConfigurationStore.validatedWorkerURL("https://user:pw@signer.example.com"))
        XCTAssertThrowsError(try SignerConfigurationStore.validatedWorkerURL("not a url"))
        XCTAssertThrowsError(try SignerConfigurationStore.validatedWorkerURL(""))
    }

    func testWorkerURLValidationNormalizesTrailingSlashQueryAndFragment() throws {
        let url = try SignerConfigurationStore.validatedWorkerURL("  https://signer.example.com/base/?a=1#x  ")

        XCTAssertEqual(url.absoluteString, "https://signer.example.com/base")
    }

    func testDigestNormalizationAcceptsGitHubPrefixAndRejectsAnythingElse() {
        let hex = String(repeating: "a", count: 64)

        XCTAssertEqual(normalizedSHA256("sha256:" + hex.uppercased()), hex)
        XCTAssertEqual(normalizedSHA256(hex), hex)
        XCTAssertNil(normalizedSHA256(nil))
        XCTAssertNil(normalizedSHA256("sha256:tooshort"))
        XCTAssertNil(normalizedSHA256(String(repeating: "z", count: 64)))
    }

    func testOTAInstallationURLWrapsOnlyHTTPSManifests() {
        let manifest = URL(string: "https://signer.example.com/v2/delivery/manifest?token=abc")!

        let installURL = OTAInstallation.installationURL(manifestURL: manifest)

        XCTAssertEqual(installURL?.scheme, "itms-services")
        XCTAssertTrue(installURL?.absoluteString.contains("action=download-manifest") == true)
        XCTAssertNil(OTAInstallation.installationURL(manifestURL: URL(string: "http://signer.example.com/m")!))
    }
}
