import Foundation
import MusicKit
import AVFoundation
import Observation

/// Plays the night. Full songs go through Apple Music's player (crossfaded on iOS 18);
/// previews go through two AVPlayers that blend into each other.
@Observable @MainActor
final class Player {
    enum Mode { case none, full, preview }

    var mode: Mode = .none
    var idx: Int = -1
    var playing = false
    var elapsed: Double = 0
    var dur: Double = 0
    var fading = false
    var crossfade: Double = 6
    /// Seconds to blend out of each position into the next; falls back to `crossfade`.
    @ObservationIgnored var blends: [Double] = []

    /// Called when a new position starts, and when the last song ends.
    var onTrack: (@MainActor (Int) -> Void)?
    var onFinish: (@MainActor () -> Void)?

    @ObservationIgnored private let music = ApplicationMusicPlayer.shared
    @ObservationIgnored private var songs: [Track?] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var fadeTimer: Timer?
    @ObservationIgnored private var deckA = AVPlayer()
    @ObservationIgnored private var deckB = AVPlayer()
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var wasPlaying = false
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?
    @ObservationIgnored private var resumeAfterInterruption = false

    /// How long to blend out of position `k`.
    func blend(after k: Int) -> Double {
        guard crossfade > 0 else { return 0 }
        return k >= 0 && k < blends.count ? blends[k] : crossfade
    }

    static var supportsFullCrossfade: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    var isActive: Bool { mode != .none }
    var count: Int { songs.count }

    // MARK: Start / stop

    func start(songs list: [Track?], at k: Int, mode newMode: Mode) async throws {
        stop()
        guard k >= 0, k < list.count else { throw PlayerError.nothingToPlay }
        songs = list
        mode = newMode
        idx = k
        busy = true
        defer { busy = false }
        do {
            switch newMode {
            case .full:
                let ids = list[k...].compactMap { $0?.song }
                guard let first = ids.first else { throw PlayerError.nothingToPlay }
                music.queue = ApplicationMusicPlayer.Queue(for: ids, startingAt: first)
                applyTransition()
                try await music.play()
            case .preview:
                guard list[k...].contains(where: { $0?.previewURL != nil }) else { throw PlayerError.nothingToPlay }
                try configureAudioSession()
                playPreview(k)
            case .none:
                return
            }
        } catch {
            // Never leave a half-started player behind: the app would think a night is playing.
            stop()
            throw error
        }
        startTimer()
        onTrack?(idx)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        fadeTimer?.invalidate(); fadeTimer = nil
        fading = false
        if mode == .full { music.stop() }
        deckA.pause(); deckB.pause()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        mode = .none
        playing = false
        idx = -1
        elapsed = 0
        dur = 0
        wasPlaying = false
    }

    /// The plan changed after the current song: rebuild what's queued.
    func update(songs list: [Track?]) async {
        songs = list
        guard mode != .none, idx >= 0, idx < list.count else { return }
        if mode == .full {
            // First choice: swap what's queued after the current song, without touching what's playing.
            let rest = list[(idx + 1)...].compactMap { $0?.song }
            if let cur = music.queue.currentEntry,
               let pos = music.queue.entries.firstIndex(where: { $0.id == cur.id }) {
                do {
                    let after = music.queue.entries.index(after: pos)
                    if after < music.queue.entries.endIndex {
                        music.queue.entries.removeSubrange(after..<music.queue.entries.endIndex)
                    }
                    if !rest.isEmpty { try await music.queue.insert(rest, position: .tail) }
                    return
                } catch {
                    // Fall through to rebuilding the queue.
                }
            }
            let ids = list[idx...].compactMap { $0?.song }
            guard let first = ids.first else { return }
            let t = music.playbackTime
            let keepPlaying = playing
            busy = true
            defer { busy = false }
            do {
                music.queue = ApplicationMusicPlayer.Queue(for: ids, startingAt: first)
                applyTransition()
                try await music.prepareToPlay()
                music.playbackTime = t
                if keepPlaying { try await music.play() }
            } catch {
                // Leave the old queue in place; the plan still shows the change.
            }
        } else {
            preloadNext()
        }
    }

    // MARK: Transport

    func toggle() async {
        switch mode {
        case .full:
            if music.state.playbackStatus == .playing { music.pause() } else { try? await music.play() }
        case .preview:
            // Mid-blend, land on the incoming song first so pause really pauses.
            if fading { finishBlend(to: idx + 1) }
            if deckA.rate > 0 { deckA.pause() } else { deckA.play() }
        case .none:
            return
        }
        tick()
    }

    func next() async {
        switch mode {
        case .full:
            try? await music.skipToNextEntry()
        case .preview:
            fadeTimer?.invalidate(); fading = false
            deckB.pause()
            advancePreview()
        case .none:
            return
        }
        tick()
    }

    func previous() async {
        if fading { finishBlend(to: idx + 1) }
        if elapsed > 5 { seek(0); return }
        switch mode {
        case .full:
            // The queue only holds what's ahead, so going back means starting from the earlier song.
            guard let k = songs.indices.last(where: { $0 < idx && songs[$0]?.song != nil }) else { seek(0); return }
            await jump(to: k)
            return
        case .preview:
            guard idx > 0 else { seek(0); return }
            fadeTimer?.invalidate(); fading = false
            deckB.pause()
            let k = idx - 1
            idx = k
            playPreview(k)
            onTrack?(k)
        case .none:
            return
        }
        tick()
    }

    func seek(_ t: Double) {
        switch mode {
        case .full: music.playbackTime = t
        case .preview: deckA.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        case .none: break
        }
        elapsed = t
    }

    /// Jump to a position of the night without changing mode.
    func jump(to k: Int) async {
        guard mode != .none, k >= 0, k < songs.count else { return }
        let m = mode
        let list = songs
        try? await start(songs: list, at: k, mode: m)
    }

    // MARK: Full songs (Apple Music)

    private func applyTransition() {
        if #available(iOS 18.0, *) {
            let d = blend(after: idx)
            music.transition = d > 0 ? MusicPlayer.Transition.crossfade(duration: d) : MusicPlayer.Transition.none
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Common mode: keep ticking while the listener scrolls.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        switch mode {
        case .full: tickFull()
        case .preview: tickPreview()
        case .none: break
        }
    }

    private func tickFull() {
        let status = music.state.playbackStatus
        playing = status == .playing
        elapsed = music.playbackTime
        if let entry = music.queue.currentEntry, case .song(let song)? = entry.item {
            dur = song.duration ?? dur
            let id = song.id.rawValue
            var k = songs.indices.first { $0 >= max(0, idx) && songs[$0]?.id == id }
            if k == nil { k = songs.indices.first { songs[$0]?.id == id } }
            if let k, k != idx {
                idx = k
                applyTransition()
                onTrack?(k)
            }
        }
        if playing { wasPlaying = true }
        // The queue ran out on the last playable song: the night is over.
        let last = songs.indices.last { songs[$0]?.song != nil } ?? (songs.count - 1)
        if !busy && wasPlaying && idx >= last && (status == .stopped || (status == .paused && dur > 0 && elapsed >= dur - 1.5)) {
            finish()
        }
    }

    // MARK: Previews (30 seconds, blended)

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if interruptionObserver == nil {
            interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                Task { @MainActor in
                    guard let self, self.mode == .preview else { return }
                    if raw == AVAudioSession.InterruptionType.began.rawValue {
                        self.resumeAfterInterruption = self.deckA.rate > 0
                        self.deckA.pause(); self.deckB.pause()
                    } else if self.resumeAfterInterruption,
                              AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume) {
                        try? AVAudioSession.sharedInstance().setActive(true)
                        self.deckA.play()
                        if self.fading { self.deckB.play() }
                    }
                }
            }
        }
    }

    private func previewURL(_ k: Int) -> URL? {
        guard k >= 0, k < songs.count, let s = songs[k] else { return nil }
        return s.previewURL
    }

    private func playPreview(_ k: Int) {
        guard let url = previewURL(k) else { advancePreview(); return }
        deckA.replaceCurrentItem(with: AVPlayerItem(url: url))
        deckA.volume = 1
        deckA.play()
        observeEnd()
        dur = 30
        elapsed = 0
        preloadNext()
    }

    private func preloadNext() {
        guard mode == .preview, !fading else { return }
        if let url = previewURL(idx + 1) {
            if (deckB.currentItem?.asset as? AVURLAsset)?.url != url {
                deckB.replaceCurrentItem(with: AVPlayerItem(url: url))
            }
        }
    }

    private func observeEnd() {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, self.mode == .preview else { return }
                guard let item = note.object as? AVPlayerItem, item === self.deckA.currentItem else { return }
                if !self.fading { self.advancePreview() }
            }
        }
    }

    private func tickPreview() {
        playing = deckA.rate > 0 || fading
        let t = deckA.currentTime().seconds
        if t.isFinite { elapsed = max(0, t) }
        if let d = deckA.currentItem?.duration.seconds, d.isFinite, d > 0 { dur = d }
        let length = min(blend(after: idx), 8)
        if !fading && length > 0 && dur - elapsed <= length && elapsed > 1 && previewURL(idx + 1) != nil && deckA.rate > 0 {
            blendIntoNext()
        }
    }

    private func blendIntoNext() {
        fading = true
        let k = idx + 1
        guard let url = previewURL(k) else { fading = false; return }
        if (deckB.currentItem?.asset as? AVURLAsset)?.url != url {
            deckB.replaceCurrentItem(with: AVPlayerItem(url: url))
        }
        deckB.volume = 0
        deckB.seek(to: .zero)
        deckB.play()
        let t0 = Date()
        let length = max(1, min(blend(after: idx), 8))
        fadeTimer?.invalidate()
        let ft = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.fading else { return }
                let p = min(1, Date().timeIntervalSince(t0) / length)
                // Equal-power curve: no dip in loudness mid-blend.
                self.deckA.volume = Float(cos(p * .pi / 2))
                self.deckB.volume = Float(sin(p * .pi / 2))
                if p >= 1 { self.finishBlend(to: k) }
            }
        }
        RunLoop.main.add(ft, forMode: .common)
        fadeTimer = ft
    }

    private func finishBlend(to k: Int) {
        guard fading else { return }
        fadeTimer?.invalidate(); fadeTimer = nil
        deckA.pause()
        let out = deckA
        deckA = deckB
        deckB = out
        deckA.volume = 1
        fading = false
        idx = k
        dur = 30
        elapsed = 0
        observeEnd()
        preloadNext()
        onTrack?(k)
    }

    private func advancePreview() {
        guard mode == .preview else { return }
        let k = idx + 1
        if k >= songs.count { finish(); return }
        idx = k
        playPreview(k)
        onTrack?(k)
    }

    #if DEBUG
    /// Screenshots: look like a night in progress without making a sound.
    func simulate(songs list: [Track?], at k: Int, elapsed e: Double, dur d: Double) {
        stop()
        songs = list
        mode = .preview
        idx = k
        playing = true
        elapsed = e
        dur = d
    }
    #endif

    private func finish() {
        let done = onFinish
        stop()
        done?()
    }
}

enum PlayerError: LocalizedError {
    case nothingToPlay
    var errorDescription: String? { "None of these songs can be played right now." }
}
