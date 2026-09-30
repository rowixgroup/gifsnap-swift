import Foundation

public enum GifSnapError: Error, Equatable, Sendable, LocalizedError {
    case invalidArgument(String)
    case http(status: Int, retryAfterSeconds: TimeInterval?)
    case network
    case timeout
    case invalidResponse
    public var errorDescription: String? {
        switch self {
        case .invalidArgument(let message): return message
        case .http(let status, _): return status == 429 ? "Too many requests. Please try again shortly." : "GifSnap request failed (\(status))."
        case .network: return "Could not reach GifSnap. Check your connection and try again."
        case .timeout: return "The request timed out. Please try again."
        case .invalidResponse: return "GifSnap returned an invalid response."
        }
    }
}

/// Typed anonymous public API client. No automatic retries, telemetry, cookies or API keys.
public final class GifSnapClient: @unchecked Sendable {
    public static let defaultBaseURL = URL(string: "https://gifsnap.com/api/v1")!
    public let baseURL: URL
    public let timeout: TimeInterval
    private let session: URLSession
    private let transport: (@Sendable (URLRequest) async throws -> (Data, URLResponse))?

    public init(baseURL: URL = GifSnapClient.defaultBaseURL, timeout: TimeInterval = 15) throws {
        try Self.validate(baseURL: baseURL, timeout: timeout)
        self.baseURL = baseURL; self.timeout = timeout; self.transport = nil
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        self.session = URLSession(configuration: configuration)
    }
    internal init(baseURL: URL = GifSnapClient.defaultBaseURL, timeout: TimeInterval = 15,
                  transport: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) throws {
        try Self.validate(baseURL: baseURL, timeout: timeout)
        self.baseURL = baseURL; self.timeout = timeout; self.transport = transport
        self.session = URLSession(configuration: .ephemeral)
    }
    deinit { session.invalidateAndCancel() }
    private static func validate(baseURL: URL, timeout: TimeInterval) throws {
        guard GifSnapURL.isHTTP(baseURL.absoluteString), let c = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              c.query == nil, c.fragment == nil else { throw GifSnapError.invalidArgument("baseURL must be HTTP(S), without credentials, query or fragment.") }
        guard timeout.isFinite, timeout >= 0.05, timeout <= 120 else { throw GifSnapError.invalidArgument("timeout must be between 0.05 and 120 seconds.") }
    }
    public func search(query: String, page: Int = 1, limit: Int = 24) async throws -> GifSnapResponse {
        try await request("gifs/search", query: validatedQuery(query), page: page, limit: limit)
    }
    public func trending(page: Int = 1, limit: Int = 24) async throws -> GifSnapResponse {
        try await request("gifs/trending", page: page, limit: limit)
    }
    public func searchStickers(query: String, page: Int = 1, limit: Int = 24) async throws -> GifSnapResponse {
        try await request("stickers/search", query: validatedQuery(query), page: page, limit: limit)
    }
    public func trendingStickers(page: Int = 1, limit: Int = 24) async throws -> GifSnapResponse {
        try await request("stickers/trending", page: page, limit: limit)
    }
    private func validatedQuery(_ query: String) throws -> String {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw GifSnapError.invalidArgument("query must not be empty.") }
        return value
    }
    private func request(_ endpoint: String, query: String? = nil, page: Int, limit: Int) async throws -> GifSnapResponse {
        guard page >= 1, (1...50).contains(limit) else { throw GifSnapError.invalidArgument("page must be positive and limit must be 1...50.") }
        try Task.checkCancellation()
        var c = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "limit", value: String(limit))]
        if let query { c.queryItems?.append(URLQueryItem(name: "q", value: query)) }
        var request = URLRequest(url: c.url!, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpShouldHandleCookies = false
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await withThrowingTaskGroup(of: TransportResult.self) { group in
                group.addTask { [self, request] in
                    let result: (Data, URLResponse)
                    if let transport { result = try await transport(request) }
                    else { result = try await session.data(for: request, delegate: RedirectGuard()) }
                    return TransportResult(data: result.0, response: result.1)
                }
                group.addTask { [timeout] in
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    throw GifSnapError.timeout
                }
                defer { group.cancelAll() }
                let result = try await group.next()!
                return (result.data, result.response)
            }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if let typed = error as? GifSnapError { throw typed }
            if (error as? URLError)?.code == .timedOut { throw GifSnapError.timeout }
            throw GifSnapError.network
        }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw GifSnapError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw GifSnapError.http(status: http.statusCode, retryAfterSeconds: Self.retryDelay(http.value(forHTTPHeaderField: "Retry-After")))
        }
        guard data.count <= 8 * 1024 * 1024 else { throw GifSnapError.invalidResponse }
        return try GifSnapResponse.decode(data)
    }
    private struct TransportResult: @unchecked Sendable { let data: Data; let response: URLResponse }
    static func retryDelay(_ value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = Double(value.trimmingCharacters(in: .whitespaces)), seconds.isFinite, seconds >= 0 { return seconds }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value).map { max(0, ceil($0.timeIntervalSinceNow)) }
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, GifSnapURL.isHTTP(url.absoluteString),
              !(task.originalRequest?.url?.scheme == "https" && url.scheme == "http") else { completionHandler(nil); return }
        completionHandler(request)
    }
}

public protocol GifSnapAPI: Sendable {
    func search(query: String, page: Int, limit: Int) async throws -> GifSnapResponse
    func trending(page: Int, limit: Int) async throws -> GifSnapResponse
    func searchStickers(query: String, page: Int, limit: Int) async throws -> GifSnapResponse
    func trendingStickers(page: Int, limit: Int) async throws -> GifSnapResponse
}
extension GifSnapClient: GifSnapAPI {
    /// The fixed HTTPS default is valid by construction.
    public static let shared = try! GifSnapClient()
}
