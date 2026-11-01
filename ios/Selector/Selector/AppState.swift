import Foundation
import MusicKit
import Observation
import SwiftUI

enum Route: Hashable {
    case brief, plan, songs, playing, recap
}

enum Sheet: String, Identifiable {
    case occasion, length, crowd, taste, connect, steer
    var id: String { rawValue }
}

/// The app: settings, the current night, Apple Music, navigation.
@Observable @MainActor
final class AppState {
    var catalog: Catalog?
    var planner: SetPlanner?
    var settings: Settings = Store.get("selector.settings", as: Settings.self) ?? Settings()
    var taste: Taste? = Store.get("selector.taste", as: Taste.self)
    var nights: [Recap] = Store.get("selector.nights", as: [Recap].self) ?? []
    var night: Night?
    var recap: Recap?

    var path: [Route] = []
    var sheet: Sheet?
    var toast: String?
    var showOffer = false
    var phaseFilter = "all"
    var steerReply: String?
    var steerChosen: String?

    var authorized = MusicAuthorization.currentStatus == .authorized
    var subscribed: Bool?
    var pendingStart = 0

    let player = Player()
    @ObservationIgnored private let matcher = AppleMusicMatcher()
    @ObservationIgnored private var resolveQueue: [Int] = []
    @ObservationIgnored private var resolveClaimed: Set<Int> = []
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init() {
        player.onTrack = { [weak self] k in self?.trackStarted(k) }
        player.onFinish = { [weak self] in self?.finishNight() }
    }

    // MARK: Lifecycle

    func load() async {
        guard catalog == nil else { return }
        do {
            let cat = try await Task.detached(priority: .userInitiated) { try Catalog.load() }.value
            catalog = cat
            planner = SetPlanner(catalog: cat)
        } catch {
            say("Couldn't load the music data. \(error.localizedDescription)")
            return
        }
        restoreNight()
        if authorized { await checkSubscription() }
    }

    var current: Route? { path.last }

    func go(_ r: Route) {
        sheet = nil
        if path.last != r { path.append(r) }
    }
    func back() { sheet = nil; if !path.isEmpty { path.removeLast() } }
    func home() { sheet = nil; path.removeAll() }

    func say(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((1_600 + text.count * 30) * 1_000_000))
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    // MARK: Settings

    func saveSettings() { Store.set("selector.settings", settings) }

    func applyOccasion(_ key: String) {
        guard let o = Occasion.named(key) else { return }
        settings.apply(o)
        saveSettings()
    }

    func toggleVibe(_ key: String) {
        if (settings.weights[key] ?? 0) > 0 { settings.weights.removeValue(forKey: key) } else { settings.weights[key] = 1 }
        settings.occasion = Occasion.matching(settings.weights)?.key
        saveSettings()
    }

    /// Make a sound the headliner (at most two).
    func starVibe(_ key: String) {
        if (settings.weights[key] ?? 0) >= 3 {
            settings.weights[key] = 1
        } else {
            let heads = settings.weights.filter { $0.value >= 3 }.keys.sorted()
            if heads.count >= 2, let drop = heads.first {
                settings.weights[drop] = 1
                say("\(Vibes.name(drop)) is no longer a headliner")
            }
            settings.weights[key] = 3
        }
        settings.occasion = Occasion.matching(settings.weights)?.key
        saveSettings()
    }

    func setMinutes(_ m: Int) { settings.minutes = m; saveSettings() }
    func setClean(_ on: Bool) { settings.clean = on; saveSettings() }
    func setFamiliar(_ known: Bool) { settings.fam = known ? 0.85 : 0.4; saveSettings() }
    func setUseTaste(_ on: Bool) { settings.useTaste = on; saveSettings() }

    func endsAt(minutes: Int) -> String {
        Fmt.clock(Fmt.roundedNow().addingTimeInterval(Double(minutes * 60)))
    }

    // MARK: Planning

    private var tasteWeights: [Float]? { settings.useTaste ? taste?.tw : nil }

    private func newPlan() -> Plan? {
        guard let planner else { return nil }
        let tw = tasteWeights
        let cfg = BuildConfig(weights: settings.weights, durS: Double(settings.minutes * 60), arc: settings.arc,
                              clean: settings.clean, fam: settings.fam, tw: tw, seed: settings.seed)
        guard let r = planner.build(cfg) else { return nil }
        return Plan(seq: r.seq, pv: r.pv, pool: r.pool, short: r.short, baseE: r.baseE, amp: r.amp,
                    weights: settings.weights, arc: settings.arc, clean: settings.clean, fam: settings.fam,
                    tw: tw, durS: Double(settings.minutes * 60), title: settings.title)
    }

    @discardableResult
    func planNight() -> Bool {
        guard let plan = newPlan() else { say("Pick at least one sound"); return false }
        player.stop()
        let n = Night(plan: plan)
        night = n
        recap = nil
        phaseFilter = "all"
        Task { await prepareNight(n) }
        return true
    }

    func newTake() {
        if player.isActive { say("The night's already playing. Use Tell your DJ instead."); return }
        settings.seed = settings.seed &* 6364136223846793005 &+ 1442695040888963407
        saveSettings()
        planNight()
    }

    /// Ask for Apple Music once, then find every song so the plan shows real artwork.
    private func prepareNight(_ n: Night) async {
        if MusicAuthorization.currentStatus == .notDetermined {
            _ = await ensureAuthorized(quiet: true)
        }
        if authorized { await resolveNight(n) }
    }

    func clock(at k: Int) -> Date {
        guard let night, let planner else { return Date() }
        let st = planner.startTimes(night.plan)
        return night.startOrNow.addingTimeInterval(k < st.count ? st[k] : 0)
    }

    func clock(afterSeconds s: Double) -> Date {
        (night?.startOrNow ?? Fmt.roundedNow()).addingTimeInterval(s)
    }

    var planStatus: String {
        guard let night else { return "" }
        if night.resolving { return "Finding your songs on Apple Music…" }
        if !night.resolveNote.isEmpty { return night.resolveNote }
        if night.resolved { return "All \(night.plan.seq.count) songs found on Apple Music." }
        return authorized ? "" : "Allow Apple Music access to hear it."
    }

    // MARK: Apple Music

    /// Asks for Apple Music access. With `quiet`, a refusal says nothing.
    func ensureAuthorized(quiet: Bool = false) async -> Bool {
        if MusicAuthorization.currentStatus == .authorized { authorized = true; return true }
        let status = await MusicAuthorization.request()
        authorized = status == .authorized
        if !authorized && !quiet {
            say("Selector needs Apple Music access to find and play songs. Allow it in Settings → Privacy & Security → Media & Apple Music.")
        }
        return authorized
    }

    func checkSubscription() async {
        if let sub = try? await MusicSubscription.current {
            subscribed = sub.canPlayCatalogContent
        } else {
            subscribed = false
        }
    }

    /// Finds every song of the night on Apple Music, swapping in close fits when one is missing.
    func resolveNight(_ n: Night) async {
        guard catalog != nil, planner != nil, authorized, !n.resolving else { return }
        n.resolving = true
        n.resolveNote = ""
        resolveQueue = n.am.indices.filter { n.am[$0].isPending }
        resolveClaimed = []
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask { @MainActor [weak self] in
                    guard let self else { return }
                    while !self.resolveQueue.isEmpty, self.night === n {
                        let k = self.resolveQueue.removeFirst()
                        await self.resolveOne(k, in: n)
                    }
                }
            }
        }
        n.resolving = false
        guard night === n else { return }
        let keep = n.am.indices.filter { n.am[$0].song != nil }
        let dropped = n.am.count - keep.count
        if dropped > 0 {
            n.plan.seq = keep.map { n.plan.seq[$0] }
            n.am = keep.map { n.am[$0] }
            n.replaced = Set(n.replaced.filter { keep.contains($0) }.compactMap { keep.firstIndex(of: $0) })
        }
        n.resolved = true
        n.resolveNote = dropped > 0
            ? "\(dropped) song\(dropped > 1 ? "s" : "") wasn't on Apple Music, so your DJ replaced \(dropped > 1 ? "them" : "it")."
            : ""
        if player.isActive { await player.update(songs: n.songs) }
    }

    private func resolveOne(_ k: Int, in n: Night) async {
        guard let cat = catalog, let planner, k < n.plan.seq.count else { return }
        let clean = n.plan.clean
        let j = n.plan.seq[k]
        var hit = await matcher.find(track: j, in: cat, clean: clean)
        var tried: Set<Int> = [j]
        var tries = 0
        while hit == nil && tries < 6 && night === n {
            let exclude = tried.union(resolveClaimed).union(Set(n.plan.seq))
            guard let alt = planner.alternative(n.plan, pos: k, exclude: exclude) else { break }
            tried.insert(alt)
            resolveClaimed.insert(alt)
            hit = await matcher.find(track: alt, in: cat, clean: clean)
            if hit != nil, k < n.plan.seq.count {
                n.plan.seq[k] = alt
                n.replaced.insert(k)
            }
            tries += 1
        }
        guard k < n.am.count else { return }
        if let hit { n.am[k] = .found(hit) } else { n.am[k] = .missing }
    }

    // MARK: Starting the night

    func startNight(from k: Int = 0) async {
        if night == nil { guard planNight() else { return } }
        guard let night else { return }
        if player.isActive { go(.playing); return }
        guard await ensureAuthorized() else { return }
        if night.resolving { say("Still finding your songs. One moment."); return }
        if !night.resolved { await resolveNight(night) }
        guard night.am.contains(where: { $0.song != nil }) else {
            say("None of these songs are on Apple Music here. Try other sounds."); return
        }
        if subscribed == nil { await checkSubscription() }
        if subscribed == true {
            await play(.full, from: k)
        } else {
            pendingStart = k
            sheet = .connect
        }
    }

    func play(_ mode: Player.Mode, from k: Int) async {
        guard let night, let planner else { return }
        sheet = nil
        if night.startedAt == nil {
            let st = planner.startTimes(night.plan)
            night.startedAt = Date().addingTimeInterval(-(k < st.count ? st[k] : 0))
        }
        player.crossfade = mode == .full ? (Player.supportsFullCrossfade ? 6 : 0) : 5
        do {
            try await player.start(songs: night.songs, at: k, mode: mode)
            go(.playing)
        } catch {
            say("Couldn't start playback. \(error.localizedDescription)")
        }
    }

    /// Tap a row: start there, or jump there if the night is playing.
    func playRow(_ k: Int) async {
        if player.isActive { await player.jump(to: k); go(.playing) } else { await startNight(from: k) }
    }

    private func trackStarted(_ k: Int) {
        night?.played.insert(k)
    }

    var modeText: String {
        switch player.mode {
        case .full: return Player.supportsFullCrossfade ? "Full songs from your Apple Music, blended." : "Full songs from your Apple Music. Blends need iOS 18."
        case .preview: return "Preview mode: 30 seconds of each song, blended. Subscribe to Apple Music for full songs."
        case .none: return ""
        }
    }

    func toggleLove() {
        guard let night, player.idx >= 0, player.idx < night.plan.seq.count else { return }
        let j = night.plan.seq[player.idx]
        if night.loved.contains(j) { night.loved.remove(j) } else { night.loved.insert(j) }
    }

    var lovedNow: Bool {
        guard let night, player.idx >= 0, player.idx < night.plan.seq.count else { return false }
        return night.loved.contains(night.plan.seq[player.idx])
    }

    // MARK: Editing the plan

    func swapAt(_ k: Int) {
        guard let night, let planner, k < night.plan.seq.count else { return }
        var tried = night.swaps[k] ?? [night.plan.seq[k]]
        guard let alt = planner.alternative(night.plan, pos: k, exclude: tried) else { say("No other song fits this spot"); return }
        tried.insert(alt)
        night.swaps[k] = tried
        night.plan.seq[k] = alt
        night.am[k] = .pending
        night.replaced.remove(k)
        guard authorized, let cat = catalog else { return }
        Task {
            let hit = await matcher.find(track: alt, in: cat, clean: night.plan.clean)
            guard self.night === night, k < night.plan.seq.count, night.plan.seq[k] == alt else { return }
            night.am[k] = hit.map { .found($0) } ?? .missing
            if hit == nil { say("That one isn't on Apple Music. Swap again.") }
            if player.isActive, k > player.idx { await player.update(songs: night.songs) }
        }
    }

    func removeAt(_ k: Int) {
        guard let night, k < night.plan.seq.count else { return }
        if player.isActive && k <= player.idx { say("That one already played"); return }
        night.plan.seq.remove(at: k)
        night.am.remove(at: k)
        night.replaced = Set(night.replaced.compactMap { r -> Int? in
            if r < k { return r }
            if r > k { return r - 1 }
            return nil
        })
        if player.isActive { Task { await player.update(songs: night.songs) } }
    }

    // MARK: Live steering

    /// Re-plans everything after the current song. Returns what the DJ says back.
    func steer(_ action: String, _ arg: String? = nil) -> String {
        guard let night, let planner else { return "" }
        let plan = night.plan
        let cur = player.isActive ? player.idx : -1
        let keep = cur + 1
        let prefix = Array(plan.seq.prefix(keep))
        let st = planner.startTimes(plan)
        let elapsed = keep < plan.seq.count ? st[keep] : planner.totalSeconds(plan)
        night.undo = SteerUndo(seq: plan.seq, am: night.am, exclude: plan.exclude, boost: plan.boost,
                               energyOff: plan.energyOff, fam: plan.fam, durS: plan.durS)
        var durS = plan.durS, fam = plan.fam
        var energyOff = plan.energyOff
        var boost = plan.boost
        var exclude = plan.exclude
        var reply = ""
        let curVibe: String? = cur >= 0 && cur < plan.seq.count ? planner.vibeKey(of: plan.seq[cur], in: plan) : nil
        let tailStart = durS > 0 ? elapsed / durS : 0
        var minutes = 20

        switch action {
        case "up":
            energyOff = { p in p < tailStart + 0.18 ? 0.12 : 0.05 }
            reply = "Got it. I'll lift the energy over the next two songs and keep it up from there."
        case "down":
            energyOff = { p in p < tailStart + 0.18 ? -0.12 : -0.05 }
            reply = "Easing it down after this one. I'll hold it mellow for a stretch."
        case "familiar":
            fam = 0.95
            reply = "Switching to the songs everyone knows for the rest of the night."
        case "surprise":
            fam = 0.35
            reply = "Going deeper. Fewer hits, more finds."
        case "more":
            guard let v = arg else { night.undo = nil; return "" }
            var b = boost ?? [:]
            b[v, default: 0] += 0.35
            boost = b
            exclude?.remove(v)
            reply = "More \(Vibes.name(v)) coming, starting after this one."
        case "skip":
            guard let v = arg ?? curVibe else { night.undo = nil; return "" }
            var ex = exclude ?? []
            ex.insert(v)
            let left = plan.weights.keys.filter { !ex.contains($0) }.sorted()
            if left.isEmpty { night.undo = nil; return "That's the only sound in the night, so I'll keep it." }
            exclude = ex
            reply = "No more \(Vibes.name(v)) for now. I'll lean on \(Vibes.joinNames(left.map { Vibes.name($0) }))."
        case "wrap":
            minutes = Int(arg ?? "") ?? 20
            durS = elapsed + Double(minutes * 60)
            let span = max(0.05, 1 - tailStart)
            energyOff = { p in -0.25 * min(max((p - tailStart) / span, 0), 1) }
            reply = "Wrapping up. \(minutes) more minutes, then I'll bring it home."
        default:
            night.undo = nil
            return ""
        }

        settings.seed = (settings.seed &* 48271) % 2147483647
        if settings.seed == 0 { settings.seed = 11 }
        saveSettings()
        let cfg = BuildConfig(weights: plan.weights, durS: durS, arc: plan.arc, clean: plan.clean, fam: fam, tw: plan.tw,
                              seed: settings.seed, xf: 0, prefix: prefix, elapsed: elapsed, energyOff: energyOff,
                              boost: boost, exclude: exclude)
        guard let r = planner.build(cfg), !r.seq.isEmpty else {
            night.undo = nil
            return "I couldn't find enough songs for that. Try another request."
        }
        night.plan.seq = prefix + r.seq
        night.plan.fam = fam
        night.plan.energyOff = energyOff
        night.plan.boost = boost
        night.plan.exclude = exclude
        night.plan.durS = durS
        night.am = Array(night.am.prefix(keep)) + Array(repeating: MatchState.pending, count: r.seq.count)
        night.replaced = Set(night.replaced.filter { $0 < keep })
        night.requests.append(SteerRequest(action: action, arg: arg, at: Date()))
        if action == "up" {
            let t = planner.cat.t
            var hot = -1, he = -1.0
            for i in 0..<min(4, r.seq.count) where t.e[r.seq[i]] > he { he = t.e[r.seq[i]]; hot = i }
            if hot >= 0 {
                reply = "Got it. I'll lift the energy over the next two songs and bring \(Catalog.shortTitle(t.n[r.seq[hot]])) forward to \(Fmt.clock(clock(at: keep + hot)))."
            }
        }
        Task {
            if authorized { await resolveNight(night) }
            await player.update(songs: night.songs)
        }
        return reply
    }

    func undoSteer() {
        guard let night, let u = night.undo else { return }
        night.plan.seq = u.seq
        night.am = u.am
        night.plan.exclude = u.exclude
        night.plan.boost = u.boost
        night.plan.energyOff = u.energyOff
        night.plan.fam = u.fam
        night.plan.durS = u.durS
        night.undo = nil
        if !night.requests.isEmpty { night.requests.removeLast() }
        steerReply = nil
        steerChosen = nil
        Task { await player.update(songs: night.songs) }
        say("Back to the earlier plan")
    }

    /// Chips on the playing screen and in the steer sheet.
    func steerChips(short: Bool) -> [(action: String, label: String, arg: String?)] {
        let heads = night?.plan.heads ?? []
        var chips: [(action: String, label: String, arg: String?)] = [
            ("up", "More energy", nil), ("down", "Bring it down", nil), ("familiar", "Something we know", nil),
        ]
        if !short { chips.append(("surprise", "Surprise us", nil)) }
        for h in (short ? Array(heads.prefix(1)) : heads) { chips.append(("more", "More \(Vibes.name(h))", h)) }
        chips.append(("skip", "Skip this vibe", nil))
        chips.append(("wrap", "Wrap up in 20 min", "20"))
        return chips
    }

    func doSteer(_ action: String, _ arg: String?) {
        let reply = steer(action, arg)
        steerChosen = action + "|" + (arg ?? "")
        steerReply = reply.isEmpty ? "I couldn't do that one." : reply
    }

    func steerFromText(_ text: String) {
        guard let (action, arg) = parseRequest(text) else {
            steerReply = "I didn't catch that. Try 'more energy', 'slow it down', 'more Punjabi', or 'wrap up in 15 minutes'."
            return
        }
        doSteer(action, arg)
    }

    func parseRequest(_ text: String) -> (String, String?)? {
        let cleaned = String(text.lowercased().unicodeScalars.map { u -> Character in
            (u.isASCII && CharacterSet.alphanumerics.contains(u)) || u == "&" || u == " " ? Character(u) : " "
        })
        let t = " " + cleaned + " "
        func has(_ pattern: String) -> Bool { t.range(of: pattern, options: .regularExpression) != nil }
        if has("(wrap|wind down|last song|end it|end the night|finish|close out)") {
            if let r = t.range(of: #"(\d+)\s*(min|minute)"#, options: .regularExpression) {
                let digits = t[r].prefix { $0.isNumber }
                return ("wrap", String(digits))
            }
            return ("wrap", "20")
        }
        for k in Vibes.order {
            let v = Vibes.style(k)
            let tokens = [v.name, v.short ?? "", k].joined(separator: " & ").lowercased()
                .components(separatedBy: CharacterSet(charactersIn: "&, "))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.count >= 3 && !["and", "the"].contains($0) }
            if tokens.contains(where: { t.contains(" " + $0) }) {
                if has("(no more|skip|less|enough|drop|stop|without)") { return ("skip", k) }
                return ("more", k)
            }
        }
        if has("(slow|chill|mellow|bring it down|calm|softer|lower|down)") { return ("down", nil) }
        if has("(energy|hype|turn up|louder|faster|harder|up|bang|lift|dance)") { return ("up", nil) }
        if has("(know|familiar|hits|classic|sing along|popular)") { return ("familiar", nil) }
        if has("(surprise|deep cut|new|discover|underground)") { return ("surprise", nil) }
        return nil
    }

    // MARK: The end of the night

    func finishNight() {
        guard let night else { return }
        let rec = recapOf(night)
        nights = [rec] + nights.filter { $0.id != rec.id }
        if nights.count > 12 { nights = Array(nights.prefix(12)) }
        Store.set("selector.nights", nights)
        Store.set("selector.night", nil as SavedNight?)
        recap = rec
        player.stop()
        path = [.recap]
    }

    func recapOf(_ n: Night) -> Recap {
        let plan = n.plan
        let t = planner?.cat.t
        let played = n.played.filter { $0 < plan.seq.count }.sorted()
        let pool = played.isEmpty ? Array(plan.seq.indices) : played
        var peakK = pool.first ?? 0, pe = -1.0
        for k in pool { if let e = t?.e[plan.seq[k]], e > pe { pe = e; peakK = k } }
        let base = n.startOrNow
        let st = planner?.startTimes(plan) ?? []
        let seconds = played.isEmpty ? (planner?.totalSeconds(plan) ?? 0) : played.reduce(0.0) { $0 + Double(t?.dur[plan.seq[$1]] ?? 0) }
        func art(_ k: Int) -> String? { n.song(at: k)?.artwork?.url(width: 600, height: 600)?.absoluteString }
        return Recap(id: n.createdAt.timeIntervalSince1970, title: plan.title, date: Fmt.weekday(base), seconds: seconds,
                     songs: pool.count, peakK: peakK, peakJ: plan.seq.isEmpty ? 0 : plan.seq[min(peakK, plan.seq.count - 1)],
                     peakAt: Fmt.clock(base.addingTimeInterval(peakK < st.count ? st[peakK] : 0)), peakArt: art(peakK),
                     loved: n.loved.count, requests: n.requests.count, saved: n.saved,
                     vibes: plan.soundsByWeight.map { Vibes.name($0) }, seq: Array(plan.seq.prefix(15)),
                     arts: (0..<min(15, plan.seq.count)).map { art($0) }, weights: plan.weights,
                     minutes: Int((plan.durS / 60).rounded()), arc: plan.arc, clean: plan.clean, fam: plan.fam, occasion: settings.occasion)
    }

    func shareText(_ r: Recap) -> String {
        guard let t = planner?.cat.t, r.peakJ < t.n.count else { return r.title }
        return "\(r.title) · \(Fmt.length(r.seconds)) · \(r.songs) songs. The floor peaked at \(r.peakAt) with \(Catalog.shortTitle(t.n[r.peakJ])) by \(t.ar[r.peakJ]). Planned by Selector."
    }

    func playAgain(_ r: Recap) {
        settings.weights = r.weights
        settings.minutes = r.minutes
        settings.arc = r.arc
        settings.clean = r.clean
        settings.fam = r.fam
        settings.occasion = r.occasion
        saveSettings()
        if planNight() { path = [.plan] }
    }

    func savePlaylist() async {
        guard let night else { return }
        guard await ensureAuthorized() else { return }
        if !night.resolved && !night.resolving { await resolveNight(night) }
        let list = night.songs.compactMap { $0 }
        guard !list.isEmpty else { say("Nothing to save yet"); return }
        do {
            _ = try await MusicLibrary.shared.createPlaylist(
                name: "Selector · \(night.plan.title)",
                description: "Planned by your Selector DJ. \(night.plan.soundsByWeight.map { Vibes.name($0) }.joined(separator: ", ")).",
                items: list)
            night.saved = true
            say("Saved to your Apple Music library. In the Music app, turn on AutoMix for blended transitions.")
        } catch {
            say("Couldn't save the playlist. \(error.localizedDescription)")
        }
    }

    // MARK: Taste

    func tasteFromText(_ text: String) {
        guard let planner else { return }
        let names = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return }
        guard let t = planner.taste(from: names, source: "You typed \(names.count) artist\(names.count == 1 ? "" : "s")") else {
            say("None of those are in your DJ's crate yet"); return
        }
        taste = t
        Store.set("selector.taste", t)
        sheet = nil
    }

    func tasteFromLibrary() async {
        guard await ensureAuthorized(), let planner else { return }
        do {
            var request = MusicLibraryRequest<Song>()
            request.sort(by: \.lastPlayedDate, ascending: false)
            request.limit = 400
            let response = try await request.response()
            var score: [String: Double] = [:]
            let items = Array(response.items)
            for (r, s) in items.enumerated() {
                let recency = 1.0 - 0.6 * Double(r) / Double(max(1, items.count - 1))
                score[s.artistName, default: 0] += recency + Double(s.playCount ?? 0) * 0.05
            }
            let ranked = score.sorted { $0.value > $1.value }.prefix(80).map { $0.key }
            guard let t = planner.taste(from: Array(ranked), source: "Your Apple Music (\(items.count) recent songs)") else {
                say("None of your recent artists are in your DJ's crate yet"); return
            }
            taste = t
            Store.set("selector.taste", t)
            say("Learned your taste from \(t.matched.count) artists")
        } catch {
            say("Couldn't read your Apple Music library. \(error.localizedDescription)")
        }
    }

    func clearTaste() {
        taste = nil
        Store.set("selector.taste", nil as Taste?)
    }

    // MARK: Picking the night up again

    func saveCurrentNight() {
        guard let night else { Store.set("selector.night", nil as SavedNight?); return }
        let s = SavedNight(seq: night.plan.seq, weights: night.plan.weights, arc: night.plan.arc, clean: night.plan.clean,
                           fam: night.plan.fam, durS: night.plan.durS, title: night.plan.title, startedAt: night.startedAt,
                           played: Array(night.played), loved: Array(night.loved), requests: night.requests.count,
                           saved: night.saved, createdAt: night.createdAt)
        Store.set("selector.night", s)
    }

    private func restoreNight() {
        guard let planner, let s = Store.get("selector.night", as: SavedNight.self),
              Date().timeIntervalSince(s.createdAt) < 12 * 3600, !s.seq.isEmpty else { return }
        let tw = tasteWeights
        let cfg = BuildConfig(weights: s.weights, durS: 60, arc: s.arc, clean: s.clean, fam: s.fam, tw: tw, seed: 1)
        guard let r = planner.build(cfg) else { return }
        let plan = Plan(seq: s.seq, pv: r.pv, pool: r.pool, short: false, baseE: r.baseE, amp: r.amp, weights: s.weights,
                        arc: s.arc, clean: s.clean, fam: s.fam, tw: tw, durS: s.durS, title: s.title)
        let n = Night(plan: plan, createdAt: s.createdAt)
        n.startedAt = s.startedAt
        n.played = Set(s.played)
        n.loved = Set(s.loved)
        n.saved = s.saved
        night = n
        if authorized { Task { await resolveNight(n) } }
    }
}
