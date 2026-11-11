import Foundation
import MusicKit

/// What the listener asked for. Persisted between launches.
struct Settings: Codable {
    var occasion: String? = "sangeet"
    var weights: [String: Int] = ["bollywood": 3, "punjabi": 3, "southindian": 1, "edm": 1]
    var minutes: Int = 120
    var arc: ArcKind = .wedding
    var clean: Bool = true
    var fam: Double = 0.8
    var useTaste: Bool = true
    var seed: UInt64 = 7

    mutating func apply(_ o: Occasion) {
        occasion = o.key
        weights = o.weights
        minutes = o.minutes
        arc = o.arc
        clean = o.clean
        fam = o.fam
    }

    /// Sounds asked for, strongest first.
    var sounds: [String] {
        weights.filter { $0.value > 0 }.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map { $0.key }
    }

    var title: String {
        if let o = Occasion.named(occasion) { return o.label }
        let heads = sounds.prefix(2).map { Vibes.name($0) }
        return heads.isEmpty ? "Your night" : heads.joined(separator: " & ") + " night"
    }
}

/// Whether a planned song has been found on Apple Music yet.
enum MatchState {
    case pending
    case missing
    case found(Track)

    var track: Track? { if case .found(let s) = self { return s }; return nil }
    var isPending: Bool { if case .pending = self { return true }; return false }
    var isMissing: Bool { if case .missing = self { return true }; return false }
}

/// One steering request, for the recap.
struct SteerRequest {
    let action: String
    let arg: String?
    let at: Date
}

/// What a steering request replaced, so it can be undone.
struct SteerUndo {
    let seq: [Int]
    let am: [MatchState]
    let exclude: Set<String>?
    let boost: [String: Double]?
    let energyOff: ((Double) -> Double)?
    let fam: Double
    let durS: Double
    let weights: [String: Int]
    let favor: [Int: Double]
    let banned: Set<Int>
    let pv: [Int]
    let pool: [Int]
    let at: Int                 // position that was playing when the request was made
}

/// The current plan and its playback state.
@Observable @MainActor
final class Night {
    var plan: Plan
    var am: [MatchState]
    var replaced: Set<Int> = []
    var resolving = false
    var resolved = false
    var resolveNote = ""
    var startedAt: Date?
    var played: Set<Int> = []          // positions
    var loved: Set<Int> = []           // catalog track ids
    var requests: [SteerRequest] = []
    var saved = false
    var undo: SteerUndo?
    var swaps: [Int: Set<Int>] = [:]
    let createdAt: Date

    init(plan: Plan, createdAt: Date = Date()) {
        self.plan = plan
        self.am = Array(repeating: .pending, count: plan.seq.count)
        self.createdAt = createdAt
    }

    /// Bumped whenever positions shift or are re-planned, so slow lookups can tell their answer is stale.
    var generation = 0
    var inFlight: Set<Int> = []
    var resolveAgain = false
    var priority = 0
    var firstPlay: Date?
    var skips: [Int] = []              // catalog track ids skipped early

    func track(at k: Int) -> Track? { k >= 0 && k < am.count ? am[k].track : nil }
    var tracks: [Track?] { am.map { $0.track } }
    var pendingCount: Int { am.reduce(0) { $0 + ($1.isPending ? 1 : 0) } }
    var startOrNow: Date { startedAt ?? Fmt.roundedNow() }
}

/// The night, remembered. Shown on the home screen and the recap.
struct Recap: Codable, Identifiable {
    var id: Double                // createdAt
    var title: String
    var date: String
    var seconds: Double
    var songs: Int
    var peakK: Int
    var peakJ: Int
    var peakAt: String
    var peakArt: String?
    var loved: Int
    var requests: Int
    var saved: Bool
    var vibes: [String]
    var seq: [Int]
    var arts: [String?]
    var weights: [String: Int]
    var minutes: Int
    var arc: ArcKind
    var clean: Bool
    var fam: Double
    var occasion: String?
}

/// Enough of a night to pick it up again after the app was closed.
struct SavedNight: Codable {
    var seq: [Int]
    var weights: [String: Int]
    var arc: ArcKind
    var clean: Bool
    var fam: Double
    var durS: Double
    var title: String
    var startedAt: Date?
    var played: [Int]
    var loved: [Int]
    var requests: Int
    var saved: Bool
    var createdAt: Date
}

enum Store {
    static func get<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
    static func set<T: Encodable>(_ key: String, _ value: T?) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            UserDefaults.standard.removeObject(forKey: key); return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}
