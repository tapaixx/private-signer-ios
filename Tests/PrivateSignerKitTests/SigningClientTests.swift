import XCTest
@testable import PrivateSignerKit

final class SigningClientTests: XCTestCase {
    private func makeClient(
        transport: RecordingTransport,
        workerURL: String = "https://signer.example.com"
    ) -> SigningClient {
        SigningClient(
            configuration: SignerConfiguration(
                workerURL: URL(string: workerURL)!,
                requestToken: "request-token"
            ),
            userAgent: "TestApp/1.0.0",
            transport: transport
        )
    }

    func testCreateURLJobUsesV2BearerContractAndCompleteOptions() async throws {
        let transport = RecordingTransport(response: """
        {"job_id":"00000000-0000-4000-8000-000000000001","status":"queued","signing_mode":"split"}
        """)
        let client = makeClient(transport: transport)
        let options = SigningOptions(
            signingMode: .split,
            targetBundleIdentifier: "com.example.clone",
            profileID: "personal-main",
            keychainAccessGroups: ["TEAM.com.example.clone", "TEAM.com.example.legacy"],
            embeddedBundlePolicy: .requireAll,
            entitlementPolicy: .stripUnsupported
        )

        let job = try await client.createURLJob(
            sourceURL: URL(string: "https://downloads.example/App.ipa")!,
            options: options
        )

        XCTAssertEqual(job.jobID, "00000000-0000-4000-8000-000000000001")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/v2/sign/jobs")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer request-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "TestApp/1.0.0")
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["source_url"] as? String, "https://downloads.example/App.ipa")
        XCTAssertEqual(payload["signing_mode"] as? String, "split")
        XCTAssertEqual(payload["target_bundle_id"] as? String, "com.example.clone")
        XCTAssertEqual(payload["profile_id"] as? String, "personal-main")
        XCTAssertEqual(payload["embedded_bundle_policy"] as? String, "require_all")
        XCTAssertEqual(payload["entitlement_policy"] as? String, "strip_unsupported")
        XCTAssertEqual(
            payload["keychain_access_groups"] as? [String],
            ["TEAM.com.example.clone", "TEAM.com.example.legacy"]
        )
    }

    func testUploadSessionUsesEightMiBPartsBeforeCreatingJob() async throws {
        let transport = RecordingTransport(responses: [
            "{\"upload_id\":\"00000000-0000-4000-8000-000000000002\",\"part_size\":8388608,\"max_bytes\":104857600,\"expires_at\":\"2026-08-12T00:00:00Z\"}",
            "{\"upload_id\":\"00000000-0000-4000-8000-000000000002\",\"part_number\":1,\"etag\":\"etag-1\"}",
            "{\"upload_id\":\"00000000-0000-4000-8000-000000000002\",\"status\":\"completed\",\"filename\":\"Local.ipa\"}",
            "{\"job_id\":\"00000000-0000-4000-8000-000000000003\",\"status\":\"queued\",\"signing_mode\":\"split\"}",
        ])
        let client = makeClient(transport: transport)
        let bytes = Data("fake-ipa!".utf8)

        let job = try await client.uploadAndCreateJob(
            filename: "Local.ipa",
            data: bytes,
            options: SigningOptions()
        )

        XCTAssertEqual(job.jobID, "00000000-0000-4000-8000-000000000003")
        XCTAssertEqual(transport.requests.map { $0.url?.path }, [
            "/v2/uploads",
            "/v2/uploads/00000000-0000-4000-8000-000000000002/parts/1",
            "/v2/uploads/00000000-0000-4000-8000-000000000002/complete",
            "/v2/sign/jobs",
        ])
        XCTAssertEqual(transport.requests[1].value(forHTTPHeaderField: "Content-Length"), "9")
    }

    func testUploadRejectsUnsafeWorkerPartSizeBeforeReadingOrSendingParts() async throws {
        for invalidPartSize in [0, SigningClient.maximumPartBytes + 1] {
            let transport = RecordingTransport(response: """
            {"upload_id":"00000000-0000-4000-8000-000000000004","part_size":\(invalidPartSize),"max_bytes":104857600,"expires_at":"2026-08-12T00:00:00Z"}
            """)
            let client = makeClient(transport: transport)

            do {
                _ = try await client.uploadAndCreateJob(
                    filename: "Local.ipa",
                    data: Data("fake-ipa".utf8),
                    options: SigningOptions()
                )
                XCTFail("unsafe part size should be rejected")
            } catch SigningClientError.invalidResponse {
                XCTAssertEqual(transport.requests.count, 1)
            }
        }
    }

    func testHistoryFollowsEveryCursorPage() async throws {
        let transport = RecordingTransport(responses: [
            "{\"jobs\":[{\"job_id\":\"00000000-0000-4000-8000-000000000010\",\"status\":\"completed\"}],\"next_cursor\":\"page-2\"}",
            "{\"jobs\":[{\"job_id\":\"00000000-0000-4000-8000-000000000011\",\"status\":\"failed\"}],\"next_cursor\":null}",
        ])
        let client = makeClient(transport: transport)

        let jobs = try await client.history()

        XCTAssertEqual(jobs.map(\.jobID), [
            "00000000-0000-4000-8000-000000000010",
            "00000000-0000-4000-8000-000000000011",
        ])
        XCTAssertEqual(transport.requests[1].url?.query, "cursor=page-2")
    }

    func testHistoryRejectsARepeatingCursorInsteadOfLoopingForever() async {
        let page = "{\"jobs\":[{\"job_id\":\"00000000-0000-4000-8000-000000000012\",\"status\":\"completed\"}],\"next_cursor\":\"same\"}"
        let transport = RecordingTransport(responses: Array(repeating: page, count: 4))
        let client = makeClient(transport: transport)

        do {
            _ = try await client.history()
            XCTFail("a repeating cursor should be rejected")
        } catch SigningClientError.invalidResponse {
            XCTAssertEqual(transport.requests.count, 2)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testNonHTTPSWorkerURLIsRefusedBeforeSending() async {
        let transport = RecordingTransport(response: "{}")
        let client = makeClient(transport: transport, workerURL: "http://signer.example.com")

        do {
            _ = try await client.job(id: "any")
            XCTFail("a plaintext Worker URL should be refused")
        } catch SigningClientError.invalidURL {
            XCTAssertTrue(transport.requests.isEmpty)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testUnauthorizedIsReportedSeparatelyFromOtherServerErrors() async {
        let transport = RecordingTransport(
            responses: ["{\"message\":\"nope\"}"],
            statusCodes: [401]
        )
        let client = makeClient(transport: transport)

        do {
            _ = try await client.job(id: "any")
            XCTFail("401 should surface as unauthorized")
        } catch SigningClientError.unauthorized {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testServerErrorCarriesStatusAndMessage() async {
        let transport = RecordingTransport(
            responses: ["{\"message\":\"source too large\"}"],
            statusCodes: [413]
        )
        let client = makeClient(transport: transport)

        do {
            _ = try await client.job(id: "any")
            XCTFail("413 should surface as a server error")
        } catch SigningClientError.server(let status, let message) {
            XCTAssertEqual(status, 413)
            XCTAssertEqual(message, "source too large")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
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
