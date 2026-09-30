import SwiftUI
import GifSnapUI

// Minimal website quickstart; the selected record type is inferred without importing GifSnap.
struct GIFComposer: View {
    var body: some View {
        GifSnapPicker { gif in
            print(gif.url)
        }
    }
}
