# GifSnap for Swift

A typed async API client and a native SwiftUI GIF/sticker picker. The picker plays full GIF and animated WebP assets, supports search and pagination, and returns the original selected record.

## Requirements

- Swift tools 5.9 or later; Xcode 15 or later.
- `GifSnap`: Foundation client for iOS 16+ and macOS 13+.
- `GifSnapUI`: native SwiftUI picker for iOS 16+. A macOS picker is not included.
- Tested with Xcode 26.3 / Swift 6.2.4 in Swift 5 language mode, an iOS 26.1 simulator and macOS. No iOS 16 runtime or physical-device result is claimed.

## Install

In Xcode choose **File → Add Package Dependencies**, enter:

```text
https://github.com/rowixgroup/gifsnap-swift
```

Select version **0.1.1** or a compatible later version. Add `GifSnapUI` and `GifSnap` to an iOS app, or just `GifSnap` for client-only use. With a `Package.swift` manifest:

```swift
.package(url: "https://github.com/rowixgroup/gifsnap-swift.git", from: "0.1.1")
```

Add products to the consuming target:

```swift
.product(name: "GifSnap", package: "gifsnap-swift"),
.product(name: "GifSnapUI", package: "gifsnap-swift")
```

The Foundation target does not link the image dependency. SwiftPM may still resolve it as part of the package graph.

## SwiftUI quickstart

For installation and a complete selection view in one page, see the [SwiftUI quickstart](docs/quickstart.md).

```swift
import SwiftUI
import GifSnap
import GifSnapUI

struct ContentView: View {
    @State private var selected: GifSnapGif?

    var body: some View {
        VStack {
            if let selected {
                Text("Selected: \(selected.title)")
            }
            GifSnapPicker(theme: .system, mediaType: .gif, pageSize: 24) { gif in
                selected = gif
                // gif.url is the exact full media URL returned by the API.
                // gif.mediaURL is its Foundation URL representation.
            }
        }
    }
}
```

The picker owns its scroll view; give it a bounded layout such as a sheet or the remaining area of a screen. It offers GIF/sticker tabs, a search field with a 300 ms debounce, explicit loading/empty/error/end states, manual load-more and retry buttons, and light/dark/system appearance. The default page size is 24; values are clamped to 1...50. `initialQuery` is an initial value, not a binding. Pass a custom `client: any GifSnapAPI` to use your own service or deterministic fixtures.

Rows retain their order on append. The picker removes duplicate exact IDs, exact full URL strings and matching optional `content_id` values. It keeps the first record and preserves its ID and URLs. Query strings are meaningful; they are never stripped. A duplicate-only page pauses for a manual next-page action rather than automatically fetching repeatedly. Selection does not dismiss the hosting sheet or send telemetry; the host decides what to do next.

## Foundation client

```swift
import GifSnap

let client = try GifSnapClient() // HTTPS public API; 15-second whole-request timeout
let response = try await client.search(query: "happy", page: 1, limit: 24)

for gif in response.data {
    print(gif.id, gif.url, gif.source ?? "Not specified")
}
if let page = response.pagination.nextPage {
    let next = try await client.search(query: "happy", page: page, limit: 24)
    print(next.data.count)
}

let trending = try await client.trending(limit: 12)
let stickers = try await client.searchStickers(query: "hello", limit: 12)
let trendingStickers = try await client.trendingStickers(limit: 12)
```

`GifSnapClient(baseURL:timeout:)` accepts an HTTP(S) base URL without credentials, query or fragment, and a timeout from 0.05 to 120 seconds. Default: `https://gifsnap.com/api/v1`. Prefer HTTPS; ordinary HTTP remains subject to the host app's App Transport Security policy. The SDK does not disable ATS. Page must be positive, limit must be 1...50, and search must contain non-whitespace text. Search text is trimmed and URL-encoded.

Client responses are **not deduplicated**. Their `data` records and pagination counts are kept as returned, including duplicates. `GifSnapGif` exposes `id`, `title`, exact `url`/`previewURL` strings, `width`, `height`, `type`, optional `source` and optional opaque `contentID`. Unknown item fields are retained in `additionalFields` as `GifSnapJSON`; numeric unknown fields use `Double`. `GifSnapResponse` exposes `data`, `pagination` and optional `query`. Provider IDs are not interchangeable. Never use `contentID` in place of the returned lookup ID.

### Errors and cancellation

```swift
let operation = Task { () -> GifSnapResponse? in
    do {
        return try await client.trending()
    } catch is CancellationError {
        return nil
    } catch let error as GifSnapError {
        switch error {
        case .http(let status, let retryAfterSeconds):
            print(status, retryAfterSeconds as Any)
        case .timeout, .network, .invalidResponse:
            print(error.localizedDescription)
        case .invalidArgument(let message):
            print(message)
        }
        return nil
    } catch {
        return nil
    }
}
// Cancel when the hosting screen no longer needs the response:
operation.cancel()
```

There are no automatic retries. `Retry-After` seconds or HTTP dates are exposed when supplied. Task cancellation cancels the URLSession transfer and surfaces `CancellationError`. The timeout covers response loading; URLSession also has request/resource timeouts. JSON response bodies larger than 8 MiB are rejected after receipt. This is not a streaming download size cap. Unsafe media URLs, malformed required fields, invalid pagination and malformed present identities are rejected as `invalidResponse`.

## Animation, accessibility and limits

`GifSnapUI` pins [SDWebImage 5.21.7](https://github.com/SDWebImage/SDWebImage/releases/tag/5.21.7), an MIT-licensed native image loader. It uses `SDAnimatedImageView`, not `AsyncImage` or per-cell web views. GIF support is built in. On first use, the picker registers SDWebImage's ImageIO-backed `SDImageAWebPCoder` in its shared coder registry for animated WebP support on the supported iOS versions. It does not replace existing coders.

The full returned media URL is tried first, then a distinct preview URL once on failure, then a visible unavailable state. The preview can be static. Each card keeps a fixed media box while loading. Decoder thumbnails are constrained to 480×480 pixels, each active animation uses a 4 MiB frame-buffer budget, and a dedicated loader allows four downloads concurrently. Dedicated image-cache eviction budgets are 32 MiB in memory and 64 MiB on disk; these are cache targets, not a guarantee of total process memory use. GIF/WebP source downloads can be large. Animated assets are tested; video URLs are not supported by this picker.

The view uses native buttons/text fields, accessible selection labels, Dynamic Type text and system colors. Reduce Motion stops animation while keeping media visible. Native image views stop playback when detached and cancel outstanding loads during teardown. Very long titles are truncated visually but the selection accessibility label includes the full title. Provider labels are not displayed or read aloud by the picker; source metadata remains available on the selected record. Test extreme Dynamic Type and host-specific layouts in your app before shipping.

The SDK adds no analytics or advertising. Searches go to the configured API, and media requests go to the returned CDN URLs; those services receive normal network request information. The API client and dedicated image loader omit cookie/credential stores. API/media rights, availability and provider terms are separate from the SDK's MIT license. Public API access is currently best-effort; this package makes no SLA, rate-limit or media-license promise.

## Verify and run the example

```bash
swift test
GIFSNAP_LIVE_TESTS=1 swift test --filter LiveContractTests
xcodebuild -scheme GifSnap-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The live test is opt-in and makes four anonymous requests. Offline tests exercise encoding, validation, response preservation, errors, timeout/cancellation, deduplication, source preference, real fallback requests, animation decoding/playback, stale-search rejection, retries and pagination locking. Synthetic GIF/WebP fixtures are generated for tests; no provider media is bundled.

A runnable app and UI flow test are under `Examples/PickerDemo`. Generate the example project with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
xcodegen generate --spec Examples/PickerDemo/project.yml
open Examples/PickerDemo/PickerDemo.xcodeproj
```

Normal launches use the real API. The UI test launches with `--fixtures`; before running it, serve synthetic media locally:

```bash
python3 -m http.server 38741 --bind 127.0.0.1 --directory Tests/GifSnapUITests/Fixtures
```

Run the `PickerDemo` test scheme on an iOS simulator. The fixture server is only needed for those UI tests. The sample app allows local networking; the library does not modify your app's Info.plist.

## License and references

SDK code/documentation: [MIT](LICENSE). Dependency notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). GIFs, stickers and service/provider trademarks are not licensed by this repository.

Implementation references: [Apple URLSession async transfer](https://developer.apple.com/documentation/foundation/urlsession), [resource timeout](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/timeoutintervalforresource), [UIViewRepresentable](https://developer.apple.com/documentation/swiftui/uiviewrepresentable), [SDAnimatedImageView](https://github.com/SDWebImage/SDWebImage/blob/5.21.7/SDWebImage/Core/SDAnimatedImageView.h), and [animated WebP coder](https://github.com/SDWebImage/SDWebImage/blob/5.21.7/SDWebImage/Core/SDImageAWebPCoder.h).
