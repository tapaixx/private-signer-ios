import Foundation

/// Seam for tests and for hosts that need their own URL loading policy.
public protocol SigningTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: SigningTransport {
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

public enum SigningClientError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case sourceTooLarge
    case server(Int, String)

    public var code: String {
        switch self {
        case .invalidURL: return "invalid_url"
        case .invalidResponse: return "invalid_response"
        case .unauthorized: return "unauthorized"
        case .sourceTooLarge: return "source_too_large"
        case .server: return "server"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return KitStrings.string("error.invalid_url")
        case .invalidResponse:
            return KitStrings.string("error.invalid_response")
        case .unauthorized:
            return KitStrings.string("error.unauthorized")
        case .sourceTooLarge:
            return KitStrings.string("error.source_too_large")
        case .server(let status, let message):
            return KitStrings.string("error.server", String(status), message)
        }
    }
}

/// The single v2 client. Project signing uses Worker-managed ProjectVersions while generic URL and
/// upload signing continue to use the established v2 Signing Job API and the same request token.
public struct SigningClient {
    public static let maximumSourceBytes = 100 * 1024 * 1024
    public static let maximumPartBytes = 8 * 1024 * 1024

    public let configuration: SignerConfiguration
    private let userAgent: String
    private let transport: SigningTransport
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        configuration: SignerConfiguration,
        userAgent: String,
        transport: SigningTransport? = nil
    ) {
        self.configuration = configuration
        self.userAgent = userAgent
        if let transport {
            self.transport = transport
        } else {
            let settings = URLSessionConfiguration.ephemeral
            settings.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            settings.timeoutIntervalForRequest = 30
            settings.timeoutIntervalForResource = 300
            self.transport = URLSession(configuration: settings)
        }
    }

    // MARK: - Project catalog

    public func projects() async throws -> [SigningProject] {
        let response: ProjectListResponse = try await send(path: "v2/projects", method: "GET")
        return response.projects
    }

    public func project(id: String) async throws -> ProjectDetail {
        try await send(path: "v2/projects/\(encodedPathComponent(id))", method: "GET")
    }

    public func projectVersions(projectID: String) async throws -> [ProjectVersion] {
        let response: ProjectVersionsResponse = try await send(
            path: "v2/projects/\(encodedPathComponent(projectID))/versions",
            method: "GET"
        )
        return response.versions
    }

    /// Asks the Worker, not the app, whether a newer version should be installed.
    public func projectUpdate(projectID: String, currentVersion: String) async throws -> ProjectUpdate {
        try await send(
            path: "v2/projects/\(encodedPathComponent(projectID))/update",
            method: "GET",
            queryItems: [URLQueryItem(name: "current_version", value: currentVersion)]
        )
    }

    /// Profiles available to this v2 client. Supplying a project filters the list by that project's
    /// server-side policy and marks its configured default.
    public func profiles(projectID: String? = nil) async throws -> [ProfileCapability] {
        let response: ProfileListResponse = try await send(
            path: "v2/profiles",
            method: "GET",
            queryItems: projectID.map { [URLQueryItem(name: "project_id", value: $0)] } ?? []
        )
        return response.profiles
    }

    // MARK: - Create Signing Jobs

    public func createProjectJob(
        projectID: String,
        versionID: String,
        options: ProjectSigningOptions = ProjectSigningOptions()
    ) async throws -> SigningJob {
        var payload = try encodedOptions(options)
        payload["project_id"] = projectID
        payload["version_id"] = versionID
        return try await send(path: "v2/sign/jobs", method: "POST", json: payload)
    }

    /// Generic URL signing. Project self-update code should never call this method.
    public func createURLJob(sourceURL: URL, options: SigningOptions) async throws -> SigningJob {
        var payload = try encodedOptions(options)
        payload["source_url"] = sourceURL.absoluteString
        return try await send(path: "v2/sign/jobs", method: "POST", json: payload)
    }

    public func uploadAndCreateJob(
        filename: String,
        data: Data,
        options: SigningOptions
    ) async throws -> SigningJob {
        guard data.count <= Self.maximumSourceBytes else { throw SigningClientError.sourceTooLarge }
        let session: UploadSessionResponse = try await send(
            path: "v2/uploads",
            method: "POST",
            json: ["filename": filename, "size": data.count]
        )
        let partSize = try validatedPartSize(session.partSize)
        var offset = 0
        var partNumber = 1
        while offset < data.count {
            let end = min(offset + partSize, data.count)
            try await uploadPart(
                uploadID: session.uploadID,
                partNumber: partNumber,
                data: data.subdata(in: offset..<end)
            )
            offset = end
            partNumber += 1
        }
        try await completeUpload(uploadID: session.uploadID)
        var payload = try encodedOptions(options)
        payload["upload_id"] = session.uploadID
        return try await send(path: "v2/sign/jobs", method: "POST", json: payload)
    }

    public func uploadAndCreateJob(fileURL: URL, options: SigningOptions) async throws -> SigningJob {
        let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .nameKey])
        guard let size = values.fileSize, size > 0, size <= Self.maximumSourceBytes else {
            throw SigningClientError.sourceTooLarge
        }
        let session: UploadSessionResponse = try await send(
            path: "v2/uploads",
            method: "POST",
            json: ["filename": values.name ?? fileURL.lastPathComponent, "size": size]
        )
        let partSize = try validatedPartSize(session.partSize)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var partNumber = 1
        while true {
            let part = try handle.read(upToCount: partSize) ?? Data()
            if part.isEmpty { break }
            try await uploadPart(uploadID: session.uploadID, partNumber: partNumber, data: part)
            partNumber += 1
        }
        try await completeUpload(uploadID: session.uploadID)
        var payload = try encodedOptions(options)
        payload["upload_id"] = session.uploadID
        return try await send(path: "v2/sign/jobs", method: "POST", json: payload)
    }

    // MARK: - Job lifecycle

    public func job(id: String) async throws -> SigningJob {
        try await send(path: "v2/sign/jobs/\(encodedPathComponent(id))", method: "GET")
    }

    public func history() async throws -> [SigningJob] {
        var jobs: [SigningJob] = []
        var cursor: String?
        var seenCursors = Set<String>()
        repeat {
            let queryItems = cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
            let response: JobHistoryResponse = try await send(
                path: "v2/sign/jobs",
                method: "GET",
                queryItems: queryItems
            )
            jobs.append(contentsOf: response.jobs)
            cursor = response.nextCursor
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw SigningClientError.invalidResponse
            }
            if seenCursors.count > 300 { throw SigningClientError.invalidResponse }
        } while cursor != nil
        return jobs
    }

    public func retry(jobID: String) async throws -> SigningJob {
        try await send(path: "v2/sign/jobs/\(encodedPathComponent(jobID))/retry", method: "POST", json: [:])
    }

    public func cancel(jobID: String) async throws -> SigningJob {
        try await send(path: "v2/sign/jobs/\(encodedPathComponent(jobID))/cancel", method: "POST", json: [:])
    }

    public func links(jobID: String) async throws -> DeliveryLinks {
        try await send(path: "v2/sign/jobs/\(encodedPathComponent(jobID))/links", method: "POST", json: [:])
    }

    // MARK: - Service identity

    public func health() async throws -> ServiceHealth {
        var request = try unauthenticatedRequest(path: "health", method: "GET")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    public func verifyConfiguration() async -> ConfigurationVerification {
        let health: ServiceHealth
        do {
            health = try await self.health()
        } catch SigningClientError.invalidResponse {
            return .notASigner
        } catch SigningClientError.server {
            return .notASigner
        } catch SigningClientError.unauthorized {
            return .notASigner
        } catch {
            return .unreachable(error.localizedDescription)
        }
        guard health.ok else { return .notASigner }
        if let contract = health.contract, !ServiceHealth.supportedContracts.contains(contract) {
            return .unsupportedContract(contract)
        }
        do {
            let _: ProjectListResponse = try await send(path: "v2/projects", method: "GET")
        } catch SigningClientError.unauthorized {
            return .invalidToken
        } catch {
            return .unreachable(error.localizedDescription)
        }
        return health.contract == nil ? .usableWithUndeclaredContract : .usable
    }

    // MARK: - Plumbing

    private func validatedPartSize(_ value: Int) throws -> Int {
        guard value > 0, value <= Self.maximumPartBytes else { throw SigningClientError.invalidResponse }
        return value
    }

    private func uploadPart(uploadID: String, partNumber: Int, data: Data) async throws {
        var request = try authorizedRequest(
            path: "v2/uploads/\(encodedPathComponent(uploadID))/parts/\(partNumber)",
            method: "PUT"
        )
        request.httpBody = data
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let _: UploadPartResponse = try await perform(request)
    }

    private func completeUpload(uploadID: String) async throws {
        let _: UploadCompleteResponse = try await send(
            path: "v2/uploads/\(encodedPathComponent(uploadID))/complete",
            method: "POST",
            json: [:]
        )
    }

    private func encodedOptions<T: Encodable>(_ options: T) throws -> [String: Any] {
        let data = try encoder.encode(options)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SigningClientError.invalidResponse
        }
        return value
    }

    private func encodedPathComponent(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func send<T: Decodable>(
        path: String,
        method: String,
        json: [String: Any]? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        var request = try authorizedRequest(path: path, method: method, queryItems: queryItems)
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await perform(request)
    }

    private func unauthenticatedRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        let segments = path.split(separator: "/").map(String.init)
        let baseURL = segments.reduce(configuration.workerURL) { partial, segment in
            partial.appendingPathComponent(segment)
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw SigningClientError.invalidURL
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw SigningClientError.invalidURL }
        guard url.scheme?.lowercased() == "https" else { throw SigningClientError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    private func authorizedRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        var request = try unauthenticatedRequest(path: path, method: method, queryItems: queryItems)
        request.setValue("Bearer \(configuration.requestToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await transport.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SigningClientError.invalidResponse }
        if http.statusCode == 401 { throw SigningClientError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let payload = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
            let message = payload?["message"] as? String
                ?? payload?["error"] as? String
                ?? KitStrings.string("error.unknown")
            throw SigningClientError.server(http.statusCode, message)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SigningClientError.invalidResponse
        }
    }
}

public struct ProjectDetail: Decodable, Equatable {
    public let project: SigningProject
    public let latestVersion: ProjectVersion?

    private enum CodingKeys: String, CodingKey {
        case project
        case latestVersion = "latest_version"
    }
}

private struct ProjectListResponse: Decodable {
    let projects: [SigningProject]
}

private struct ProjectVersionsResponse: Decodable {
    let versions: [ProjectVersion]
}

private struct ProfileListResponse: Decodable {
    let profiles: [ProfileCapability]
}

private struct UploadSessionResponse: Decodable {
    let uploadID: String
    let partSize: Int

    private enum CodingKeys: String, CodingKey {
        case uploadID = "upload_id"
        case partSize = "part_size"
    }
}

private struct UploadPartResponse: Decodable {
    let uploadID: String
    let partNumber: Int

    private enum CodingKeys: String, CodingKey {
        case uploadID = "upload_id"
        case partNumber = "part_number"
    }
}

private struct UploadCompleteResponse: Decodable {
    let uploadID: String
    let status: String

    private enum CodingKeys: String, CodingKey {
        case uploadID = "upload_id"
        case status
    }
}

private struct JobHistoryResponse: Decodable {
    let jobs: [SigningJob]
    let nextCursor: String?

    private enum CodingKeys: String, CodingKey {
        case jobs
        case nextCursor = "next_cursor"
    }
}
