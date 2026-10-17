import Foundation

public enum GifSnapMediaType: String, Codable, Sendable { case gif, sticker }

/// Values returned by providers that do not yet have a typed SDK field.
public indirect enum GifSnapJSON: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), null, array([GifSnapJSON]), object([String: GifSnapJSON])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([GifSnapJSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: GifSnapJSON].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

/// Optional small animation. The original GIF URL remains the sharing URL.
public struct GifSnapAnimatedPreview: Decodable, Equatable, Sendable {
    public let url: String
    public let mimeType: String
    public let width: Int
    public let height: Int
    public let byteSize: Int?
    public let animated: Bool
    public init(url: String, mimeType: String, width: Int, height: Int, byteSize: Int? = nil, animated: Bool = true) throws {
        let extensions = ["image/gif":"gif", "image/webp":"webp", "video/mp4":"mp4", "video/webm":"webm"]
        let ext = URL(string: url)?.pathExtension.lowercased() ?? ""
        guard GifSnapURL.isHTTP(url), let expected = extensions[mimeType], ext.isEmpty || ext == expected,
              animated, (1...480).contains(width), (1...480).contains(height),
              byteSize.map({ (1...524288).contains($0) }) ?? true else { throw GifSnapError.invalidResponse }
        self.url = url; self.mimeType = mimeType; self.width = width; self.height = height
        self.byteSize = byteSize; self.animated = animated
    }
    private enum CodingKeys: String, CodingKey { case url, mimeType = "mime_type", width, height, byteSize = "byte_size", animated }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(url: c.decode(String.self, forKey: .url), mimeType: c.decode(String.self, forKey: .mimeType),
                      width: c.decode(Int.self, forKey: .width), height: c.decode(Int.self, forKey: .height),
                      byteSize: c.decodeIfPresent(Int.self, forKey: .byteSize), animated: c.decode(Bool.self, forKey: .animated))
    }
}

public struct GifSnapGif: Decodable, Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    /// Exact returned URL, including its query. May point to an external CDN.
    public let url: String
    public let previewURL: String
    public let width: Int
    public let height: Int
    public let type: GifSnapMediaType
    public let source: String?
    /// Optional opaque server-verified identity. Never substitute it for the lookup ID.
    public let contentID: String?
    public let animatedPreview: GifSnapAnimatedPreview?
    public let additionalFields: [String: GifSnapJSON]
    public var mediaURL: URL { URL(string: url)! }
    public var previewMediaURL: URL { URL(string: previewURL)! }

    public init(id: String, title: String, url: String, previewURL: String, width: Int, height: Int,
                type: GifSnapMediaType = .gif, source: String? = nil, contentID: String? = nil,
                additionalFields: [String: GifSnapJSON] = [:], animatedPreview: GifSnapAnimatedPreview? = nil) throws {
        guard !id.isEmpty, GifSnapURL.isHTTP(url), GifSnapURL.isHTTP(previewURL), width >= 0, height >= 0,
              contentID == nil || !contentID!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GifSnapError.invalidResponse
        }
        self.id = id; self.title = title; self.url = url; self.previewURL = previewURL
        self.width = width; self.height = height; self.type = type; self.source = source
        self.contentID = contentID; self.additionalFields = additionalFields
        self.animatedPreview = animatedPreview
    }
    private enum Keys: String, CodingKey, CaseIterable {
        case id, title, url, previewURL = "preview_url", width, height, type, source, contentID = "content_id"
        case animatedPreview = "animated_preview"
    }
    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let all = try decoder.container(keyedBy: AnyKey.self)
        var extra: [String: GifSnapJSON] = [:]
        for key in all.allKeys where !Keys.allCases.contains(where: { $0.rawValue == key.stringValue }) {
            extra[key.stringValue] = try all.decode(GifSnapJSON.self, forKey: key)
        }
        // Optional means absent; a present null or malformed field is not accepted.
        let source = c.contains(.source) ? try c.decode(String.self, forKey: .source) : nil
        let identity = c.contains(.contentID) ? try c.decode(String.self, forKey: .contentID) : nil
        try self.init(id: c.decode(String.self, forKey: .id), title: c.decode(String.self, forKey: .title),
                      url: c.decode(String.self, forKey: .url), previewURL: c.decode(String.self, forKey: .previewURL),
                      width: c.decode(Int.self, forKey: .width), height: c.decode(Int.self, forKey: .height),
                      type: c.decode(GifSnapMediaType.self, forKey: .type), source: source,
                      contentID: identity, additionalFields: extra,
                      animatedPreview: try? c.decode(GifSnapAnimatedPreview.self, forKey: .animatedPreview))
    }
}

public struct GifSnapPagination: Decodable, Equatable, Sendable {
    public let page: Int
    public let limit: Int
    public let total: Int
    public let hasNext: Bool
    public let nextPage: Int?
    public let offset: Int
    enum CodingKeys: String, CodingKey { case page, limit, total, hasNext = "has_next", nextPage = "next_page", offset }
    func validate() throws {
        guard page >= 1, (1...50).contains(limit), total >= 0, offset >= 0,
              hasNext ? (nextPage.map { $0 > page } ?? false) : nextPage == nil else { throw GifSnapError.invalidResponse }
    }
}

public struct GifSnapResponse: Decodable, Equatable, Sendable {
    public let data: [GifSnapGif]
    public let pagination: GifSnapPagination
    public let query: String?
    public static func decode(_ data: Data) throws -> Self {
        do {
            let response = try JSONDecoder().decode(Self.self, from: data)
            try response.pagination.validate()
            return response
        } catch { throw GifSnapError.invalidResponse }
    }
}

public enum GifSnapURL {
    public static func isHTTP(_ value: String) -> Bool {
        guard !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let c = URLComponents(string: value), let scheme = c.scheme?.lowercased(),
              ["https", "http"].contains(scheme), let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.url != nil else { return false }
        return true
    }
}

/// Presentation-only deduplication. Raw client responses are never filtered.
public struct GifSnapIdentitySet: Sendable {
    private var ids: Set<String> = [], urls: Set<String> = [], contentIDs: Set<String> = []
    public init() {}
    public mutating func appendUnique(_ items: [GifSnapGif]) -> [GifSnapGif] {
        var result: [GifSnapGif] = []
        for item in items {
            let duplicate = ids.contains(item.id) || urls.contains(item.url) || item.contentID.map { contentIDs.contains($0) } == true
            // Record all observed keys, including aliases of a record already kept.
            ids.insert(item.id); urls.insert(item.url)
            if let identity = item.contentID { contentIDs.insert(identity) }
            if !duplicate { result.append(item) }
        }
        return result
    }
}

/// Small image animation, original animation, then legacy poster; at most three attempts.
public struct GifSnapMediaCandidates: Equatable, Sendable {
    public let urls: [URL]
    public init(full: String, preview: String, animatedPreview: GifSnapAnimatedPreview? = nil) {
        var seen = Set<String>()
        let small = animatedPreview.flatMap { $0.mimeType.hasPrefix("image/") ? $0.url : nil }
        urls = [small, full, preview].compactMap { $0 }.filter { GifSnapURL.isHTTP($0) && seen.insert($0).inserted }.compactMap(URL.init(string:))
    }
}
