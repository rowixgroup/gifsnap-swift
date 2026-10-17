import XCTest
@testable import GifSnap

final class PreviewTests: XCTestCase {
    func testSmallFirstFallbackAndOriginalSelectionURL() throws {
        let small = try GifSnapAnimatedPreview(url: "https://cdn.test/small.webp", mimeType: "image/webp", width: 160, height: 120, byteSize: 15000)
        let item = try GifSnapGif(id: "a", title: "A", url: "https://cdn.test/full.gif?exact=1", previewURL: "https://cdn.test/poster.webp", width: 640, height: 480, animatedPreview: small)
        XCTAssertEqual(GifSnapMediaCandidates(full: item.url, preview: item.previewURL, animatedPreview: small).urls.map(\.absoluteString), [small.url, item.url, item.previewURL])
        XCTAssertEqual(item.url, "https://cdn.test/full.gif?exact=1")
        let video = try GifSnapAnimatedPreview(url: "https://cdn.test/small.mp4", mimeType: "video/mp4", width: 160, height: 120)
        XCTAssertEqual(GifSnapMediaCandidates(full: item.url, preview: item.url, animatedPreview: video).urls.count, 1)
    }
    func testMalformedOptionalPreviewKeepsUsableGIF() throws {
        let root = try JSONSerialization.jsonObject(with: ClientTests.fixture()) as! [String: Any]
        let item = (root["data"] as! [[String: Any]])[0]
        let small: [String: Any] = ["url":"https://cdn.test/small.webp", "mime_type":"image/webp", "width":160, "height":120, "byte_size":15000, "animated":true]
        var good = item; good["animated_preview"] = small
        XCTAssertEqual(try GifSnapResponse.decode(ClientTests.fixture(items: [good])).data[0].animatedPreview?.byteSize, 15000)
        for patch: [String: Any] in [["animated":false], ["byte_size":524289], ["width":481], ["url":"file:///tmp/x"], ["url":"https://cdn.test/static.jpg"]] {
            var bad = small; bad.merge(patch) { _, new in new }
            var row = item; row["animated_preview"] = bad
            let parsed = try GifSnapResponse.decode(ClientTests.fixture(items: [row])).data[0]
            XCTAssertNil(parsed.animatedPreview); XCTAssertEqual(parsed.url, item["url"] as? String)
        }
    }
}
