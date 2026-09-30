#if canImport(UIKit)
import Foundation
import SwiftUI
import GifSnap

@MainActor final class PickerModel: ObservableObject {
    @Published private(set) var items: [GifSnapGif] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasNext = true
    @Published private(set) var duplicatePage = false
    private var identities = GifSnapIdentitySet()
    private var page = 1
    private var generation = UUID()
    private var query = ""
    private var type: GifSnapMediaType = .gif
    private var moreTask: Task<Void, Never>?
    private let client: any GifSnapAPI
    private let pageSize: Int

    init(client: any GifSnapAPI, pageSize: Int) {
        self.client = client; self.pageSize = min(50, max(1, pageSize))
    }
    func refresh(query: String, type: GifSnapMediaType, debounce: Bool = true) async {
        moreTask?.cancel(); generation = UUID()
        let current = generation
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines); self.type = type
        items = []; identities = GifSnapIdentitySet(); page = 1; hasNext = true
        errorMessage = nil; duplicatePage = false; isLoading = true
        if debounce && !self.query.isEmpty {
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
        }
        await fetch(generation: current)
    }
    func loadMore() {
        guard !isLoading, hasNext else { return }
        isLoading = true
        let current = generation
        moreTask = Task { await fetch(generation: current) }
    }
    func stop() {
        moreTask?.cancel(); generation = UUID(); isLoading = false
    }
    private func fetch(generation current: UUID) async {
        guard !Task.isCancelled, current == generation else { return }
        errorMessage = nil
        do {
            let result: GifSnapResponse
            switch (type, query.isEmpty) {
            case (.gif, true): result = try await client.trending(page: page, limit: pageSize)
            case (.gif, false): result = try await client.search(query: query, page: page, limit: pageSize)
            case (.sticker, true): result = try await client.trendingStickers(page: page, limit: pageSize)
            case (.sticker, false): result = try await client.searchStickers(query: query, page: page, limit: pageSize)
            }
            guard !Task.isCancelled, current == generation else { return }
            let additions = identities.appendUnique(result.data)
            items.append(contentsOf: additions)
            hasNext = result.pagination.hasNext
            duplicatePage = additions.isEmpty && hasNext
            if let next = result.pagination.nextPage { page = next }
        } catch {
            guard !Task.isCancelled, current == generation, !(error is CancellationError) else { return }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Could not load GIFs. Please try again."
        }
        if current == generation { isLoading = false }
    }
}
#endif
