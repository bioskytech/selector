import Foundation

// MARK: - Arcs

/// A piecewise-linear curve over 0...1, with values roughly in -1...1.
struct ArcShape {
    let points: [(x: Double, y: Double)]

    func value(at p: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if p <= first.x { return first.y }
        for k in 1..<points.count where p <= points[k].x {
            let (x0, y0) = points[k - 1]
            let (x1, y1) = points[k]
            return y0 + (y1 - y0) * (p - x0) / (x1 - x0)
        }
        return last.y
    }

    static let wedding = ArcShape(points: [(0, -0.7), (0.12, -0.45), (0.3, 0.25), (0.4, -0.55), (0.5, 0.1), (0.65, 0.6), (0.85, 1), (0.95, 0.85), (1, 0.45)])
    static let party = ArcShape(points: [(0, -0.4), (0.2, 0.3), (0.4, 0.7), (0.55, 0.35), (0.75, 1), (0.9, 0.85), (1, 0.25)])
    static let sunset = ArcShape(points: [(0, -1), (0.3, -0.45), (0.6, 0.3), (0.85, 1), (1, 0.9)])
    static let peak = ArcShape(points: [(0, 0.45), (0.15, 0.85), (0.5, 0.75), (0.8, 1), (1, 0.8)])
}

// MARK: - Plans

/// Everything the planner needs for one build. `prefix`, `elapsed`, `energyOff`, `boost`
/// and `exclude` are used when re-planning the rest of a night that is already playing.
struct BuildConfig {
    var weights: [String: Int]
    var durS: Double
    var arc: ArcKind
    var clean: Bool
    var fam: Double
    var tw: [Float]?
    var seed: UInt64
    var xf: Double = 0
    var prefix: [Int] = []
    var elapsed: Double? = nil
    var energyOff: ((Double) -> Double)? = nil
    var boost: [String: Double]? = nil
    var exclude: Set<String>? = nil
    /// Per-track nudges from requests and from what was loved or skipped tonight.
    var favor: [Int: Double] = [:]
    /// Primary-artist indices not to play again tonight.
    var banned: Set<Int> = []
}

struct Plan {
    var seq: [Int]
    var pv: [Int]              // vibe index per catalog track (-1 outside the pool)
    var pool: [Int]
    var short: Bool
    var baseE: Double
    var amp: Double
    var weights: [String: Int]
    var arc: ArcKind
    var clean: Bool
    var fam: Double
    var tw: [Float]?
    var durS: Double
    var title: String
    var exclude: Set<String>? = nil
    var boost: [String: Double]? = nil
    var energyOff: ((Double) -> Double)? = nil
    var favor: [Int: Double] = [:]
    var banned: Set<Int> = []

    /// Sounds the plan was asked for, strongest first.
    var heads: [String] { weights.filter { $0.value >= 3 }.keys.sorted() }
    var soundsByWeight: [String] { weights.filter { $0.value > 0 }.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map { $0.key } }
}

struct Phase: Identifiable {
    let key: String
    let label: String
    let from: Int
    let to: Int
    var start: Double = 0
    var end: Double = 0
    var id: String { key }
}

struct Taste: Codable {
    var tw: [Float]
    var matched: [String]
    var total: Int
    var top: [String]
    var source: String
}

// MARK: - Deterministic RNG

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992.0 }
}

// MARK: - Planner

private struct Beam {
    var seq: [Int] = []
    var score: Double = 0
    var used: Set<Int> = []
    var titles: Set<String> = []
    var artistLast: [Int: Int] = [:]
    var artistCount: [Int: Int] = [:]
    var vibeCount: [Double]
    var block: Int = 0
    var time: Double = 0
    var short: Bool = false
}

final class SetPlanner {
    let cat: Catalog
    let camelot: [Camelot]
    let titleKey: [String]
    let vibeKeys: [String]
    let vibeIndex: [String: Int]
    let clubEnergy: ArcShape
    let clubTempo: ArcShape
    private let byArtist: [String: [Int]]
    private let artistIndex: [String: Int]
    private let tCoef: [Double]
    private let eCoef: [Double]
    private let camCoef: [Double]
    private let camIndex: [UInt8]      // key relation for every pair of the 24 keys

    init(catalog: Catalog) {
        cat = catalog
        let t = catalog.t
        let n = t.id.count
        camelot = (0..<n).map { Camelot(key: t.k[$0] % 12, mode: t.k[$0] >= 12 ? 1 : 0) }
        titleKey = (0..<n).map { Normalizer.titleKey(t.n[$0]) + "|" + String(t.a[$0]) }
        vibeKeys = catalog.vibes.map { $0.key }

        var vi: [String: Int] = [:]
        for (i, v) in catalog.vibes.enumerated() { vi[v.key] = i }
        vibeIndex = vi

        let all = catalog.arc.arc["all"]
        let eS = SetPlanner.smooth(all?.energy ?? Array(repeating: 0, count: 10))
        let eMax = max(eS.map { abs($0) }.max() ?? 1, 1e-6)
        var ep: [(x: Double, y: Double)] = [(0, eS[0] / eMax)]
        for k in 0..<eS.count { ep.append(((Double(k) + 0.5) / Double(eS.count), eS[k] / eMax)) }
        ep.append((1, (eS.last ?? 0) / eMax))
        clubEnergy = ArcShape(points: ep)

        let tS = SetPlanner.smooth(all?.tempo ?? Array(repeating: 0, count: 10))
        var tp: [(x: Double, y: Double)] = [(0, tS[0])]
        for k in 0..<tS.count { tp.append(((Double(k) + 0.5) / Double(tS.count), tS[k])) }
        tp.append((1, tS.last ?? 0))
        clubTempo = ArcShape(points: tp)

        var ba: [String: [Int]] = [:]
        for i in 0..<n {
            for a in t.ar[i].components(separatedBy: ", ") {
                let key = Normalizer.artist(a)
                if !key.isEmpty { ba[key, default: []].append(i) }
            }
        }
        byArtist = ba
        var ai: [String: Int] = [:]
        for (i, a) in catalog.artists.enumerated() { ai[Normalizer.artist(a)] = i }
        artistIndex = ai

        // The transition model, unpacked into arrays so scoring a pair of songs is a few lookups.
        let m = catalog.model
        tCoef = (0..<max(1, m.tbins.count - 1)).map { m.coef["t\($0)"] ?? 0 }
        eCoef = (0..<max(1, m.ebins.count - 1)).map { m.coef["e\($0)"] ?? 0 }
        var relNames: [String] = []
        var relCoef: [Double] = []
        var table = [UInt8](repeating: 0, count: 24 * 24)
        for a in 0..<24 {
            for b in 0..<24 {
                let rel = KeyRelation.between(Camelot(key: a % 12, mode: a >= 12 ? 1 : 0), Camelot(key: b % 12, mode: b >= 12 ? 1 : 0)).rawValue
                var idx = relNames.firstIndex(of: rel)
                if idx == nil { relNames.append(rel); relCoef.append(m.coef["cam_" + rel] ?? 0); idx = relNames.count - 1 }
                table[a * 24 + b] = UInt8(idx ?? 0)
            }
        }
        camCoef = relCoef
        camIndex = table
        cUp = m.coef["up_energy"] ?? 0
        cDance = m.coef["ad_dance"] ?? 0
        cVal = m.coef["ad_val"] ?? 0
        cLoud = m.coef["ad_loud"] ?? 0
        cInstr = m.coef["ad_instr"] ?? 0
    }
    private let cUp: Double, cDance: Double, cVal: Double, cLoud: Double, cInstr: Double

    /// Catalog tracks credited to an artist, by any spelling.
    func tracks(byArtist name: String) -> [Int] { byArtist[Normalizer.artist(name)] ?? [] }

    private static func smooth(_ a: [Double]) -> [Double] {
        guard a.count >= 3 else { return a }
        return a.indices.map { k in
            let lo = max(0, k - 1), hi = min(a.count - 1, k + 1)
            let s = a[lo...hi]
            return s.reduce(0, +) / Double(s.count)
        }
    }

    func shape(_ kind: ArcKind) -> ArcShape {
        switch kind {
        case .club: return clubEnergy
        case .wedding: return .wedding
        case .party: return .party
        case .sunset: return .sunset
        case .peak: return .peak
        }
    }

    func vibe(_ key: String) -> Catalog.Vibe? {
        guard let i = vibeIndex[key] else { return nil }
        return cat.vibes[i]
    }

    func vibeKey(of j: Int, in plan: Plan) -> String {
        let v = plan.pv[j]
        return v >= 0 && v < vibeKeys.count ? vibeKeys[v] : (vibeKeys.first ?? "pop")
    }

    private func energyMed(_ v: Int) -> Double { cat.vibes[v].energy_med ?? 0.6 }
    private func bpmMed(_ v: Int) -> Double { cat.vibes[v].bpm_med ?? 120 }

    // MARK: Learned transition model

    private func bin(_ edges: [Double], _ x: Double) -> Int {
        for k in 0..<(edges.count - 1) where x >= edges[k] && x < edges[k + 1] { return k }
        return edges.count - 2
    }

    /// Log-odds that a real DJ would play `j` after `i`.
    func logit(_ i: Int, _ j: Int) -> Double {
        let m = cat.model
        let t = cat.t
        var z = m.intercept
        z += tCoef[min(bin(m.tbins, tempoGapPercent(t.bpm[i], t.bpm[j])), tCoef.count - 1)]
        z += camCoef[Int(camIndex[(t.k[i] % 24) * 24 + (t.k[j] % 24)])]
        let de = t.e[j] - t.e[i]
        z += eCoef[min(bin(m.ebins, abs(de)), eCoef.count - 1)]
        z += cUp * max(0, de)
        z += cDance * abs(t.d[j] - t.d[i])
        z += cVal * abs(t.v[j] - t.v[i])
        z += cLoud * abs(t.l[j] - t.l[i]) / 20
        z += cInstr * abs(t.i[j] - t.i[i])
        return z
    }

    /// The transition in plain words; nil means a smooth blend the listener needn't know about.
    func transitionWord(_ i: Int, _ j: Int) -> String? {
        let t = cat.t
        let tp = tempoGapPercent(t.bpm[i], t.bpm[j])
        let rel = KeyRelation.between(camelot[i], camelot[j])
        let de = t.e[j] - t.e[i]
        if tp <= 3 && rel.isHarmonic { return nil }
        if tp <= 3 { return "Beat switch" }
        if tp <= 6 { return de > 0.08 ? "Bass drop" : "Bass swap" }
        if tp <= 12 { return de > 0 ? "Speed up" : "Loop and cut" }
        return de < -0.1 ? "Fade down" : "Echo out"
    }

    /// How long to blend out of each song: long when the next one is in key and on tempo,
    /// short when it's a hard switch. The last entry is unused.
    func blendLengths(_ plan: Plan) -> [Double] {
        let seq = plan.seq
        return seq.indices.map { k in
            guard k + 1 < seq.count else { return 4 }
            switch transitionWord(seq[k], seq[k + 1]) {
            case nil: return 10
            case "Beat switch": return 6
            case "Bass drop", "Bass swap": return 5
            case "Speed up", "Loop and cut": return 3
            default: return 2
            }
        }
    }

    // MARK: Build

    struct BuildResult {
        var seq: [Int]
        var pv: [Int]
        var pool: [Int]
        var short: Bool
        var baseE: Double
        var amp: Double
    }

    /// Plans a set. With a `prefix`, plans only the remainder after it (live steering).
    func build(_ cfg: BuildConfig) -> BuildResult? {
        let t = cat.t
        let n = cat.count
        let sel = cfg.weights
            .filter { $0.value > 0 && !(cfg.exclude?.contains($0.key) ?? false) }
            .sorted { $0.key < $1.key }
            .map { (key: $0.key, w: $0.value) }
        guard !sel.isEmpty else { return nil }
        let sumW = Double(sel.reduce(0) { $0 + $1.w })

        var share = Array(repeating: 0.0, count: cat.vibes.count)
        var mask = 0
        for s in sel {
            guard let v = vibeIndex[s.key] else { continue }
            share[v] = Double(s.w) / sumW
            mask |= 1 << v
        }
        if let boost = cfg.boost {
            for (k, b) in boost { if let v = vibeIndex[k] { share[v] += b } }
        }

        var pv = Array(repeating: -1, count: n)
        var pool: [Int] = []
        for i in 0..<n {
            if t.vm[i] & mask == 0 { continue }
            if cfg.clean && t.x[i] == 1 { continue }
            var best = -1, bw = -1
            for s in sel {
                guard let v = vibeIndex[s.key] else { continue }
                if t.vm[i] & (1 << v) != 0 && s.w > bw { bw = s.w; best = v }
            }
            pv[i] = best
            pool.append(i)
        }
        // Songs asked for by name or artist come along even when their sound wasn't picked.
        for (i, f) in cfg.favor where f >= 2 && i >= 0 && i < n && pv[i] < 0 {
            if cfg.clean && t.x[i] == 1 { continue }
            pv[i] = homeVibe(i, share: share)
            pool.append(i)
        }
        for j in cfg.prefix where j >= 0 && j < n && pv[j] < 0 { pv[j] = homeVibe(j, share: share) }
        guard !pool.isEmpty else { return nil }
        // How much each sound was asked for, 0...1: headliners own the peak, the rest fill the valleys.
        let maxW = Double(sel.map { $0.w }.max() ?? 1)
        var want = Array(repeating: 0.0, count: cat.vibes.count)
        for s in sel { if let v = vibeIndex[s.key] { want[v] = Double(s.w) / maxW } }
        // A song that also belongs to a regional sound nobody asked for (a Punjabi track tagged hip-hop
        // in an Afrobeats night) would stick out, so it has to earn its place.
        var foreignMask = 0
        for key in ["bollywood", "punjabi", "southindian", "mideast", "reggaeton", "latin", "afro", "kpop"] {
            if let v = vibeIndex[key], mask & (1 << v) == 0 { foreignMask |= 1 << v }
        }
        let favor = cfg.favor
        let banned = cfg.banned

        var baseE = 0.0
        for s in sel { if let v = vibeIndex[s.key] { baseE += energyMed(v) * Double(s.w) / sumW } }
        let amp = cfg.arc == .club ? 0.10 : 0.17
        let sh = shape(cfg.arc)
        let off = cfg.energyOff
        let tw = cfg.tw
        let fam = cfg.fam
        let durS = cfg.durS
        let xf = cfg.xf
        let nGuess = max(4, Int((durS / 200).rounded()))
        let maxArtist = max(2, Int((Double(nGuess) / 10).rounded(.up)))
        var rng = SplitMix64(seed: cfg.seed)

        func targetE(_ v: Int, _ p: Double) -> Double {
            min(max(energyMed(v) + amp * sh.value(at: p) + (off?(p) ?? 0), 0.22), 0.97)
        }
        func targetB(_ v: Int, _ p: Double) -> Double {
            let o = cfg.arc == .club ? clubTempo.value(at: p) : 3.5 * sh.value(at: p)
            return bpmMed(v) + o
        }
        func playSec(_ j: Int) -> Double { max(Double(t.dur[j]) - xf, 30) }

        func stepScore(_ b: Beam, _ j: Int, _ p: Double) -> Double {
            let cnt = b.seq.count
            let prev = b.seq.last ?? -1
            let v = pv[j]
            var s = 0.0
            if prev >= 0 { s += logit(prev, j) }
            s -= 4.0 * abs(t.e[j] - targetE(v, p))
            s -= 0.5 * min(abs(t.bpm[j] - targetB(v, p)) / 8, 2)
            let cur = cnt > 0 ? b.vibeCount[v] / Double(cnt) : 0
            s += 3.0 * (share[v] - cur) - 10.0 * max(0, cur - share[v] - 0.03)
            if prev >= 0 && pv[prev] == v && b.block < 4 { s += 0.35 }
            let arcNow = sh.value(at: p)
            s += 0.15 * arcNow * (energyMed(v) - baseE) / 0.15
            s += arcNow > 0 ? 1.1 * arcNow * (want[v] - 0.6) : 0.5 * arcNow * (want[v] - 0.6)
            if t.vm[j] & foreignMask != 0 && favor[j] == nil { s -= 1.6 }
            if let tw { s += 0.6 * Double(tw[j]) }
            if let f = favor[j] { s += f }
            // Open and close on songs people know: first and last impressions.
            if p > 0.93 || cnt == 0 { s += 1.4 * Double(t.p[j]) / 100 }
            s += (fam - 0.5) * 2.2 * (Double(t.p[j]) / 100) + 0.25 * t.d[j]
            return s + rng.unit() * 0.3
        }

        func ok(_ b: Beam, _ j: Int) -> Bool {
            if b.used.contains(j) || b.titles.contains(titleKey[j]) { return false }
            let a = t.a[j]
            if banned.contains(a) { return false }
            let cnt = b.seq.count
            if let last = b.artistLast[a], last > cnt - 6 { return false }
            return (b.artistCount[a] ?? 0) < maxArtist
        }

        // Seed the beam with the fixed prefix: songs already played, plus the one playing.
        var root = Beam(vibeCount: Array(repeating: 0, count: cat.vibes.count))
        for j in cfg.prefix {
            let cnt = root.seq.count
            root.seq.append(j)
            root.used.insert(j)
            root.titles.insert(titleKey[j])
            root.artistLast[t.a[j]] = cnt
            root.artistCount[t.a[j], default: 0] += 1
            root.vibeCount[pv[j]] += 1
            root.time += playSec(j)
        }
        if let elapsed = cfg.elapsed { root.time = elapsed }
        let prefixLen = root.seq.count

        let beamWidth = 5, topK = 8
        var beams = [root]
        var guardCount = 0
        while beams.contains(where: { $0.time < durS }) && guardCount < 200 {
            guardCount += 1
            var cand: [(beam: Int, j: Int, score: Double)] = []
            for bi in beams.indices {
                if beams[bi].time >= durS { cand.append((bi, -1, beams[bi].score)); continue }
                let b = beams[bi]
                let p = min(1, (b.time + 100) / durS)
                var top: [(j: Int, sc: Double)] = []
                for j in pool where ok(b, j) {
                    let sc = stepScore(b, j, p)
                    if top.count < topK {
                        top.append((j, sc)); top.sort { $0.sc > $1.sc }
                    } else if sc > top[topK - 1].sc {
                        top[topK - 1] = (j, sc); top.sort { $0.sc > $1.sc }
                    }
                }
                if top.isEmpty {
                    beams[bi].time = durS; beams[bi].short = true
                    cand.append((bi, -1, beams[bi].score)); continue
                }
                for c in top { cand.append((bi, c.j, b.score + c.sc)) }
            }
            cand.sort { $0.score > $1.score }
            var next: [Beam] = []
            var seen = Set<String>()
            var carried = Set<Int>()
            for c in cand {
                if next.count >= beamWidth { break }
                if c.j < 0 {
                    if !carried.contains(c.beam) { carried.insert(c.beam); next.append(beams[c.beam]) }
                    continue
                }
                let key = "\(c.j):\(beams[c.beam].seq.count)"
                if seen.contains(key) { continue }
                seen.insert(key)
                var nb = beams[c.beam]
                let j = c.j, cnt = nb.seq.count, v = pv[j]
                let sameVibe = cnt > 0 && pv[nb.seq[cnt - 1]] == v
                nb.seq.append(j)
                nb.score = c.score
                nb.used.insert(j)
                nb.titles.insert(titleKey[j])
                nb.artistLast[t.a[j]] = cnt
                nb.artistCount[t.a[j], default: 0] += 1
                nb.vibeCount[v] += 1
                nb.block = sameVibe ? nb.block + 1 : 1
                nb.time += playSec(j)
                next.append(nb)
            }
            beams = next
            if beams.isEmpty { break }
        }
        func perSong(_ b: Beam) -> Double { b.score / Double(max(1, b.seq.count - prefixLen)) }
        guard let best = beams.max(by: { perSong($0) < perSong($1) }) else { return nil }
        return BuildResult(seq: Array(best.seq.dropFirst(prefixLen)), pv: pv, pool: pool, short: best.short, baseE: baseE, amp: amp)
    }

    /// The sound a track belongs to when it wasn't picked for one: the most-wanted sound it carries.
    private func homeVibe(_ i: Int, share: [Double]) -> Int {
        var best = 0, bs = -1.0
        for v in cat.vibes.indices where cat.t.vm[i] & (1 << v) != 0 && share[v] > bs { bs = share[v]; best = v }
        return best
    }

    // MARK: Times, phases

    func startTimes(_ plan: Plan) -> [Double] {
        var t = 0.0
        return plan.seq.map { j in let s = t; t += Double(cat.t.dur[j]); return s }
    }

    func totalSeconds(_ plan: Plan) -> Double {
        plan.seq.reduce(0.0) { $0 + Double(cat.t.dur[$1]) }
    }

    /// Energy per song, smoothed over five songs.
    func smoothedEnergy(_ plan: Plan) -> [Double] {
        let e = plan.seq.map { cat.t.e[$0] }
        return e.indices.map { k in
            let s = e[max(0, k - 2)..<min(e.count, k + 3)]
            return s.reduce(0, +) / Double(s.count)
        }
    }

    /// Arrive / Build / Lift / Peak / Land, from the planned energy.
    func phases(_ plan: Plan) -> [Phase] {
        let n = plan.seq.count
        let st = startTimes(plan), tot = totalSeconds(plan)
        if n < 4 {
            return [Phase(key: "all", label: "The night", from: 0, to: n, start: 0, end: tot)]
        }
        let sm = smoothedEnergy(plan)
        let win = max(3, Int((Double(n) * 0.25).rounded()))
        var bestK = Int((Double(n) * 0.6).rounded()), bestV = -1.0
        var k = Int((Double(n) * 0.4).rounded())
        while k + win <= n {
            let v = sm[k..<(k + win)].reduce(0, +) / Double(win)
            if v > bestV { bestV = v; bestK = k }
            k += 1
        }
        let peakFrom = min(bestK, n - 1), peakTo = min(n, peakFrom + win)
        let liftFrom = max(Int((Double(n) * 0.3).rounded()), peakFrom - max(2, Int((Double(n) * 0.12).rounded())))
        let arriveTo = min(liftFrom - 1, max(2, Int((Double(n) * 0.2).rounded())))
        let landFrom = peakTo >= n - 1 ? n - 1 : peakTo
        var out = [
            Phase(key: "arrive", label: "Arrive", from: 0, to: arriveTo),
            Phase(key: "build", label: "Build", from: arriveTo, to: liftFrom),
            Phase(key: "lift", label: "Lift", from: liftFrom, to: peakFrom),
            Phase(key: "peak", label: "Peak", from: peakFrom, to: landFrom),
            Phase(key: "land", label: "Land", from: landFrom, to: n),
        ].filter { $0.to > $0.from && $0.from >= 0 }
        for i in out.indices {
            out[i].start = st[min(out[i].from, n - 1)]
            out[i].end = out[i].to < n ? st[out[i].to] : tot
        }
        return out
    }

    func phase(of k: Int, in plan: Plan) -> Phase? {
        let ph = phases(plan)
        return ph.first { k >= $0.from && k < $0.to } ?? ph.last
    }

    // MARK: The DJ explains the night

    func topArtists(_ plan: Plan, _ from: Int, _ to: Int, _ n: Int = 2, vibe: String? = nil) -> [String] {
        var c: [String: Double] = [:]
        var order: [String] = []
        let hi = min(to, plan.seq.count)
        guard from < hi else { return [] }
        for k in from..<hi {
            let j = plan.seq[k]
            if let vibe, vibeKey(of: j, in: plan) != vibe { continue }
            let a = Catalog.firstArtist(cat.t.ar[j])
            if c[a] == nil { order.append(a) }
            c[a, default: 0] += 1 + Double(plan.tw?[j] ?? 0)
        }
        if c.isEmpty && vibe != nil { return topArtists(plan, from, to, n) }
        return order.sorted { (c[$0] ?? 0) > (c[$1] ?? 0) }.prefix(n).map { $0 }
    }

    func topVibe(_ plan: Plan, _ from: Int, _ to: Int) -> String? {
        var c: [String: Int] = [:]
        var order: [String] = []
        let hi = min(to, plan.seq.count)
        guard from < hi else { return nil }
        for k in from..<hi {
            let v = vibeKey(of: plan.seq[k], in: plan)
            if c[v] == nil { order.append(v) }
            c[v, default: 0] += 1
        }
        return order.sorted { (c[$0] ?? 0) > (c[$1] ?? 0) }.first
    }

    func whenText(_ sec: Double, startedAt: Date?) -> String {
        if let startedAt { return "at " + Fmt.clock(startedAt.addingTimeInterval(sec)) }
        let m = Int((sec / 60).rounded())
        if m >= 25 && m <= 35 { return "around the half hour" }
        if m < 60 { return "about \(m) minutes in" }
        let h = Int(sec) / 3600, mm = (Int(sec) % 3600) / 60
        return String(format: "at %d:%02d", h, mm)
    }

    func djNote(_ plan: Plan, startedAt: Date?) -> String {
        let ph = phases(plan)
        let seq = plan.seq, n = seq.count
        guard n > 0 else { return "Pick a few sounds and I'll plan the night." }
        func get(_ k: String) -> Phase? { ph.first { $0.key == k } }
        guard let arrive = get("arrive"), let peak = get("peak") else {
            return "A \(Fmt.length(totalSeconds(plan))) set of \(n) songs. I'll read the room and keep it moving."
        }
        let t = cat.t
        let opener = Catalog.firstArtist(t.ar[seq[0]])
        let A = Array(topArtists(plan, arrive.from, arrive.to).filter { $0 != opener }.prefix(1))
        let overall = topVibe(plan, 0, n)
        let lift = get("lift"), build = get("build"), land = get("land")
        let liftV = lift.flatMap { topVibe(plan, $0.from, $0.to) }
        let peakV = topVibe(plan, peak.from, peak.to) ?? overall ?? "pop"
        let gentle = [ArcKind.wedding, .sunset, .club].contains(plan.arc)
        var s = gentle
            ? "I'll ease people in with \(Vibes.joinNames([opener] + A)) while they arrive"
            : "I'll open with \(Vibes.joinNames([opener] + A)) to get the room moving"
        if let build {
            let B = topArtists(plan, build.from, build.to)
            s += ", start building \(whenText(build.start, startedAt: startedAt)) with \(Vibes.joinNames(B))"
        }
        if let lift {
            let L = topArtists(plan, lift.from, lift.to, 1)
            if let liftV, liftV != overall {
                s += ", then lift into a run of \(Vibes.name(liftV)) \(whenText(lift.start, startedAt: startedAt)) so everyone's on the floor."
            } else {
                s += ", then lift it \(whenText(lift.start, startedAt: startedAt)) with \(Vibes.joinNames(L)) so everyone's on the floor."
            }
        } else {
            s += "."
        }
        let P = topArtists(plan, peak.from, peak.to, 2, vibe: peakV)
        var when = whenText(peak.start, startedAt: startedAt)
        if when.hasPrefix("at ") { when.removeFirst(3) }
        s += " From \(when) it's peak \(Vibes.name(peakV)) with \(Vibes.joinNames(P))"
        let closer = Catalog.shortTitle(t.n[seq[n - 1]])
        let soft = land != nil && t.e[seq[n - 1]] < t.e[seq[peak.from]] - 0.08
        s += ", and I'll land the night \(soft ? "softly " : "")with \(closer)."
        return s
    }

    // MARK: Swaps

    /// Best replacement for position `pos`, judged against its neighbours.
    func alternative(_ plan: Plan, pos: Int, exclude: Set<Int>) -> Int? {
        let t = cat.t
        let seq = plan.seq
        guard pos < seq.count, plan.durS > 0 else { return nil }
        let prev = pos > 0 ? seq[pos - 1] : -1
        let next = pos < seq.count - 1 ? seq[pos + 1] : -1
        let st = startTimes(plan)
        let p = (st[pos] + 60) / plan.durS
        let used = Set(seq)
        let titles = Set(seq.map { titleKey[$0] })
        var near = Set<Int>()
        for k in max(0, pos - 5)..<min(seq.count, pos + 6) where k != pos { near.insert(t.a[seq[k]]) }
        let sh = shape(plan.arc)

        var best = -1
        var bs = -Double.infinity
        for j in plan.pool {
            if used.contains(j) || exclude.contains(j) || titles.contains(titleKey[j]) || near.contains(t.a[j]) || plan.banned.contains(t.a[j]) { continue }
            let v = plan.pv[j]
            var s = 0.0
            if prev >= 0 { s += logit(prev, j) }
            if next >= 0 { s += logit(j, next) }
            let target = min(max(energyMed(v) + plan.amp * sh.value(at: p), 0.22), 0.97)
            s -= 4 * abs(t.e[j] - target)
            if let tw = plan.tw { s += 0.6 * Double(tw[j]) }
            if let f = plan.favor[j] { s += f }
            s += (plan.fam - 0.5) * 2.2 * (Double(t.p[j]) / 100)
            if s > bs { bs = s; best = j }
        }
        return best >= 0 ? best : nil
    }

    // MARK: Taste

    /// Turns a ranked list of artist names into per-track weights, using learned artist neighbours.
    func taste(from names: [String], source: String) -> Taste? {
        var tw = Array(repeating: Float(0), count: cat.count)
        var matched: [String] = []
        var affinity: [String: Double] = [:]
        for (r, name) in names.enumerated() {
            let w = 1 - 0.6 * Double(r) / Double(max(1, names.count - 1))
            let key = Normalizer.artist(name)
            guard let tracks = byArtist[key] else { continue }
            matched.append(name)
            for i in tracks {
                tw[i] = max(tw[i], Float(w))
                for (vi, v) in cat.vibes.enumerated() where cat.t.vm[i] & (1 << vi) != 0 {
                    affinity[v.key, default: 0] += w
                }
            }
            if let ai = artistIndex[key], ai < cat.an.count {
                for nb in cat.an[ai] where nb < cat.artists.count {
                    let nk = Normalizer.artist(cat.artists[nb])
                    for i in byArtist[nk] ?? [] { tw[i] = max(tw[i], Float(0.45 * w)) }
                }
            }
        }
        guard !matched.isEmpty else { return nil }
        let top = affinity.sorted { $0.value > $1.value }.prefix(4).map { $0.key }
        return Taste(tw: tw, matched: matched, total: names.count, top: top, source: source)
    }
}
