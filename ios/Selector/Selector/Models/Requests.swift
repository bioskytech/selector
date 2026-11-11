import Foundation

/// One thing the listener asked the DJ for.
enum DJIntent: Equatable {
    case energy(up: Bool)
    case familiar
    case surprise
    case more(vibe: String)
    case less(vibe: String?)          // nil = whatever is playing now
    case wrap(minutes: Int)
    case playSong(track: Int)
    case moreArtist(name: String)
    case lessArtist(name: String)

    /// Stable key, used to highlight the chip that was tapped.
    var key: String {
        switch self {
        case .energy(let up): return up ? "up" : "down"
        case .familiar: return "familiar"
        case .surprise: return "surprise"
        case .more(let v): return "more|" + v
        case .less(let v): return "less|" + (v ?? "")
        case .wrap(let m): return "wrap|\(m)"
        case .playSong(let j): return "song|\(j)"
        case .moreArtist(let n): return "artist|" + n
        case .lessArtist(let n): return "noartist|" + n
        }
    }
}

/// What a typed description of the night turned into.
struct BriefResult {
    var occasion: String?
    var weights: [String: Int] = [:]
    var minutes: Int?
    var clean: Bool?
    var fam: Double?
    var arc: ArcKind?
    var artists: [String] = []

    var understoodAnything: Bool {
        occasion != nil || !weights.isEmpty || minutes != nil || clean != nil || fam != nil || !artists.isEmpty
    }
}

/// Understands plain-language requests without a network: sounds, artists, songs, energy, time.
final class RequestParser {
    private let cat: Catalog
    private var artistByWords: [String: String] = [:]     // "diljit dosanjh" -> display name
    private var songByWords: [String: Int] = [:]          // "brown munde" -> most popular track
    private static let aliases: [(words: String, vibe: String)] = [
        ("bollywood", "bollywood"), ("hindi", "bollywood"), ("desi", "bollywood"), ("filmi", "bollywood"),
        ("punjabi", "punjabi"), ("bhangra", "punjabi"), ("dhol", "punjabi"),
        ("telugu", "southindian"), ("tamil", "southindian"), ("tollywood", "southindian"), ("kollywood", "southindian"),
        ("south indian", "southindian"), ("kuthu", "southindian"), ("malayalam", "southindian"), ("kannada", "southindian"),
        ("arabic", "mideast"), ("persian", "mideast"), ("turkish", "mideast"), ("middle east", "mideast"),
        ("middle eastern", "mideast"), ("farsi", "mideast"), ("khaleeji", "mideast"), ("iranian", "mideast"), ("dabke", "mideast"),
        ("reggaeton", "reggaeton"), ("regueton", "reggaeton"), ("perreo", "reggaeton"), ("dembow", "reggaeton"),
        ("latin", "latin"), ("salsa", "latin"), ("bachata", "latin"), ("cumbia", "latin"), ("merengue", "latin"), ("spanish", "latin"),
        ("afrobeats", "afro"), ("afrobeat", "afro"), ("afro", "afro"), ("amapiano", "afro"), ("naija", "afro"),
        ("k pop", "kpop"), ("kpop", "kpop"), ("j pop", "kpop"), ("jpop", "kpop"), ("korean", "kpop"),
        ("techno", "techno"), ("house", "house"), ("deep house", "house"), ("tech house", "house"), ("trance", "trance"),
        ("edm", "edm"), ("big room", "edm"), ("festival", "edm"), ("electronic", "edm"),
        ("drum and bass", "bass"), ("drum n bass", "bass"), ("dnb", "bass"), ("dubstep", "bass"), ("jungle", "bass"),
        ("disco", "disco"), ("funk", "disco"), ("funky", "disco"), ("nu disco", "disco"),
        ("hip hop", "hiphop"), ("hiphop", "hiphop"), ("rap", "hiphop"), ("r&b", "hiphop"), ("rnb", "hiphop"), ("trap", "hiphop"),
        ("pop", "pop"), ("top 40", "pop"), ("chart", "pop"),
    ]
    private static let stopTitles: Set<String> = [
        "up", "down", "more", "energy", "play", "next", "stop", "dance", "party", "tonight", "the night", "slow", "faster",
        "something", "music", "song", "songs", "love", "please", "now", "one more", "hello", "thank you", "home",
    ]

    /// Everyday words that also happen to be artist names.
    private static let common: Set<String> = stopTitles.union([
        "less", "some", "want", "this", "that", "hear", "skip", "slower", "family", "everyone", "chill", "house", "latin",
        "disco", "wrap", "know", "hits", "classic", "classics", "future", "blue", "black", "white", "young", "little", "after",
        "before", "night", "hour", "hours", "minutes", "energy", "bring", "something", "anything", "nothing", "again", "there",
        "friends", "people", "girls", "boys", "kids", "little", "mostly", "mainly", "heavy", "clean", "explicit", "wedding",
        "birthday", "sunset", "dinner", "rooftop", "warehouse", "techno", "trance", "reggaeton", "punjabi", "bollywood",
    ])

    init(catalog: Catalog) {
        cat = catalog
        for name in catalog.artists {
            let w = RequestParser.words(name)
            if w.count >= 4 && !RequestParser.common.contains(w) { artistByWords[w] = name }
        }
        // First names people actually say: "more Diljit", "some Karan".
        var firstNames: [String: [String]] = [:]
        for name in catalog.artists {
            let parts = RequestParser.words(name).split(separator: " ")
            if parts.count >= 2, let f = parts.first, f.count >= 5, !RequestParser.common.contains(String(f)) { firstNames[String(f), default: []].append(name) }
        }
        for (f, names) in firstNames where names.count == 1 && artistByWords[f] == nil { artistByWords[f] = names[0] }

        let t = catalog.t
        for j in 0..<catalog.count {
            let w = RequestParser.words(Catalog.shortTitle(t.n[j]))
            guard w.count >= 3, !RequestParser.stopTitles.contains(w) else { continue }
            if let old = songByWords[w], t.p[old] >= t.p[j] { continue }
            songByWords[w] = j
        }
    }

    /// Lowercase words, accents folded, punctuation dropped (but "&" kept for "r&b").
    static func words(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        var out = ""
        for u in folded.unicodeScalars {
            if (u.isASCII && CharacterSet.alphanumerics.contains(u)) || u == "&" { out.unicodeScalars.append(u) }
            else if u == "-" || u == "'" || u == "’" { continue }
            else { out += " " }
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    private func has(_ text: String, _ pattern: String) -> Bool {
        text.range(of: "(^| )(" + pattern + ")( |$)", options: .regularExpression) != nil
    }

    private func vibes(in text: String) -> [String] {
        var found: [String] = []
        // Hyphenated names lose their hyphen in `words`, so "hip-hop" arrives as "hiphop" and "k-pop" as "kpop".
        for a in RequestParser.aliases.sorted(by: { $0.words.count > $1.words.count }) {
            let w = a.words.replacingOccurrences(of: "&", with: "\\&")
            if has(text, w), !found.contains(a.vibe) {
                // "pop" inside "k pop" was already claimed by the longer alias.
                if a.vibe == "pop" && found.contains("kpop") && !has(text.replacingOccurrences(of: "k pop", with: ""), "pop") { continue }
                found.append(a.vibe)
            }
        }
        return found
    }

    /// Longest runs of words that name an artist or a song.
    private func entities(in text: String) -> (artists: [String], songs: [Int]) {
        let w = text.split(separator: " ").map(String.init)
        var artists: [String] = []
        var songs: [Int] = []
        var i = 0
        while i < w.count {
            var matched = 0
            for len in stride(from: min(6, w.count - i), through: 1, by: -1) {
                let phrase = w[i..<(i + len)].joined(separator: " ")
                if let name = artistByWords[phrase] {
                    if !artists.contains(name) { artists.append(name) }
                    matched = len
                    break
                }
                if len >= 2, let j = songByWords[phrase] {
                    if !songs.contains(j) { songs.append(j) }
                    matched = len
                    break
                }
            }
            i += max(1, matched)
        }
        return (artists, songs)
    }

    private func singleWordSong(in text: String) -> Int? {
        // "play kesariya": one-word titles only count right after a play verb.
        guard let r = text.range(of: #"(^| )(play|put on|queue|drop|spin) (the song |some )?([a-z0-9]+)"#, options: .regularExpression) else { return nil }
        guard let last = text[r].split(separator: " ").last else { return nil }
        return songByWords[String(last)]
    }

    // MARK: Requests while the night plays

    func parse(_ raw: String) -> [DJIntent] {
        let text = RequestParser.words(raw)
        guard !text.isEmpty else { return [] }
        var out: [DJIntent] = []
        func add(_ i: DJIntent) { if !out.contains(i) { out.append(i) } }

        // Split "more punjabi and wrap up in 20" into clauses, but keep "drum and bass" together.
        let protected = text.replacingOccurrences(of: "drum and bass", with: "dnb").replacingOccurrences(of: "sing along", with: "singalong")
        let clauses = protected.components(separatedBy: " and ").flatMap { $0.components(separatedBy: " then ") }
            .flatMap { $0.components(separatedBy: " but ") }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        for c in clauses {
            let negative = has(c, "no more|no|less|fewer|enough|skip|stop|without|not so much|tired of|sick of|done with|drop the|lose the|cut the")

            if has(c, "wrap|wrap up|wind down|last song|last few|end it|end the night|finish|close out|closing|bring it home|call it") ||
               c.range(of: #"\d+ ?(min|mins|minutes|minute) (left|more)"#, options: .regularExpression) != nil {
                var minutes = 20
                if let r = c.range(of: #"\d+"#, options: .regularExpression), let m = Int(c[r]) { minutes = min(max(m, 5), 120) }
                else if has(c, "half an hour|half hour") { minutes = 30 }
                else if has(c, "an hour|one hour") { minutes = 60 }
                else if has(c, "last song") { minutes = 5 }
                add(.wrap(minutes: minutes))
                continue
            }

            let vs = vibes(in: c)
            let ent = entities(in: c)
            for v in vs { add(negative ? .less(vibe: v) : .more(vibe: v)) }
            for a in ent.artists { add(negative ? .lessArtist(name: a) : .moreArtist(name: a)) }
            if !negative {
                let playVerb = has(c, "play|put on|queue|drop|spin|next|request|hear|want")
                for j in ent.songs where playVerb || ent.artists.isEmpty { add(.playSong(track: j)) }
                if ent.songs.isEmpty, ent.artists.isEmpty, let j = singleWordSong(in: c) { add(.playSong(track: j)) }
            }
            if !vs.isEmpty || !ent.artists.isEmpty || !ent.songs.isEmpty { continue }

            if negative && has(c, "this|this vibe|this stuff|this one|these") { add(.less(vibe: nil)); continue }

            // The room, described.
            if has(c, "aunties|aunty|uncles|parents|grandparents|elders|family|everyone|everybody|crowd pleaser|crowd pleasers|singalong|wedding classics") {
                add(.familiar)
            }
            if has(c, "dead|boring|bored|asleep|sleepy|sitting|nobody|no one|empty|flat|lame|wake") { add(.energy(up: true)); add(.familiar) }
            if has(c, "too loud|too much|too fast|too hard|too intense|headache|breather|break|talk|chat|dinner|eating|romantic|slow dance|couples") {
                add(.energy(up: false))
            }

            let down = has(c, "slow|slower|chill|chiller|mellow|calm|calmer|softer|quieter|lower|down|easy|ease|relax|cool it|cool down|tone it")
            let up = has(c, "energy|hype|turn up|turn it up|louder|faster|harder|up|bang|bangers|banger|lift|dance|dancing|peak|party|pump|fire|lit|go off|wild|crazy")
            if down && !(up && !negative && !has(c, "down|slow|slower|lower|less")) { add(.energy(up: false)) }
            else if up { add(.energy(up: !negative)) }

            if has(c, "know|familiar|hits|hit|classic|classics|popular|famous|throwback|throwbacks|old school|favorites|favourites|anthems") {
                add(negative ? .surprise : .familiar)
            } else if has(c, "surprise|deep cut|deep cuts|new|discover|underground|different|fresh|unexpected|rare|obscure|weird") {
                add(.surprise)
            }
        }
        return out
    }

    // MARK: Describing the night up front

    func parseBrief(_ raw: String) -> BriefResult {
        let text = RequestParser.words(raw)
        var r = BriefResult()
        guard !text.isEmpty else { return r }

        let occasions: [(pattern: String, key: String)] = [
            ("sangeet|mehndi|mehendi|haldi|baraat|shaadi|wedding|reception|garba|diwali|eid|navratri", "sangeet"),
            ("warehouse|rave|underground", "techno"),
            ("rooftop|pool party|beach", "reggaeton"),
            ("sunset|golden hour|sundowner", "sunset"),
            ("dinner|brunch|cocktail|cocktails", "dinner"),
            ("house party|birthday|bday|pregame|pre game|afterparty|after party|kickback|game night|friends over|housewarming|party", "party"),
        ]
        for o in occasions where has(text, o.pattern) { r.occasion = o.key; break }
        if has(text, "workout|gym|run|running|spin class") { r.arc = .peak }

        // How long.
        if let m = text.range(of: #"(\d+) ?(h|hr|hrs|hour|hours)( (\d+))?"#, options: .regularExpression) {
            let nums = text[m].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            if let h = nums.first { r.minutes = h * 60 + (nums.count > 1 ? nums[1] : 0) }
        } else if let m = text.range(of: #"(\d+) ?(m|min|mins|minute|minutes)"#, options: .regularExpression) {
            r.minutes = Int(text[m].prefix { $0.isNumber })
        } else if has(text, "half an hour|half hour") { r.minutes = 30 }
        else if has(text, "an hour|one hour") { r.minutes = 60 }
        else if has(text, "couple of hours|couple hours|two hours") { r.minutes = 120 }
        else if has(text, "three hours") { r.minutes = 180 }
        else if has(text, "all night|whole night") { r.minutes = 240 }
        if let m = text.range(of: #"(till|until|til|to|ends at|end at) (midnight|\d{1,2}( ?\d\d)? ?(am|pm)?)"#, options: .regularExpression) {
            if let mins = RequestParser.minutesUntil(String(text[m])) { r.minutes = mins }
        }
        if let m = r.minutes { r.minutes = min(max((m + 14) / 15 * 15, 30), 360) }

        // Which sounds, and how much of each.
        let strong = "mostly|mainly|lots of|heavy on|heavy|all|only|pure|strictly|big on|tons of|primarily|focus on"
        let light = "some|a little|a bit of|bit of|little|touch of|sprinkle of|sprinkle|few|occasional|hint of|dash of|maybe"
        var order: [String] = []
        for a in RequestParser.aliases.sorted(by: { $0.words.count > $1.words.count }) {
            let w = a.words.replacingOccurrences(of: "&", with: "\\&")
            guard has(text, w), r.weights[a.vibe] == nil else { continue }
            if a.vibe == "house", has(text, "house party") && !has(text.replacingOccurrences(of: "house party", with: ""), "house") { continue }
            if a.vibe == "pop", has(text, "k pop|j pop") && !has(text.replacingOccurrences(of: "k pop", with: "").replacingOccurrences(of: "j pop", with: ""), "pop") { continue }
            if a.vibe == "edm", a.words == "festival" { continue }
            if has(text, "(no|not|without|skip|except) (any )?" + w) { continue }
            if has(text, "(" + strong + ") (the )?" + w) { r.weights[a.vibe] = 3 }
            else if has(text, "(" + light + ") (the )?" + w) { r.weights[a.vibe] = 1 }
            else { r.weights[a.vibe] = 2 }
            order.append(a.vibe)
        }
        // With no emphasis given, the first sound named leads.
        if !r.weights.isEmpty, !r.weights.values.contains(3) {
            let lead = firstMentioned(order, in: text)
            r.weights[lead] = 3
        }
        for (k, v) in r.weights where v == 2 { r.weights[k] = 1 }

        if has(text, "family|kids|children|parents|aunties|uncles|grandparents|clean|pg|office|work party|colleagues") { r.clean = true }
        if has(text, "explicit|uncensored|adults only|no kids|dirty") { r.clean = false }
        if has(text, "hits|know|singalong|sing along|classics|classic|crowd pleasers|familiar|popular|throwbacks|anthems|aunties|everyone") { r.fam = 0.85 }
        if has(text, "deep cuts|underground|surprise|new stuff|discover|obscure|different") { r.fam = 0.4 }

        r.artists = entities(in: text).artists
        return r
    }

    private func firstMentioned(_ vibes: [String], in text: String) -> String {
        var best = vibes[0]
        var bestAt = text.endIndex
        for a in RequestParser.aliases where vibes.contains(a.vibe) {
            if let r = text.range(of: "(^| )" + a.words.replacingOccurrences(of: "&", with: "\\&") + "( |$)", options: .regularExpression), r.lowerBound < bestAt {
                bestAt = r.lowerBound
                best = a.vibe
            }
        }
        return best
    }

    /// "till midnight", "until 2am", "to 11 30 pm": minutes from now.
    static func minutesUntil(_ phrase: String, now: Date = Date()) -> Int? {
        let cal = Calendar.current
        var hour: Int, minute = 0
        if phrase.contains("midnight") { hour = 0 }
        else {
            let nums = phrase.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
            guard let h = nums.first, h <= 24 else { return nil }
            hour = h
            if nums.count > 1 { minute = min(nums[1], 59) }
            if phrase.contains("pm"), hour < 12 { hour += 12 }
            else if phrase.contains("am"), hour == 12 { hour = 0 }
            else if !phrase.contains("am"), !phrase.contains("pm"), hour <= 6 { /* small hours */ }
            else if !phrase.contains("am"), !phrase.contains("pm"), hour < 12 { hour += 12 }
        }
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour % 24
        comps.minute = minute
        guard var target = cal.date(from: comps) else { return nil }
        if target <= now { target = target.addingTimeInterval(86400) }
        let mins = Int(target.timeIntervalSince(now) / 60)
        return mins > 0 && mins <= 12 * 60 ? mins : nil
    }
}
