import XCTest
@testable import PrivateSignerKit

final class ServiceHealthTests: XCTestCase {
    private func makeClient(_ transport: RecordingTransport) -> SigningClient {
        SigningClient(
            configuration: SignerConfiguration(
                workerURL: URL(string: "https://signer.example.com")!,
                requestToken: "request-token"
            ),
            userAgent: "TestApp/1.0.0",
            transport: transport
        )
    }

    func testHealthProbeIsUnauthenticated() async throws {
        let transport = RecordingTransport(response: #"{"ok":true,"contract":"v2","version":"2.1.0"}"#)

        let health = try await makeClient(transport).health()

        XCTAssertEqual(health, ServiceHealth(ok: true, contract: "v2", version: "2.1.0"))
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/health")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testAWrongAddressIsReportedAsNotASignerRatherThanABadToken() async {
        let transport = RecordingTransport(response: #"{"hello":"world"}"#)

        let verification = await makeClient(transport).verifyConfiguration()

        XCTAssertEqual(verification, .notASigner)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testARejectedTokenIsReportedSeparatelyFromAWrongAddress() async {
        let transport = RecordingTransport(
            responses: [#"{"ok":true,"contract":"v2"}"#, #"{"message":"nope"}"#],
            statusCodes: [200, 401]
        )

        let verification = await makeClient(transport).verifyConfiguration()

        XCTAssertEqual(verification, .invalidToken)
        XCTAssertFalse(verification.isUsable)
        XCTAssertEqual(transport.requests.last?.url?.path, "/v2/projects")
    }

    func testAnUndeclaredContractStillCountsAsUsable() async {
        let transport = RecordingTransport(
            responses: [#"{"ok":true}"#, #"{"projects":[]}"#]
        )

        let verification = await makeClient(transport).verifyConfiguration()

        XCTAssertEqual(verification, .usableWithUndeclaredContract)
        XCTAssertTrue(verification.isUsable)
    }

    func testAnUnknownContractIsRefusedBeforeTheTokenIsSent() async {
        let transport = RecordingTransport(response: #"{"ok":true,"contract":"future"}"#)

        let verification = await makeClient(transport).verifyConfiguration()

        XCTAssertEqual(verification, .unsupportedContract("future"))
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testAnHTTPErrorFromHealthIsAWrongAddressNotAnOutage() async {
        let transport = RecordingTransport(responses: ["<html>404</html>"], statusCodes: [404])

        let verification = await makeClient(transport).verifyConfiguration()

        XCTAssertEqual(verification, .notASigner)
    }

    func testAFullyWorkingSignerIsUsable() async {
        let transport = RecordingTransport(
            responses: [#"{"ok":true,"contract":"v2"}"#, #"{"projects":[]}"#]
        )

        let verification = await makeClient(transport).verifyConfiguration()

        XCTAssertEqual(verification, .usable)
        XCTAssertEqual(verification.code, "usable")
        XCTAssertEqual(transport.requests.last?.url?.path, "/v2/projects")
    }
}
