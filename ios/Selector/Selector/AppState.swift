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
    var parser: RequestParser?
    /// Occasion name to use as the title when the sounds were customised in a typed brief.
    @ObservationIgnored var briefTitle: String?

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
            parser = RequestParser(catalog: cat)
            if let tw = taste?.tw, tw.count != cat.count { taste = nil; Store.set("selector.taste", nil as Taste?) }
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
                doSteer([.energy(up: true)])
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
        if let i = path.firstIndex(of: r) { path.removeSubrange((i + 1)...) } else { path.append(r) }
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
        if player.isActive { say("A night is already playing. End it first from the playing screen."); return false }
        guard var plan = newPlan() else { say("Pick at least one sound"); return false }
        if let briefTitle, settings.occasion == nil { plan.title = briefTitle }
        briefTitle = nil
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
        // Unknown stays unknown, so a hiccup doesn't lock the session into previews.
        if let sub = try? await MusicSubscription.current { subscribed = sub.canPlayCatalogContent }
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
        if authorized && subscribed != true { await checkSubscription() }
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
        guard player.isActive else { say("Apple Music connected. Nights will play as full songs."); return }
        let k = max(0, player.idx)
        player.stop()
        await startNight(from: k)
    }

    /// Tap a row: start there, or jump there if the night is playing.
    func playRow(_ k: Int) async {
        if player.isActive { await player.jump(to: k); go(.playing) } else { await startNight(from: k) }
    }

    private func trackStarted(_ k: Int) {
        guard let night, let planner else { return }
        night.played.insert(k)
        if night.firstPlay == nil { night.firstPlay = Date() }
        // Keep the printed times honest after skips and jumps: this song started now.
        let st = planner.startTimes(night.plan)
        if k < st.count { night.startedAt = Date().addingTimeInterval(-st[k] - player.elapsed) }
        if let u = night.undo, k > u.at + 1 { night.undo = nil }
    }

    var modeText: String {
        switch player.mode {
        case .full: return Player.supportsFullCrossfade ? "Full songs from your Apple Music, blended." : "Full songs from your Apple Music. Blends need iOS 18."
        case .preview: return "Previews: 30 seconds of each song, blended."
        case .none: return ""
        }
    }

    // MARK: Editing the plan

    func swapAt(_ k: Int) {
        guard let night, let planner, k < night.plan.seq.count else { return }
        if player.isActive && k <= player.idx { say("That one already played"); return }
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
    func steer(_ intents: [DJIntent]) -> String {
        guard let night, let planner, !intents.isEmpty else { return "" }
        let plan = night.plan
        let t = planner.cat.t
        let cur = player.isActive ? player.idx : -1
        let keep = min(cur + 1, plan.seq.count)
        var prefix = Array(plan.seq.prefix(keep))
        let st = planner.startTimes(plan)
        var elapsed = keep < plan.seq.count ? st[keep] : planner.totalSeconds(plan)
        let undo = SteerUndo(seq: plan.seq, am: night.am, exclude: plan.exclude, boost: plan.boost, energyOff: plan.energyOff,
                             fam: plan.fam, durS: plan.durS, weights: plan.weights, favor: plan.favor, banned: plan.banned,
                             pv: plan.pv, pool: plan.pool, at: cur)
        var durS = plan.durS, fam = plan.fam
        var energyOff = plan.energyOff
        var boost = plan.boost ?? [:]
        var exclude = plan.exclude ?? []
        var weights = plan.weights
        var favor = plan.favor
        var banned = plan.banned
        var forced: [Int] = []
        var replies: [String] = []
        var applied: [DJIntent] = []
        let curVibe: String? = cur >= 0 && cur < plan.seq.count ? planner.vibeKey(of: plan.seq[cur], in: plan) : nil
        let tailStart = durS > 0 ? min(elapsed / durS, 1) : 0
        var liftedEnergy = false

        for intent in intents {
            switch intent {
            case .energy(let up):
                let d = up ? 1.0 : -1.0
                energyOff = { p in d * (p < tailStart + 0.18 ? 0.12 : 0.05) }
                liftedEnergy = up
                replies.append(up ? "I'll lift the energy over the next two songs and keep it up." : "Easing it down after this one, and holding it mellow for a stretch.")
            case .familiar:
                fam = 0.95
                replies.append("Switching to the songs everyone knows.")
            case .surprise:
                fam = 0.35
                replies.append("Going deeper: fewer hits, more finds.")
            case .more(let v):
                if (weights[v] ?? 0) == 0 { weights[v] = 1 }
                boost[v, default: 0] += 0.35
                exclude.remove(v)
                replies.append("More \(Vibes.name(v)) coming, starting after this one.")
            case .less(let asked):
                guard let v = asked ?? curVibe else { continue }
                let left = weights.filter { $0.value > 0 && !exclude.contains($0.key) && $0.key != v }.keys.sorted()
                if left.isEmpty { replies.append("\(Vibes.name(v)) is the only sound tonight, so I'll keep it."); continue }
                if (weights[v] ?? 0) == 0 { replies.append("There's no \(Vibes.name(v)) in tonight's plan."); continue }
                exclude.insert(v)
                boost[v] = nil
                replies.append("No more \(Vibes.name(v)) for now. I'll lean on \(Vibes.joinNames(left.map { Vibes.name($0) })).")
            case .wrap(let minutes):
                durS = elapsed + Double(minutes * 60)
                let span = max(0.05, 1 - tailStart)
                energyOff = { p in -0.25 * min(max((p - tailStart) / span, 0), 1) }
                replies.append("\(minutes) more minutes, then I'll bring it home.")
            case .playSong(let j):
                guard j >= 0, j < planner.cat.count else { continue }
                let title = Catalog.shortTitle(t.n[j])
                if plan.clean && t.x[j] == 1 { replies.append("\(title) is explicit, and tonight is family-friendly."); continue }
                if cur >= 0, cur < plan.seq.count, plan.seq[cur] == j { replies.append("\(title) is playing right now."); continue }
                if prefix.contains(j) { replies.append("\(title) already played tonight. I'll find something close."); favor[j] = nil; continue }
                forced.append(j)
                favor[j] = 2.5
                replies.append("\(title) by \(Catalog.firstArtist(t.ar[j])) is up next.")
            case .moreArtist(let name):
                let tracks = planner.tracks(byArtist: name).filter { !prefix.contains($0) && !(plan.clean && t.x[$0] == 1) }
                if tracks.isEmpty { replies.append("I've played everything I have by \(name)."); continue }
                for j in tracks { favor[j] = max(favor[j] ?? 0, 2.5) }
                for j in tracks { banned.remove(t.a[j]) }
                replies.append("More \(name) on the way.")
            case .lessArtist(let name):
                let key = Normalizer.artist(name)
                for j in planner.tracks(byArtist: name) {
                    favor[j] = -8
                    if Normalizer.artist(Catalog.firstArtist(t.ar[j])) == key { banned.insert(t.a[j]) }
                }
                replies.append("No more \(name) tonight.")
            }
            applied.append(intent)
        }
        guard !applied.isEmpty else { return replies.joined(separator: " ") }

        for j in forced where !prefix.contains(j) {
            prefix.append(j)
            elapsed += Double(t.dur[j])
        }
        settings.seed = (settings.seed &* 48271) % 2147483647
        if settings.seed == 0 { settings.seed = 11 }
        saveSettings()
        var cfg = BuildConfig(weights: weights, durS: max(durS, elapsed + 60), arc: plan.arc, clean: plan.clean, fam: fam, tw: plan.tw,
                              seed: settings.seed, xf: 0, prefix: prefix, elapsed: elapsed, energyOff: energyOff,
                              boost: boost.isEmpty ? nil : boost, exclude: exclude.isEmpty ? nil : exclude)
        cfg.favor = favor
        cfg.banned = banned
        guard let r = planner.build(cfg), !(r.seq.isEmpty && forced.isEmpty) else {
            return "I couldn't find enough songs for that. Try another request."
        }
        night.undo = undo
        night.plan.seq = prefix + r.seq
        // Keep the sound of songs that already played, even if that sound was just dropped.
        var pv = r.pv
        for j in plan.seq.prefix(keep) where pv[j] < 0 && plan.pv[j] >= 0 { pv[j] = plan.pv[j] }
        night.plan.pv = pv
        night.plan.pool = r.pool
        night.plan.weights = weights
        night.plan.fam = fam
        night.plan.energyOff = energyOff
        night.plan.boost = boost.isEmpty ? nil : boost
        night.plan.exclude = exclude.isEmpty ? nil : exclude
        night.plan.favor = favor
        night.plan.banned = banned
        night.plan.durS = durS
        night.am = Array(night.am.prefix(keep)) + Array(repeating: MatchState.pending, count: night.plan.seq.count - keep)
        night.replaced = Set(night.replaced.filter { $0 < keep })
        night.swaps = night.swaps.filter { $0.key < keep }
        night.generation += 1
        night.inFlight = []
        night.resolved = false
        for i in applied { night.requests.append(SteerRequest(action: i.key, arg: nil, at: Date())) }
        if !phaseKeys.contains(phaseFilter) { phaseFilter = "all" }
        if liftedEnergy, applied.count == 1 {
            var hot = -1, he = -1.0
            for i in 0..<min(4, r.seq.count) where t.e[r.seq[i]] > he { he = t.e[r.seq[i]]; hot = i }
            if hot >= 0 {
                replies = ["I'll lift the energy over the next two songs and bring \(Catalog.shortTitle(t.n[r.seq[hot]])) forward to \(Fmt.clock(clock(at: prefix.count + hot)))."]
            }
        }
        Task {
            await syncPlayer()
            await resolveNight(night)
        }
        return replies.joined(separator: " ")
    }

    private var phaseKeys: [String] {
        guard let night, let planner else { return [] }
        return planner.phases(night.plan).map { $0.key }
    }

    func undoSteer() {
        guard let night, let u = night.undo else { return }
        // Only what hasn't played yet goes back; the song that's on stays on.
        let keep = min(max(player.isActive ? player.idx + 1 : 0, 0), min(u.seq.count, night.plan.seq.count))
        let played = Array(night.plan.seq.prefix(keep))
        let tail = u.seq.dropFirst(keep).filter { !played.contains($0) }
        let tailAm = u.seq.indices.dropFirst(keep).filter { !played.contains(u.seq[$0]) }.map { u.am[$0] }
        night.plan.seq = played + tail
        night.am = Array(night.am.prefix(keep)) + tailAm
        night.plan.exclude = u.exclude
        night.plan.boost = u.boost
        night.plan.energyOff = u.energyOff
        night.plan.fam = u.fam
        night.plan.durS = u.durS
        night.plan.weights = u.weights
        night.plan.favor = u.favor
        night.plan.banned = u.banned
        var pv = u.pv
        for j in played where pv[j] < 0 && night.plan.pv[j] >= 0 { pv[j] = night.plan.pv[j] }
        night.plan.pv = pv
        night.plan.pool = u.pool
        night.undo = nil
        night.generation += 1
        night.inFlight = []
        night.replaced = Set(night.replaced.filter { $0 < keep })
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
    func steerChips(short: Bool) -> [(intent: DJIntent, label: String)] {
        let heads = night?.plan.heads ?? []
        var chips: [(intent: DJIntent, label: String)] = [
            (.energy(up: true), "More energy"), (.energy(up: false), "Bring it down"), (.familiar, "Something we know"),
        ]
        if !short { chips.append((.surprise, "Surprise us")) }
        for h in (short ? Array(heads.prefix(1)) : heads) { chips.append((.more(vibe: h), "More \(Vibes.name(h))")) }
        chips.append((.less(vibe: nil), "Skip this vibe"))
        chips.append((.wrap(minutes: 20), "Wrap up in 20 min"))
        return chips
    }

    func doSteer(_ intents: [DJIntent]) {
        let reply = steer(intents)
        steerChosen = intents.first?.key
        steerReply = reply.isEmpty ? "I couldn't do that one." : reply
    }

    func steerFromText(_ text: String) {
        let intents = parser?.parse(text) ?? []
        if !intents.isEmpty { doSteer(intents); return }
        steerReply = "Thinking…"
        let sounds = Vibes.order
        Task {
            if let intent = await OnDeviceDJ.interpret(text, sounds: sounds) {
                doSteer([intent])
            } else {
                steerChosen = nil
                steerReply = "I didn't catch that. Try \"more energy\", \"play Brown Munde\", \"no more techno\", or \"wrap up in 15 minutes\"."
            }
        }
    }

    // MARK: Reading the room

    /// Loving a song nudges the rest of the night toward that artist.
    func toggleLove() {
        guard let night, let planner, player.idx >= 0, player.idx < night.plan.seq.count else { return }
        let j = night.plan.seq[player.idx]
        let artist = Catalog.firstArtist(planner.cat.t.ar[j])
        if night.loved.contains(j) {
            night.loved.remove(j)
            for k in planner.tracks(byArtist: artist) where night.plan.favor[k] == 0.9 { night.plan.favor[k] = nil }
        } else {
            night.loved.insert(j)
            for k in planner.tracks(byArtist: artist) where night.plan.favor[k] == nil { night.plan.favor[k] = 0.9 }
            Haptics.tap()
        }
    }

    var lovedNow: Bool {
        guard let night, player.idx >= 0, player.idx < night.plan.seq.count else { return false }
        return night.loved.contains(night.plan.seq[player.idx])
    }

    /// Skip to the next song. Two quick skips of the same sound and the DJ eases off it.
    func skip() async {
        guard let night, let planner, player.idx >= 0, player.idx < night.plan.seq.count else { await player.next(); return }
        let k = player.idx
        let j = night.plan.seq[k]
        let early = player.elapsed < min(45, max(8, player.dur * 0.35))
        await player.next()
        guard early, player.mode == .full || player.dur > 60 else { return }
        night.plan.favor[j] = -4
        night.skips.append(k)
        let v = planner.vibeKey(of: j, in: night.plan)
        let recent = night.skips.suffix(2)
        if recent.count == 2, let a = recent.first, k - a <= 3, a < night.plan.seq.count,
           planner.vibeKey(of: night.plan.seq[a], in: night.plan) == v,
           night.plan.weights.filter({ $0.value > 0 && !(night.plan.exclude?.contains($0.key) ?? false) }).count > 1 {
            night.skips.removeAll()
            let reply = steer([.less(vibe: v)])
            if !reply.isEmpty { say("Two quick skips. " + reply) }
        }
    }

    // MARK: Describing the night

    /// "Sangeet, mostly Punjabi, three hours": plan straight from a sentence.
    func planFromText(_ text: String) {
        guard let parser, let planner else { return }
        let r = parser.parseBrief(text)
        guard r.understoodAnything else {
            say("Tell me the occasion, the sounds, or how long. For example: house party, hip-hop and afrobeats, two hours.")
            return
        }
        if player.isActive { say("A night is playing. End it first, or tell your DJ what to change."); return }
        if let o = Occasion.named(r.occasion) {
            if r.weights.isEmpty { settings.apply(o) } else {
                settings.arc = o.arc; settings.clean = o.clean; settings.fam = o.fam; settings.minutes = o.minutes
            }
        }
        if !r.weights.isEmpty { settings.weights = r.weights }
        settings.occasion = r.weights.isEmpty ? r.occasion : Occasion.matching(settings.weights)?.key
        briefTitle = r.weights.isEmpty ? nil : Occasion.named(r.occasion)?.label
        if let m = r.minutes { settings.minutes = m }
        if let c = r.clean { settings.clean = c }
        if let f = r.fam { settings.fam = f }
        if let a = r.arc { settings.arc = a }
        if !r.artists.isEmpty, let t = planner.taste(from: r.artists, source: "You asked for \(Vibes.joinNames(r.artists))") {
            taste = t
            Store.set("selector.taste", t)
            settings.useTaste = true
        }
        saveSettings()
        if planNight() { path = [.plan] }
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
        sheet = nil
        steerReply = nil
        steerChosen = nil
        player.stop()
        self.night = nil
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
        let seconds = n.firstPlay.map { Date().timeIntervalSince($0) } ?? (planner?.totalSeconds(plan) ?? 0)
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

    /// End the night early, from the playing screen.
    func endNight() {
        finishNight()
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
              Date().timeIntervalSince(s.createdAt) < 12 * 3600, !s.seq.isEmpty,
              s.seq.allSatisfy({ $0 >= 0 && $0 < planner.cat.count }) else { return }
        let tw = tasteWeights
        let cfg = BuildConfig(weights: s.weights, durS: 60, arc: s.arc, clean: s.clean, fam: s.fam, tw: tw, seed: 1)
        guard let r = planner.build(cfg) else { return }
        var pv = r.pv
        for j in s.seq where pv[j] < 0 { pv[j] = planner.vibeIndex[Settings(weights: s.weights).sounds.first ?? "pop"] ?? 0 }
        let plan = Plan(seq: s.seq, pv: pv, pool: r.pool, short: false, baseE: r.baseE, amp: r.amp, weights: s.weights,
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
