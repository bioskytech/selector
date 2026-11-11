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
    @ObservationIgnored private let lookup = ITunesMatcher()
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
        #if DEBUG
        if let i = CommandLine.arguments.firstIndex(of: "-demo"), i + 1 < CommandLine.arguments.count {
            await runDemo(CommandLine.arguments[i + 1])
            return
        }
        #endif
        restoreNight()
        if authorized { await checkSubscription() }
    }

    #if DEBUG
    /// Screenshots: `-demo plan|songs|playing|steer|brief|recap|tonight` opens that screen with a real plan.
    private func runDemo(_ screen: String) async {
        demo = true
        authorized = false
        settings = Settings()
        guard screen != "tonight", screen != "brief" else { if screen == "brief" { path = [.brief] }; return }
        guard planNight(), let n = night else { return }
        n.priority = screen == "plan" ? 0 : 6
        // Give the lookup a little while to bring in artwork.
        let deadline = Date().addingTimeInterval(22)
        while Date() < deadline, n.pendingCount > n.plan.seq.count - 12 { try? await Task.sleep(nanoseconds: 300_000_000) }
        switch screen {
        case "plan": path = [.plan]
        case "songs": path = [.plan, .songs]
        case "playing", "steer":
            n.startedAt = Date().addingTimeInterval(-1500)
            n.played = Set(0...6)
            player.simulate(songs: n.tracks, at: 6, elapsed: 84, dur: 212)
            path = [.plan, .playing]
            if screen == "steer" {
                try? await Task.sleep(nanoseconds: 600_000_000)
                sheet = .steer
                doSteer("up", nil)
            }
        case "recap":
            n.startedAt = Date().addingTimeInterval(-7200)
            n.played = Set(n.plan.seq.indices)
            n.loved = Set(n.plan.seq.prefix(9))
            finishNight()
        default: break
        }
    }
    #endif

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
        musicKitOK = true
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

    /// Start finding songs right away so the plan shows real artwork.
    private func prepareNight(_ n: Night) async {
        await resolveNight(n)
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
        let n = night.plan.seq.count
        if starting { return "Cueing up the first song…" }
        if night.resolving {
            let found = n - night.pendingCount
            return found > 0 ? "Finding your songs… \(found) of \(n)" : "Finding your songs…"
        }
        if !night.resolveNote.isEmpty { return night.resolveNote }
        if night.resolved { return source == .appleMusic ? "All \(n) songs found on Apple Music." : "All \(n) songs found." }
        return ""
    }

    // MARK: Apple Music

    /// Where songs are found: Apple Music when it's connected and working, otherwise Apple's
    /// public lookup, which needs no sign-in and gives artwork and 30-second previews.
    enum Source { case appleMusic, lookup }
    var musicKitOK = true
    var source: Source { authorized && musicKitOK ? .appleMusic : .lookup }
    var starting = false
    @ObservationIgnored var demo = false

    /// Asks for Apple Music access. With `quiet`, a refusal says nothing.
    func ensureAuthorized(quiet: Bool = false) async -> Bool {
        if MusicAuthorization.currentStatus == .authorized { authorized = true; return true }
        let status = await MusicAuthorization.request()
        authorized = status == .authorized
        if !authorized && !quiet {
            say("Allow Apple Music in Settings → Privacy & Security → Media & Apple Music.")
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

    private enum ResolveOutcome { case done, stale, failed }

    /// Finds every song of the night, swapping in close fits when one is missing.
    /// Safe to call again while it runs: the running pass picks up whatever is still pending.
    func resolveNight(_ n: Night) async {
        guard catalog != nil, planner != nil else { return }
        if n.resolving { n.resolveAgain = true; return }
        n.resolving = true
        n.resolveNote = ""
        var offline = false
        repeat {
            n.resolveAgain = false
            let workers = source == .appleMusic ? 4 : 1
            let failed = await withTaskGroup(of: Bool.self) { group -> Bool in
                for _ in 0..<workers {
                    group.addTask { @MainActor [weak self] in
                        while let self, self.night === n, let k = self.nextPending(n) {
                            if await self.resolveOne(k, in: n) == .failed { return true }
                        }
                        return false
                    }
                }
                var any = false
                for await f in group { any = any || f }
                return any
            }
            if failed {
                if musicKitOK && authorized {
                    // Apple Music didn't answer (often: MusicKit isn't enabled for this build). Use the lookup.
                    musicKitOK = false
                    n.resolveAgain = true
                } else {
                    offline = true
                }
            }
        } while night === n && !offline && (n.resolveAgain || n.pendingCount > 0)
        n.resolving = false
        guard night === n else { return }
        if offline {
            n.resolveNote = "Can't reach Apple Music right now. Check your connection."
            return
        }
        // Drop what couldn't be found, but never shift songs that already played.
        let floor = player.isActive ? player.idx : -1
        let keep = n.am.indices.filter { $0 <= floor || !n.am[$0].isMissing }
        let dropped = n.am.count - keep.count
        if dropped > 0 {
            n.plan.seq = keep.map { n.plan.seq[$0] }
            n.am = keep.map { n.am[$0] }
            n.replaced = Set(n.replaced.compactMap { keep.firstIndex(of: $0) })
            n.generation += 1
            n.inFlight = []
        }
        n.resolved = n.pendingCount == 0
        if dropped > 0 {
            n.resolveNote = "\(dropped) song\(dropped > 1 ? "s weren't" : " wasn't") available, so your DJ closed the gap."
        }
        await syncPlayer()
    }

    /// The next position worth looking up: what plays soonest first.
    private func nextPending(_ n: Night) -> Int? {
        let count = n.am.count
        guard count > 0 else { return nil }
        let start = min(max(player.isActive ? player.idx : n.priority, 0), count - 1)
        for off in 0..<count {
            let k = (start + off) % count
            if n.am[k].isPending && !n.inFlight.contains(k) {
                n.inFlight.insert(k)
                return k
            }
        }
        return nil
    }

    private func find(_ j: Int, clean: Bool, from src: Source, in cat: Catalog) async throws -> Track? {
        switch src {
        case .appleMusic: return try await matcher.find(track: j, in: cat, clean: clean)
        case .lookup: return try await lookup.find(track: j, in: cat, clean: clean)
        }
    }

    private func resolveOne(_ k: Int, in n: Night) async -> ResolveOutcome {
        guard let cat = catalog, let planner, k < n.plan.seq.count else { n.inFlight.remove(k); return .stale }
        let gen = n.generation
        let src = source
        let clean = n.plan.clean
        let j = n.plan.seq[k]
        func fresh() -> Bool { night === n && n.generation == gen && k < n.plan.seq.count }
        do {
            var hit = try await find(j, clean: clean, from: src, in: cat)
            guard fresh() else { return .stale }
            var tried: Set<Int> = [j]
            var tries = 0
            while hit == nil && tries < (src == .appleMusic ? 6 : 2) {
                let exclude = tried.union(Set(n.plan.seq))
                guard let alt = planner.alternative(n.plan, pos: k, exclude: exclude) else { break }
                tried.insert(alt)
                hit = try await find(alt, clean: clean, from: src, in: cat)
                guard fresh() else { return .stale }
                if hit != nil, !n.plan.seq.contains(alt) {
                    n.plan.seq[k] = alt
                    n.replaced.insert(k)
                } else {
                    hit = nil
                }
                tries += 1
            }
            n.inFlight.remove(k)
            guard k < n.am.count else { return .stale }
            if let hit { n.am[k] = .found(hit) } else { n.am[k] = .missing }
            if player.mode == .preview { await player.update(songs: n.tracks) }
            return .done
        } catch {
            if fresh() { n.inFlight.remove(k) }
            return .failed
        }
    }

    /// Hand the player the current plan: songs, and how long to blend each transition.
    func syncPlayer() async {
        guard let night, let planner else { return }
        player.blends = planner.blendLengths(night.plan)
        if player.isActive { await player.update(songs: night.tracks) }
    }

    // MARK: Starting the night

    func startNight(from k: Int = 0) async {
        if night == nil { guard planNight() else { return } }
        guard let night else { return }
        if player.isActive { go(.playing); return }
        guard !starting else { return }
        starting = true
        defer { starting = false }

        if MusicAuthorization.currentStatus == .notDetermined && !demo { _ = await ensureAuthorized(quiet: true) }
        if authorized && subscribed == nil { await checkSubscription() }
        var wantFull: Bool { authorized && subscribed == true && musicKitOK }
        if wantFull {
            // Songs found through the lookup can't play in full: find them again on Apple Music.
            var changed = false
            for i in night.am.indices where night.am[i].track != nil && night.am[i].track?.song == nil {
                night.am[i] = .pending
                changed = true
            }
            if changed { night.generation += 1; night.inFlight = []; night.resolved = false }
        }
        night.priority = min(max(k, 0), max(0, night.am.count - 1))
        if night.pendingCount > 0 { Task { await resolveNight(night) } }

        // Full songs wait for the whole night; previews start as soon as the first song is found.
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline, self.night === night {
            let ready = wantFull
                ? (night.pendingCount == 0 && !night.resolving)
                : (night.priority < night.am.count && !night.am[night.priority].isPending) || (!night.resolving && night.pendingCount == 0)
            if ready || (!night.resolving && !night.resolveNote.isEmpty && night.pendingCount > 0) { break }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        guard self.night === night, !night.am.isEmpty else { return }
        let full = wantFull && night.tracks.contains { $0?.song != nil }
        let from = min(night.priority, night.am.count - 1)
        let first = (from..<night.am.count).first { i in
            guard let tr = night.am[i].track else { return false }
            return full ? tr.song != nil : tr.previewURL != nil
        }
        guard let first else {
            say(night.resolveNote.isEmpty ? "Couldn't find these songs right now. Try again in a moment." : night.resolveNote)
            return
        }
        await play(full ? .full : .preview, from: first)
    }

    func play(_ mode: Player.Mode, from k: Int) async {
        guard let night, let planner else { return }
        sheet = nil
        if night.startedAt == nil {
            let st = planner.startTimes(night.plan)
            night.startedAt = Date().addingTimeInterval(-(k < st.count ? st[k] : 0))
        }
        player.crossfade = mode == .full ? (Player.supportsFullCrossfade ? 6 : 0) : 5
        player.blends = planner.blendLengths(night.plan)
        do {
            try await player.start(songs: night.tracks, at: k, mode: mode)
            go(.playing)
        } catch {
            if mode == .full {
                // Apple Music refused: fall back to previews rather than silence.
                musicKitOK = false
                say("Apple Music couldn't play full songs, so here are previews.")
                if let p = (k..<night.am.count).first(where: { night.am[$0].track?.previewURL != nil }),
                   (try? await player.start(songs: night.tracks, at: p, mode: .preview)) != nil {
                    go(.playing)
                }
            } else {
                say("Couldn't start playback. \(error.localizedDescription)")
            }
        }
    }

    /// From previews to full songs, once Apple Music is connected and subscribed.
    func connectAppleMusic() async {
        if MusicAuthorization.currentStatus == .denied || MusicAuthorization.currentStatus == .restricted {
            if let url = URL(string: UIApplication.openSettingsURLString) { await UIApplication.shared.open(url) }
            return
        }
        guard await ensureAuthorized() else { return }
        await checkSubscription()
        guard subscribed == true else { showOffer = true; return }
        musicKitOK = true
        sheet = nil
        let k = max(0, player.idx)
        player.stop()
        await startNight(from: k)
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
        case .preview: return "Previews: 30 seconds of each song, blended."
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
        night.generation += 1
        night.inFlight = []
        night.resolved = false
        Task { await resolveNight(night) }
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
        night.generation += 1
        night.inFlight = []
        if night.resolving { night.resolveAgain = true }
        Task { await syncPlayer() }
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
        night.generation += 1
        night.inFlight = []
        night.resolved = false
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
            await syncPlayer()
            await resolveNight(night)
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
        night.generation += 1
        night.inFlight = []
        if !night.requests.isEmpty { night.requests.removeLast() }
        steerReply = nil
        steerChosen = nil
        Task {
            await syncPlayer()
            if night.pendingCount > 0 { await resolveNight(night) }
        }
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
        func art(_ k: Int) -> String? { n.track(at: k)?.artworkURL(600)?.absoluteString }
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
        // A playlist needs real Apple Music songs, not lookup results.
        var changed = false
        for i in night.am.indices where night.am[i].track != nil && night.am[i].track?.song == nil {
            night.am[i] = .pending
            changed = true
        }
        if changed { night.generation += 1; night.inFlight = []; night.resolved = false }
        if night.pendingCount > 0 {
            say("Finding these on Apple Music…")
            await resolveNight(night)
            let deadline = Date().addingTimeInterval(60)
            while night.resolving, Date() < deadline { try? await Task.sleep(nanoseconds: 200_000_000) }
        }
        let list = night.tracks.compactMap { $0?.song }
        guard !list.isEmpty else { say("Couldn't reach Apple Music to save this. Try again in a moment."); return }
        do {
            _ = try await MusicLibrary.shared.createPlaylist(
                name: "Selector · \(night.plan.title)",
                description: "Planned by your Selector DJ. \(night.plan.soundsByWeight.map { Vibes.name($0) }.joined(separator: ", ")).",
                items: list)
            night.saved = true
            say("Saved to your Apple Music library.")
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
        Task { await resolveNight(n) }
    }
}
