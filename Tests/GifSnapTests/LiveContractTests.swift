import XCTest
import GifSnap

final class LiveContractTests: XCTestCase {
    func testFourPublicEndpointsWithoutCredentials() async throws {
        guard ProcessInfo.processInfo.environment["GIFSNAP_LIVE_TESTS"] == "1" else { throw XCTSkip("Opt-in live contract test") }
        let client = try GifSnapClient()
        let responses = [try await client.search(query: "hello", limit: 2), try await client.trending(limit: 2),
                         try await client.searchStickers(query: "hello", limit: 2), try await client.trendingStickers(limit: 2)]
        for response in responses {
            XCTAssertFalse(response.data.isEmpty)
            XCTAssertEqual(response.pagination.limit, 2)
            XCTAssertTrue(response.data.allSatisfy { GifSnapURL.isHTTP($0.url) })
        }
        XCTAssertTrue(responses[0].data.allSatisfy { $0.type == .gif })
        XCTAssertTrue(responses[2].data.allSatisfy { $0.type == .sticker })
    }
}
