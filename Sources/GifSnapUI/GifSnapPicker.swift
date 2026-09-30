#if canImport(UIKit)
import SwiftUI
import GifSnap

public enum GifSnapTheme: String, Sendable { case system, light, dark }

/// A ready-to-use iOS 16+ picker. Selection returns the unchanged first matching API record.
@MainActor public struct GifSnapPicker: View {
    @StateObject private var model: PickerModel
    @State private var query: String
    @State private var mediaType: GifSnapMediaType
    private let theme: GifSnapTheme
    private let onSelect: (GifSnapGif) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 240), spacing: 12)]

    public init(client: any GifSnapAPI = GifSnapClient.shared, theme: GifSnapTheme = .system,
                mediaType: GifSnapMediaType = .gif, pageSize: Int = 24, initialQuery: String = "",
                onSelect: @escaping (GifSnapGif) -> Void) {
        _model = StateObject(wrappedValue: PickerModel(client: client, pageSize: pageSize))
        _query = State(initialValue: initialQuery); _mediaType = State(initialValue: mediaType)
        self.theme = theme; self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search GIFs and stickers", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.search).accessibilityIdentifier("gifsnap.search")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Clear search").frame(minWidth: 44, minHeight: 44)
                }
            }
            .padding(.leading, 12).padding(.trailing, 4).frame(minHeight: 48)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            Picker("Media type", selection: $mediaType) {
                Text("GIFs").tag(GifSnapMediaType.gif)
                Text("Stickers").tag(GifSnapMediaType.sticker)
            }.pickerStyle(.segmented).accessibilityIdentifier("gifsnap.mediaType")

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.items) { item in
                        Button { onSelect(item) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                AnimatedMedia(full: item.url, preview: item.previewURL, isAnimating: !reduceMotion)
                                    .frame(height: 132).frame(maxWidth: .infinity)
                                    .background(Color(uiColor: .tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                Text(item.title.isEmpty ? "Untitled GIF" : item.title)
                                    .font(.caption.weight(.medium)).lineLimit(1)
                            }.foregroundStyle(.primary).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select \(item.title.isEmpty ? "GIF" : item.title)")
                        .accessibilityIdentifier("gifsnap.item.\(item.id)")
                    }
                }
                VStack(spacing: 12) {
                    if model.isLoading {
                        ProgressView("Loading…").padding().accessibilityIdentifier("gifsnap.loading")
                    } else if let error = model.errorMessage {
                        Text(error).font(.callout).multilineTextAlignment(.center)
                        Button("Retry") { model.loadMore() }.buttonStyle(.bordered).accessibilityIdentifier("gifsnap.retry")
                    } else if model.items.isEmpty && !model.hasNext {
                        Label("No results. Try another search.", systemImage: "magnifyingglass")
                            .font(.callout).foregroundStyle(.secondary).padding()
                    } else if model.hasNext {
                        if model.duplicatePage {
                            Text("This page contained items already shown.").font(.caption).foregroundStyle(.secondary)
                        }
                        Button("Load more") { model.loadMore() }.buttonStyle(.bordered)
                            .frame(minHeight: 44).accessibilityIdentifier("gifsnap.loadMore")
                    } else {
                        Text("You’re all caught up.").font(.caption).foregroundStyle(.secondary).padding()
                    }
                    Link("Powered by GifSnap", destination: URL(string: "https://gifsnap.com")!)
                        .font(.caption).padding(.bottom, 8)
                }.frame(maxWidth: .infinity).padding(.top, 16)
            }.scrollDismissesKeyboard(.interactively)
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(theme == .system ? nil : theme == .dark ? .dark : .light)
        .task(id: SearchKey(query: query, type: mediaType)) { await model.refresh(query: query, type: mediaType) }
        .onDisappear { model.stop() }
    }
    private struct SearchKey: Equatable { let query: String; let type: GifSnapMediaType }
}
#endif
