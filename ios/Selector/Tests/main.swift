import Foundation

// A quick look at what the DJ understands and plans. Run by CI; output is read by a person.
let path = CommandLine.arguments[1]
let cat = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
let planner = SetPlanner(catalog: cat)
let parser = RequestParser(catalog: cat)

func show(_ i: DJIntent) -> String {
    switch i {
    case .playSong(let j): return "play[\(cat.t.n[j]) / \(cat.t.ar[j])]"
    default: return i.key
    }
}
print("== requests")
for s in ["more energy", "less energy", "slow it down after this", "more hip-hop", "more k-pop", "something popular",
          "no more punjabi", "more Diljit", "play Brown Munde", "play kesariya next", "no more Badshah please",
          "more punjabi and wrap up in 15 minutes", "the aunties want to dance", "everyone's sitting down",
          "too loud, people are eating", "some AP Dhillon then bring it down", "last song", "30 minutes left",
          "throw in some reggaeton", "enough of this", "skip this vibe", "surprise us", "drum and bass please",
          "play something by Bad Bunny", "can we hear Tum Hi Ho", "more r&b", "asdf qwerty"] {
    print("  \(s)  ->  \(parser.parse(s).map(show).joined(separator: ", "))")
}
print("== briefs")
for s in ["Sangeet for 80 people, mostly Punjabi with some Bollywood, three hours, family friendly",
          "house party till 2am, hip hop and afrobeats, lots of hits",
          "2 hour warehouse techno, deep cuts", "rooftop sunset, reggaeton heavy, a little house, 90 min",
          "dinner party with disco and some pop, kids around", "k-pop birthday for 1 hour",
          "something for my Diljit and Karan Aujla loving friends"] {
    let r = parser.parseBrief(s)
    print("  \(s)\n     -> occasion=\(r.occasion ?? "-") weights=\(r.weights.sorted { $0.key < $1.key }) minutes=\(r.minutes.map(String.init) ?? "-") clean=\(r.clean.map { "\($0)" } ?? "-") fam=\(r.fam.map { "\($0)" } ?? "-") artists=\(r.artists)")
}
print("== plans")
for o in Occasion.all {
    let t0 = Date()
    let cfg = BuildConfig(weights: o.weights, durS: Double(o.minutes * 60), arc: o.arc, clean: o.clean, fam: o.fam, tw: nil, seed: 7)
    guard let r = planner.build(cfg) else { print("  \(o.key): no plan"); continue }
    let ms = Int(Date().timeIntervalSince(t0) * 1000)
    let plan = Plan(seq: r.seq, pv: r.pv, pool: r.pool, short: r.short, baseE: r.baseE, amp: r.amp, weights: o.weights, arc: o.arc, clean: o.clean, fam: o.fam, tw: nil, durS: Double(o.minutes * 60), title: o.label)
    let ph = planner.phases(plan).map { "\($0.label) \($0.from)-\($0.to)" }.joined(separator: " | ")
    var smooth = 0
    for k in 1..<max(1, r.seq.count) where planner.transitionWord(r.seq[k - 1], r.seq[k]) == nil { smooth += 1 }
    print("  \(o.key): \(r.seq.count) songs in \(ms) ms, pool \(r.pool.count), smooth blends \(smooth), phases: \(ph)")
    print("     \(planner.djNote(plan, startedAt: nil))")
}
