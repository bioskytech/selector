import Foundation

/// The bundled crate: 11,700 dance-ready songs with audio features, the learned
/// transition model, the learned club arc, and artist "goes-with" neighbours.
/// Produced by the Python pipeline (build_app_data.py).
struct Catalog: Decodable, Sendable {
    struct Tracks: Decodable, Sendable {
        let id: [String]      // Spotify track id (used as a stable key)
        let n: [String]       // title
        let ar: [String]      // "Artist, Artist"
        let a: [Int]          // primary artist index into `artists`
        let bpm: [Double]     // tempo folded into the vibe's DJ range
        let k: [Int]          // key 0-11, +12 when major
        let e: [Double]       // energy 0-1
        let d: [Double]       // danceability 0-1
        let v: [Double]       // valence 0-1
        let l: [Double]       // loudness dB
        let i: [Double]       // instrumentalness 0-1
        let s: [Double]       // speechiness 0-1
        let dur: [Int]        // seconds
        let p: [Int]          // popularity 0-100
        let vm: [Int]         // vibe bitmask
        let x: [Int]          // explicit flag
    }
    struct Vibe: Decodable, Sendable, Identifiable {
        let key: String
        let label: String
        let bpm: [Double]
        let n: Int
        let bpm_med: Double?
        let energy_med: Double?
        let electronic: Bool
        let limited: Bool
        var id: String { key }
    }
    struct Model: Decodable, Sendable {
        let intercept: Double
        let coef: [String: Double]
        let tbins: [Double]
        let ebins: [Double]
    }
    struct ArcCurve: Decodable, Sendable {
        let energy: [Double]
        let tempo: [Double]
        let n_mixes: Int
    }
    struct PlayStat: Decodable, Sendable {
        let median_min: Double
        let frac_median: Double?
        let n: Int
    }
    struct ArcModel: Decodable, Sendable {
        let arc: [String: ArcCurve]
        let play: [String: PlayStat]
    }

    let t: Tracks
    let vibes: [Vibe]
    let artists: [String]
    let an: [[Int]]
    let model: Model
    let arc: ArcModel

    var count: Int { t.id.count }

    static func load() throws -> Catalog {
        guard let url = Bundle.main.url(forResource: "app_data", withExtension: "json") else {
            throw CatalogError.missingResource
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    /// Title without the "(From ...)" / "[Remix]" tail, for speech and headlines.
    static func shortTitle(_ s: String) -> String {
        if let r = s.range(of: #"\s*[\(\[].*$"#, options: .regularExpression) {
            return String(s[..<r.lowerBound])
        }
        return s
    }

    /// First artist of an "A, B, C" credit.
    static func firstArtist(_ s: String) -> String {
        s.components(separatedBy: ", ").first ?? s
    }
}

enum CatalogError: LocalizedError {
    case missingResource
    var errorDescription: String? { "app_data.json is missing from the app bundle." }
}

// MARK: - Vibes

/// Display name and colour for each of the 16 sounds. Every colour is bright enough to carry dark type.
struct VibeStyle {
    let name: String
    let short: String?
    let hex: String
    let dark: Bool          // light background: use dark text on it

    var label: String { short ?? name }
}

enum Vibes {
    static let all: [String: VibeStyle] = [
        "bollywood": VibeStyle(name: "Bollywood", short: nil, hex: "#FF4FA0", dark: true),
        "punjabi": VibeStyle(name: "Punjabi", short: nil, hex: "#FF8A1F", dark: true),
        "southindian": VibeStyle(name: "Telugu & Tamil", short: nil, hex: "#19C3A6", dark: true),
        "mideast": VibeStyle(name: "Arabic, Persian & Turkish", short: "Middle East", hex: "#E9B44C", dark: true),
        "reggaeton": VibeStyle(name: "Reggaeton", short: nil, hex: "#FFD60A", dark: true),
        "latin": VibeStyle(name: "Latin", short: nil, hex: "#FF5E3A", dark: true),
        "afro": VibeStyle(name: "Afrobeats", short: nil, hex: "#5BD66B", dark: true),
        "kpop": VibeStyle(name: "K-Pop & J-Pop", short: nil, hex: "#6FD3FF", dark: true),
        "techno": VibeStyle(name: "Techno", short: nil, hex: "#4D7DFF", dark: true),
        "house": VibeStyle(name: "House", short: nil, hex: "#2ED3E6", dark: true),
        "trance": VibeStyle(name: "Trance", short: nil, hex: "#9B8CFF", dark: true),
        "edm": VibeStyle(name: "EDM", short: nil, hex: "#B8F03C", dark: true),
        "bass": VibeStyle(name: "Drum & Bass", short: nil, hex: "#FF3B4E", dark: true),
        "disco": VibeStyle(name: "Disco & Funk", short: nil, hex: "#F25BD6", dark: true),
        "hiphop": VibeStyle(name: "Hip-Hop & R&B", short: nil, hex: "#C9A4FF", dark: true),
        "pop": VibeStyle(name: "Pop", short: nil, hex: "#FF7A90", dark: true),
    ]
    static let order = ["bollywood", "punjabi", "southindian", "mideast", "reggaeton", "latin", "afro", "kpop",
                        "techno", "house", "trance", "edm", "bass", "disco", "hiphop", "pop"]
    static let electronic: Set<String> = ["techno", "house", "edm", "trance", "bass"]

    static func name(_ key: String) -> String { all[key]?.label ?? key }
    static func hex(_ key: String) -> String { all[key]?.hex ?? "#444444" }
    static func style(_ key: String) -> VibeStyle { all[key] ?? VibeStyle(name: key, short: nil, hex: "#444444", dark: false) }

    /// "A, B and C"
    static func joinNames(_ a: [String]) -> String {
        guard let last = a.last else { return "" }
        if a.count == 1 { return last }
        return a.dropLast().joined(separator: ", ") + " and " + last
    }
}

// MARK: - Occasions

enum ArcKind: String, Codable, CaseIterable {
    case club, wedding, party, sunset, peak
}

struct Occasion: Identifiable {
    let key: String
    let label: String
    let desc: String
    let weights: [String: Int]
    let minutes: Int
    let arc: ArcKind
    let clean: Bool
    let fam: Double
    var id: String { key }

    static let all: [Occasion] = [
        Occasion(key: "sangeet", label: "Sangeet night", desc: "Family in the room, dhol by the second hour", weights: ["bollywood": 3, "punjabi": 3, "southindian": 1, "edm": 1], minutes: 120, arc: .wedding, clean: true, fam: 0.8),
        Occasion(key: "party", label: "House party", desc: "Friends over, drinks out, peak around the second hour", weights: ["pop": 3, "hiphop": 1, "punjabi": 1, "afro": 1], minutes: 120, arc: .party, clean: false, fam: 0.75),
        Occasion(key: "reggaeton", label: "Reggaeton rooftop", desc: "Sunset, dembow and a little afrobeats", weights: ["reggaeton": 3, "latin": 1, "afro": 1], minutes: 90, arc: .party, clean: false, fam: 0.75),
        Occasion(key: "sunset", label: "Sunset to peak", desc: "Starts at golden hour, ends in the dark", weights: ["house": 3, "disco": 1, "techno": 1], minutes: 180, arc: .sunset, clean: false, fam: 0.5),
        Occasion(key: "techno", label: "Warehouse techno", desc: "Long blends, no vocals, no breaks", weights: ["techno": 3, "house": 1], minutes: 120, arc: .club, clean: false, fam: 0.4),
        Occasion(key: "mideast", label: "Middle East night", desc: "Arabic, Persian and Turkish pop with a dance edge", weights: ["mideast": 3, "pop": 1, "edm": 1], minutes: 90, arc: .party, clean: true, fam: 0.7),
        Occasion(key: "afro", label: "Afro house party", desc: "Afrobeats, amapiano and house", weights: ["afro": 3, "house": 1, "hiphop": 1], minutes: 120, arc: .party, clean: false, fam: 0.7),
        Occasion(key: "dinner", label: "Dinner that turns into a party", desc: "Quiet while people eat, then the tables get pushed back", weights: ["disco": 2, "pop": 2, "bollywood": 1], minutes: 180, arc: .sunset, clean: true, fam: 0.8),
    ]
    static let lengths = [30, 60, 90, 120, 180, 240]

    static func named(_ key: String?) -> Occasion? {
        guard let key else { return nil }
        return all.first { $0.key == key }
    }

    /// The occasion whose sounds exactly match these weights, if any.
    static func matching(_ weights: [String: Int]) -> Occasion? {
        let on = weights.filter { $0.value > 0 }
        return all.first { o in o.weights.count == on.count && o.weights.allSatisfy { on[$0.key] == $0.value } }
    }
}
