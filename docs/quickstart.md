# GifSnap 0.1.1 SwiftUI quickstart

The package repository is https://github.com/rowixgroup/gifsnap-swift. Its products are named `GifSnap` and `GifSnapUI`.

In Xcode, add the repository URL with version 0.1.1 or later. Add both products to an iOS 16+ app target. With Swift Package Manager:

```swift
.package(url: "https://github.com/rowixgroup/gifsnap-swift.git", from: "0.1.1")
```

Add these dependencies to the consuming target:

```swift
.product(name: "GifSnap", package: "gifsnap-swift"),
.product(name: "GifSnapUI", package: "gifsnap-swift")
```

This complete view keeps the selection in application state:

```swift
import SwiftUI
import GifSnap
import GifSnapUI

struct GifComposer: View {
    @State private var selected: GifSnapGif?

    var body: some View {
        VStack {
            GifSnapPicker(theme: .system, mediaType: .gif, pageSize: 24) { gif in
                selected = gif
            }
            .frame(height: 440)

            Text(selected?.title ?? "Choose a GIF")
        }
    }
}
```

`selected?.url` is the complete full-media URL returned by the API. Keep the selection's identifier, dimensions and source metadata when storing or sending it. A preview can be static. The picker provides animated GIF/WebP playback; a custom view needs an animation-capable image implementation.

The README is the complete reference: https://github.com/rowixgroup/gifsnap-swift/blob/main/README.md
