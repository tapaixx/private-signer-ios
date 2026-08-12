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

    func testCreateProjectJobUsesV2IdentifiersAndOnlySigningOptions() async throws {
        let transport = RecordingTransport(response: """
        {"job_id":"00000000-0000-4000-8000-000000000001","status":"queued","signing_mode":"split"}
        """)
        let client = makeClient(transport: transport)
        let options = ProjectSigningOptions(
            signingMode: .split,
            targetBundleIdentifier: "com.example.clone",
            profileID: "profile-set-a",
            keychainAccessGroups: ["TEAM.com.example.clone"],
            embeddedBundlePolicy: .requireAll,
            entitlementPolicy: .stripUnsupported
        )

        let job = try await client.createProjectJob(
            projectID: "location-spoofer",
            versionID: "1.0.5-0010",
            options: options
        )

        XCTAssertEqual(job.jobID, "00000000-0000-4000-8000-000000000001")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/v2/sign/jobs")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer request-token")
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(payload["project_id"] as? String, "location-spoofer")
        XCTAssertEqual(payload["version_id"] as? String, "1.0.5-0010")
        XCTAssertEqual(payload["profile_id"] as? String, "profile-set-a")
        XCTAssertEqual(payload["target_bundle_id"] as? String, "com.example.clone")
        XCTAssertNil(payload["source_url"])
        XCTAssertNil(payload["expected_sha256"])
        XCTAssertNil(payload["expected_version"])
        XCTAssertNil(payload["expected_build"])
    }

    func testProjectUpdateUsesWorkerCatalogAndDecodesProfileCapabilities() async throws {
        let transport = RecordingTransport(response: """
        {
          "project": {
            "id":"location-spoofer",
            "name":"Location Spoofer",
            "bundle_id":"com.example.location",
            "homepage_url":null,
            "version_scheme":"build-tagged",
            "default_profile_id":"profile-set-a",
            "sync_enabled":true,
            "last_synced_at":"2026-08-12T10:00:00Z"
          },
          "current_version":"1.0.5-0009",
          "current_known":true,
          "update_available":true,
          "target_version": {
            "project_id":"location-spoofer",
            "version_id":"1.0.5-0010",
            "version":"1.0.5-0010",
            "tag":"v1.0.5-0010",
            "release_id":12,
            "asset_id":34,
            "asset_name":"Location-Spoofer-v1.0.5-0010-unsigned.ipa",
            "size":1234,
            "sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "digest_status":"verified",
            "published_at":"2026-08-12T10:01:00Z",
            "state":"published"
          },
          "profiles":[{
            "id":"profile-set-a",
            "display_name":"Personal iPhone",
            "expires_at":"2026-08-19T00:00:00Z",
            "short_lived":true,
            "signable":true,
            "is_default":true
          }]
        }
        """)
        let client = makeClient(transport: transport)

        let update = try await client.projectUpdate(projectID: "location-spoofer", currentVersion: "1.0.5-0009")

        XCTAssertTrue(update.updateAvailable)
        XCTAssertEqual(update.targetVersion?.versionID, "1.0.5-0010")
        XCTAssertEqual(update.profiles.first?.id, "profile-set-a")
        XCTAssertTrue(update.profiles.first?.isDefault == true)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/v2/projects/location-spoofer/update")
        XCTAssertEqual(request.url?.query, "current_version=1.0.5-0009")
    }

    func testGenericURLJobUsesV2AndExplicitProfile() async throws {
        let transport = RecordingTransport(response: """
        {"job_id":"00000000-0000-4000-8000-000000000002","status":"queued","signing_mode":"split"}
        """)
        let client = makeClient(transport: transport)
        _ = try await client.createURLJob(
            sourceURL: URL(string: "https://downloads.example/App.ipa")!,
            options: SigningOptions(profileID: "profile-set-a")
        )
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/v2/sign/jobs")
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(payload["source_url"] as? String, "https://downloads.example/App.ipa")
        XCTAssertEqual(payload["profile_id"] as? String, "profile-set-a")
    }

    func testUploadUsesV2RoutesBeforeCreatingJob() async throws {
        let transport = RecordingTransport(responses: [
            "{\"upload_id\":\"00000000-0000-4000-8000-000000000003\",\"part_size\":8388608,\"max_bytes\":104857600,\"expires_at\":\"2026-08-12T00:00:00Z\"}",
            "{\"upload_id\":\"00000000-0000-4000-8000-000000000003\",\"part_number\":1,\"etag\":\"etag-1\"}",
            "{\"upload_id\":\"00000000-0000-4000-8000-000000000003\",\"status\":\"completed\",\"filename\":\"Local.ipa\"}",
            "{\"job_id\":\"00000000-0000-4000-8000-000000000004\",\"status\":\"queued\",\"signing_mode\":\"split\"}",
        ])
        let client = makeClient(transport: transport)

        _ = try await client.uploadAndCreateJob(
            filename: "Local.ipa",
            data: Data("fake-ipa!".utf8),
            options: SigningOptions(profileID: "profile-set-a")
        )

        XCTAssertEqual(transport.requests.map { $0.url?.path }, [
            "/v2/uploads",
            "/v2/uploads/00000000-0000-4000-8000-000000000003/parts/1",
            "/v2/uploads/00000000-0000-4000-8000-000000000003/complete",
            "/v2/sign/jobs",
        ])
    }

    func testHistoryFollowsEveryCursorPageOnV2() async throws {
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
        XCTAssertEqual(transport.requests.first?.url?.path, "/v2/sign/jobs")
        XCTAssertEqual(transport.requests[1].url?.query, "cursor=page-2")
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

    func testUnauthorizedIsReportedSeparatelyFromForbidden() async {
        let unauthorized = RecordingTransport(responses: ["{\"error\":\"unauthorized\"}"], statusCodes: [401])
        do {
            _ = try await makeClient(transport: unauthorized).projects()
            XCTFail("401 should surface as unauthorized")
        } catch SigningClientError.unauthorized {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        let forbidden = RecordingTransport(responses: ["{\"error\":\"forbidden\"}"], statusCodes: [403])
        do {
            _ = try await makeClient(transport: forbidden).projects()
            XCTFail("403 should retain the server error")
        } catch SigningClientError.server(let status, let message) {
            XCTAssertEqual(status, 403)
            XCTAssertEqual(message, "forbidden")
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
