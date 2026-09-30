import SwiftUI
import GifSnap
import GifSnapUI

@main struct PickerDemoApp: App {
    @State private var selected: GifSnapGif?
    @State private var dark = false
    private let client: any GifSnapAPI = ProcessInfo.processInfo.arguments.contains("--fixtures") ? DemoFixtureAPI() : GifSnapClient.shared
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack(spacing: 0) {
                    if let selected {
                        Text("Selected: \(selected.title)").font(.callout).padding(8).accessibilityIdentifier("demo.selection")
                    }
                    GifSnapPicker(client: client, theme: dark ? .dark : .light, pageSize: 6) { selected = $0 }
                }
                .navigationTitle("GifSnap").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button(dark ? "Light" : "Dark") { dark.toggle() }.accessibilityIdentifier("demo.theme") }
            }
        }
    }
}

/// Offline UI fixtures only. Normal demo launches use the real anonymous API.
actor DemoFixtureAPI: GifSnapAPI {
    private var failedOnce = false
    private func result(query: String, page: Int, type: String) throws -> GifSnapResponse {
        if query == "retry" && !failedOnce { failedOnce = true; throw GifSnapError.network }
        let count = query == "empty" ? 0 : 3
        let next = count > 0 && page == 1
        let items: [[String: Any]] = (0..<count).map { index in
            let id = "\(query)-\(page)-\(index)"
            return ["id": id, "title": "\(query.isEmpty ? "Motion" : query) \(page)-\(index)",
                    "url": "http://127.0.0.1:38741/\(index == 1 ? "motion.webp" : "motion.gif")?item=\(id)",
                    "preview_url": "http://127.0.0.1:38741/preview.png?item=\(id)",
                    "width": 64, "height": 48, "type": type, "source": "Synthetic test"]
        }
        let json: [String: Any] = ["data": items, "pagination": ["page": page, "limit": 6, "total": count * 2, "has_next": next, "next_page": next ? 2 : NSNull(), "offset": (page - 1) * 3]]
        return try GifSnapResponse.decode(JSONSerialization.data(withJSONObject: json))
    }
    func search(query: String, page: Int, limit: Int) async throws -> GifSnapResponse { try result(query: query, page: page, type: "gif") }
    func trending(page: Int, limit: Int) async throws -> GifSnapResponse { try result(query: "", page: page, type: "gif") }
    func searchStickers(query: String, page: Int, limit: Int) async throws -> GifSnapResponse { try result(query: query, page: page, type: "sticker") }
    func trendingStickers(page: Int, limit: Int) async throws -> GifSnapResponse { try result(query: "", page: page, type: "sticker") }
}
