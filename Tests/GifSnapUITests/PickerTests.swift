#if canImport(UIKit)
import XCTest
import SwiftUI
import SDWebImage
import GifSnap
@testable import GifSnapUI

actor FixtureAPI: GifSnapAPI {
    var requests: [String] = []
    var failPageTwo = false
    var duplicates = false
    func configure(fail: Bool = false, duplicates: Bool = false) { failPageTwo = fail; self.duplicates = duplicates }
    func result(query: String, page: Int, type: String) async throws -> GifSnapResponse {
        requests.append("\(type):\(query):\(page)")
        if query == "slow" { try? await Task.sleep(nanoseconds: 100_000_000) }
        if failPageTwo && page == 2 { failPageTwo = false; throw GifSnapError.network }
        let identity = duplicates ? "first" : "\(query)-\(page)"
        let data: [[String: Any]] = query == "empty" ? [] : [["id": "\(query)-\(page)", "title": "Fixture \(page)", "url": "https://fixture.invalid/\(query)-\(page).gif", "preview_url": "https://fixture.invalid/preview.png", "width": 64, "height": 48, "type": type, "source": "Synthetic", "content_id": identity]]
        let hasNext = page < 3 && query != "empty"
        let json: [String: Any] = ["data": data, "pagination": ["page": page, "limit": 24, "total": 3, "has_next": hasNext, "next_page": hasNext ? page + 1 : NSNull(), "offset": (page - 1) * 24]]
        return try GifSnapResponse.decode(JSONSerialization.data(withJSONObject: json))
    }
    func search(query: String, page: Int, limit: Int) async throws -> GifSnapResponse { try await result(query: query, page: page, type: "gif") }
    func trending(page: Int, limit: Int) async throws -> GifSnapResponse { try await result(query: "", page: page, type: "gif") }
    func searchStickers(query: String, page: Int, limit: Int) async throws -> GifSnapResponse { try await result(query: query, page: page, type: "sticker") }
    func trendingStickers(page: Int, limit: Int) async throws -> GifSnapResponse { try await result(query: "", page: page, type: "sticker") }
}

@MainActor final class PickerTests: XCTestCase {
    func settle(_ model: PickerModel) async throws {
        for _ in 0..<200 where model.isLoading { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertFalse(model.isLoading)
    }
    func testBothAnimatedFormatsDecodeDistinctFramesAndDurations() throws {
        _ = GifSnapAnimation.prepare
        for ext in ["gif", "webp"] {
            let url = Bundle.module.url(forResource: "motion", withExtension: ext, subdirectory: "Fixtures")!
            let image = try XCTUnwrap(SDAnimatedImage(data: Data(contentsOf: url)))
            XCTAssertEqual(image.animatedImageFrameCount, 3, ext)
            let first = image.animatedImageFrame(at: 0)?.pngData()
            let second = image.animatedImageFrame(at: 1)?.pngData()
            XCTAssertNotNil(first); XCTAssertNotEqual(first, second, ext)
            XCTAssertEqual(image.animatedImageDuration(at: 0), 0.1, accuracy: 0.03)
            XCTAssertEqual(image.animatedImageDuration(at: 1), 0.2, accuracy: 0.03)
        }
    }
    func testNativeViewAdvancesAndStopsAnimation() async throws {
        _ = GifSnapAnimation.prepare
        let image = try XCTUnwrap(SDAnimatedImage(data: Data(contentsOf: Bundle.module.url(forResource: "motion", withExtension: "webp", subdirectory: "Fixtures")!)))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let controller = UIViewController(); window.rootViewController = controller
        let view = SDAnimatedImageView(frame: CGRect(x: 0, y: 0, width: 64, height: 48))
        controller.view.addSubview(view); window.makeKeyAndVisible(); view.image = image
        view.startAnimating()
        var observed: Set<UInt> = []
        for _ in 0..<12 { try await Task.sleep(nanoseconds: 50_000_000); observed.insert(view.currentFrameIndex) }
        XCTAssertGreaterThan(observed.count, 1)
        view.stopAnimating(); XCTAssertFalse(view.isAnimating)
        window.isHidden = true
    }
    func testSearchPaginationLockFailureRetryAndOrder() async throws {
        let client = FixtureAPI(); await client.configure(fail: true)
        let model = PickerModel(client: client, pageSize: 24)
        await model.refresh(query: "cats", type: .gif, debounce: false)
        XCTAssertEqual(model.items.map(\.id), ["cats-1"])
        model.loadMore(); model.loadMore(); try await settle(model)
        XCTAssertNotNil(model.errorMessage); XCTAssertEqual(model.items.map(\.id), ["cats-1"])
        model.loadMore(); try await settle(model)
        XCTAssertEqual(model.items.map(\.id), ["cats-1", "cats-2"])
        model.loadMore(); try await settle(model); XCTAssertFalse(model.hasNext)
        let requests = await client.requests
        XCTAssertEqual(requests, ["gif:cats:1", "gif:cats:2", "gif:cats:2", "gif:cats:3"])
    }
    func testDuplicateOnlyPagePausesForManualContinuation() async throws {
        let client = FixtureAPI(); await client.configure(duplicates: true)
        let model = PickerModel(client: client, pageSize: 24)
        await model.refresh(query: "cats", type: .gif, debounce: false)
        model.loadMore(); try await settle(model)
        XCTAssertEqual(model.items.count, 1); XCTAssertTrue(model.duplicatePage); XCTAssertTrue(model.hasNext)
        let requestCount = await client.requests.count
        XCTAssertEqual(requestCount, 2)
    }
    func testStaleSearchIgnoredAndEmptyStickersFinish() async throws {
        let client = FixtureAPI(); let model = PickerModel(client: client, pageSize: 24)
        let first = Task { await model.refresh(query: "slow", type: .gif, debounce: false) }
        try await Task.sleep(nanoseconds: 10_000_000)
        await model.refresh(query: "new", type: .sticker, debounce: false)
        await first.value
        XCTAssertEqual(model.items.map(\.id), ["new-1"]); XCTAssertEqual(model.items.first?.type, .sticker)
        await model.refresh(query: "empty", type: .sticker, debounce: false)
        XCTAssertTrue(model.items.isEmpty); XCTAssertFalse(model.hasNext)
    }
    func testStopPreventsLateMutation() async throws {
        let model = PickerModel(client: FixtureAPI(), pageSize: 24)
        let task = Task { await model.refresh(query: "slow", type: .gif, debounce: false) }
        try await Task.sleep(nanoseconds: 10_000_000); model.stop(); await task.value
        XCTAssertTrue(model.items.isEmpty); XCTAssertFalse(model.isLoading)
    }
    func testFullMediaErrorFallsBackOnceAndTerminalFailureStops() async throws {
        let config = SDWebImageDownloaderConfig()
        let session = URLSessionConfiguration.ephemeral
        session.protocolClasses = [MediaFixtureProtocol.self]
        config.sessionConfiguration = session
        let cache = SDImageCache(namespace: UUID().uuidString)
        let manager = SDWebImageManager(cache: cache, loader: SDWebImageDownloader(config: config))
        let coordinator = AnimatedMedia.Coordinator(manager: manager)
        let view = MediaContainer()
        let host = UUID().uuidString.lowercased() + ".invalid"
        let full = URL(string: "https://\(host)/broken.gif")!
        let preview = URL(string: "https://\(host)/preview.png")!
        coordinator.update(view: view, urls: [full, preview], isAnimating: true)
        for _ in 0..<200 where view.imageView.image == nil { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertNotNil(view.imageView.image)
        XCTAssertEqual(MediaFixtureProtocol.requests.paths(host: host), ["/broken.gif", "/preview.png"])
        coordinator.update(view: view, urls: [full, preview], isAnimating: true)
        XCTAssertEqual(MediaFixtureProtocol.requests.paths(host: host).count, 2)
        let secondHost = UUID().uuidString.lowercased() + ".invalid"
        coordinator.update(view: view, urls: [URL(string: "https://\(secondHost)/broken1.gif")!, URL(string: "https://\(secondHost)/broken2.png")!], isAnimating: true)
        for _ in 0..<200 where view.message.text != "Media unavailable" { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(view.message.text, "Media unavailable")
        XCTAssertEqual(MediaFixtureProtocol.requests.paths(host: secondHost), ["/broken1.gif", "/broken2.png"])
        XCTAssertNil(view.imageView.image)
    }
    func testBoundedFallbackExhaustionAndTeardown() {
        let coordinator = AnimatedMedia.Coordinator(); let view = MediaContainer()
        coordinator.update(view: view, urls: [], isAnimating: false)
        XCTAssertFalse(view.imageView.isAnimating)
        AnimatedMedia.dismantleUIView(view, coordinator: coordinator)
        XCTAssertNil(view.imageView.image)
    }
}
private final class MediaRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: [String]] = [:]
    func append(_ url: URL) { lock.lock(); defer { lock.unlock() }; values[url.host!, default: []].append(url.path) }
    func paths(host: String) -> [String] { lock.lock(); defer { lock.unlock() }; return values[host] ?? [] }
}
private final class MediaFixtureProtocol: URLProtocol {
    static let requests = MediaRequests()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!; Self.requests.append(url)
        let success = url.lastPathComponent == "preview.png"
        let response = HTTPURLResponse(url: url, statusCode: success ? 200 : 404, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if success, let asset = Bundle.module.url(forResource: "preview", withExtension: "png", subdirectory: "Fixtures"), let data = try? Data(contentsOf: asset) { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
