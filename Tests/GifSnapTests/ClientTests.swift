import XCTest
@testable import GifSnap

final class ClientTests: XCTestCase {
    static func fixture(items: [[String: Any]]? = nil, page: Int = 1, next: Int? = nil, total: Int = 71) -> Data {
        let item: [String: Any] = ["id": "raw-id", "title": "A GIF", "url": "https://cdn.example/animated.webp?version=1", "preview_url": "https://cdn.example/still.webp", "width": 320, "height": 180, "type": "gif", "source": "provider", "content_id": "opaque:123", "provider_metadata": ["label": "preserved"]]
        return try! JSONSerialization.data(withJSONObject: ["data": items ?? [item], "pagination": ["page": page, "limit": 24, "total": total, "has_next": next != nil, "next_page": next as Any? ?? NSNull(), "offset": (page - 1) * 24], "query": "hello"])
    }
    static func http(_ request: URLRequest, status: Int = 200, headers: [String: String]? = nil) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }
    func testSearchEncodingAndPreservedResponse() async throws {
        let client = try GifSnapClient { request in
            let c = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(c.path, "/api/v1/gifs/search")
            XCTAssertEqual(c.queryItems?.first(where: { $0.name == "q" })?.value, "cats & dogs/😺")
            XCTAssertEqual(c.queryItems?.first(where: { $0.name == "page" })?.value, "3")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertFalse(request.httpShouldHandleCookies)
            return (Self.fixture(), Self.http(request))
        }
        let result = try await client.search(query: " cats & dogs/😺 ", page: 3, limit: 12)
        XCTAssertEqual(result.pagination.total, 71)
        XCTAssertEqual(result.data[0].url, "https://cdn.example/animated.webp?version=1")
        XCTAssertEqual(result.data[0].contentID, "opaque:123")
        XCTAssertEqual(result.data[0].source, "provider")
        XCTAssertEqual(result.data[0].additionalFields["provider_metadata"], .object(["label": .string("preserved")]))
    }
    func testAllFourEndpoints() async throws {
        for endpoint in ["gifs/trending", "gifs/search", "stickers/trending", "stickers/search"] {
            let client = try GifSnapClient { request in
                XCTAssertEqual(request.url!.path, "/api/v1/" + endpoint)
                return (Self.fixture(), Self.http(request))
            }
            switch endpoint {
            case "gifs/trending": _ = try await client.trending()
            case "gifs/search": _ = try await client.search(query: "hi")
            case "stickers/trending": _ = try await client.trendingStickers()
            default: _ = try await client.searchStickers(query: "hi")
            }
        }
    }
    func testInvalidURLsAndOptions() throws {
        for value in ["file:///tmp/image.gif", "javascript:alert(1)", "https://user:pass@host.test/a", "/relative.gif", "https:///", "data:image/gif;base64,abc"] {
            XCTAssertFalse(GifSnapURL.isHTTP(value), value)
        }
        for value in ["https://host.test/api?q=1", "https://host.test/api#fragment", "file:///tmp", "https://user@host.test"] {
            XCTAssertThrowsError(try GifSnapClient(baseURL: URL(string: value)!))
        }
        XCTAssertThrowsError(try GifSnapClient(timeout: .infinity))
        XCTAssertThrowsError(try GifSnapClient(timeout: 0))
    }
    func testInvalidPageLimitAndSearchNeverReachTransport() async throws {
        let client = try GifSnapClient { _ in XCTFail("Unexpected transport"); throw GifSnapError.network }
        for options in [(0, 24), (1, 0), (1, 51)] {
            do { _ = try await client.trending(page: options.0, limit: options.1); XCTFail() }
            catch GifSnapError.invalidArgument { } catch { XCTFail("\(error)") }
        }
        do { _ = try await client.search(query: " \n "); XCTFail() }
        catch GifSnapError.invalidArgument { } catch { XCTFail("\(error)") }
    }
    func testHTTPErrorRetainsStatusAndRetryAfter() async throws {
        let client = try GifSnapClient { request in (Data("not JSON".utf8), Self.http(request, status: 429, headers: ["Retry-After": "30"])) }
        do { _ = try await client.trending(); XCTFail() }
        catch { XCTAssertEqual(error as? GifSnapError, .http(status: 429, retryAfterSeconds: 30)) }
    }
    func testInvalidJSONAndPaginationRejected() throws {
        XCTAssertThrowsError(try GifSnapResponse.decode(Data("bad".utf8)))
        XCTAssertThrowsError(try GifSnapResponse.decode(Self.fixture(page: 2, next: 2)))
        XCTAssertThrowsError(try GifSnapResponse.decode(Self.fixture(total: -1)))
    }
    func testInvalidPresentIdentityOrUnsafeMediaRejected() throws {
        let base = try JSONSerialization.jsonObject(with: Self.fixture()) as! [String: Any]
        let item = (base["data"] as! [[String: Any]])[0]
        for value: Any in [NSNull(), "", " \n ", 42] {
            var bad = item; bad["content_id"] = value
            XCTAssertThrowsError(try GifSnapResponse.decode(Self.fixture(items: [bad])))
        }
        var bad = item; bad["url"] = "file:///tmp/private.gif"
        XCTAssertThrowsError(try GifSnapResponse.decode(Self.fixture(items: [bad])))
    }
    func testAbsentIdentityAndSourceAcceptedWithoutRewritingCounts() throws {
        let original = try JSONSerialization.jsonObject(with: Self.fixture()) as! [String: Any]
        var item = (original["data"] as! [[String: Any]])[0]
        item.removeValue(forKey: "source"); item.removeValue(forKey: "content_id")
        let response = try GifSnapResponse.decode(Self.fixture(items: [item, item], total: 99))
        XCTAssertEqual(response.data.count, 2); XCTAssertEqual(response.pagination.total, 99)
        XCTAssertNil(response.data[0].contentID); XCTAssertNil(response.data[0].source)
    }
    func testWholeRequestTimeout() async throws {
        let client = try GifSnapClient(timeout: 0.05) { request in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return (Self.fixture(), Self.http(request))
        }
        let start = Date()
        do { _ = try await client.trending(); XCTFail() }
        catch { XCTAssertEqual(error as? GifSnapError, .timeout) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
    }
    func testCancellationIsNotNetworkFailure() async throws {
        let client = try GifSnapClient { request in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return (Self.fixture(), Self.http(request))
        }
        let task = Task { try await client.trending() }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch is CancellationError { } catch { XCTFail("\(error)") }
    }
    func testNetworkFailureMapped() async throws {
        let client = try GifSnapClient { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await client.trending(); XCTFail() } catch { XCTAssertEqual(error as? GifSnapError, .network) }
    }
    func testDedupFirstRecordPreservedAndQueryVariantsDistinct() throws {
        func item(_ id: String, _ url: String, _ identity: String? = nil) throws -> GifSnapGif {
            try GifSnapGif(id: id, title: id, url: url, previewURL: "https://cdn.test/p.webp", width: 10, height: 10, contentID: identity)
        }
        var seen = GifSnapIdentitySet()
        let first = try item("original", "https://cdn.test/a.gif?v=1", "provider:1")
        let alias = try item("alias", "https://cdn.test/b.webp", "provider:1")
        let queryVariant = try item("variant", "https://cdn.test/a.gif?v=2")
        XCTAssertEqual(seen.appendUnique([first, alias, queryVariant]), [first, queryVariant])
        XCTAssertEqual(try seen.appendUnique([item("another", alias.url)]).count, 0)
        XCTAssertEqual(try seen.appendUnique([item("original", "https://cdn.test/other.gif")]).count, 0)
    }
    func testMediaCandidatesFullFirstBoundedAndSafe() {
        XCTAssertEqual(GifSnapMediaCandidates(full: "https://cdn.test/a.webp?x=1", preview: "https://cdn.test/p.webp").urls.map(\.absoluteString), ["https://cdn.test/a.webp?x=1", "https://cdn.test/p.webp"])
        XCTAssertEqual(GifSnapMediaCandidates(full: "https://cdn.test/a.gif", preview: "https://cdn.test/a.gif").urls.count, 1)
        XCTAssertEqual(GifSnapMediaCandidates(full: "file:///tmp/x", preview: "").urls.count, 0)
    }
}
