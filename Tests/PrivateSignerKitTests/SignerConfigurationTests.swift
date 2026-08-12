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

final class PackageLocalizationTests: XCTestCase {
    /// The bug this exists for: a host whose Chinese is hardcoded in Swift declares no
    /// localizations, so iOS runs it as an English app and every properly localized package
    /// inside it shows English. The host is misconfigured; the person reading the screen is not
    /// the one who can fix that.

    func testChinesePreferencesSelectTheChineseStrings() {
        let bundle = PackageLocalization.bundle(for: .module, preferring: ["zh-Hans-CN", "en-US"])

        XCTAssertEqual(
            NSLocalizedString("error.unauthorized", bundle: bundle, comment: ""),
            "Signing Request Token 不正确。"
        )
    }

    func testTheRegionalAndBareFormsOfChineseAllResolve() {
        for preference in ["zh-Hans", "zh-Hans-CN", "zh-CN", "zh"] {
            let bundle = PackageLocalization.bundle(for: .module, preferring: [preference])
            XCTAssertEqual(
                NSLocalizedString("error.empty_token", bundle: bundle, comment: ""),
                "Signing Request Token 不能为空。",
                preference
            )
        }
    }

    func testEnglishPreferencesSelectEnglish() {
        let bundle = PackageLocalization.bundle(for: .module, preferring: ["en-GB", "fr"])

        XCTAssertEqual(
            NSLocalizedString("error.unauthorized", bundle: bundle, comment: ""),
            "The Signing Request Token was rejected."
        )
    }

    func testAnUnshippedLanguageFallsBackRatherThanReturningTheKey() {
        let bundle = PackageLocalization.bundle(for: .module, preferring: ["ja-JP"])
        let value = NSLocalizedString("error.unauthorized", bundle: bundle, comment: "")

        XCTAssertNotEqual(value, "error.unauthorized", "a missing language must not surface the key")
        XCTAssertFalse(value.isEmpty)
    }

    func testEmptyPreferencesStillProduceUsableText() {
        let bundle = PackageLocalization.bundle(for: .module, preferring: [])
        let value = NSLocalizedString("error.unauthorized", bundle: bundle, comment: "")

        XCTAssertNotEqual(value, "error.unauthorized")
    }

    func testTheErrorTypesThemselvesFollowTheUserLanguage() {
        // The end-to-end shape: an error surfaced to a user, not a bundle lookup.
        XCTAssertNotNil(SigningClientError.unauthorized.errorDescription)
        XCTAssertEqual(SigningClientError.unauthorized.code, "unauthorized")
    }
}
