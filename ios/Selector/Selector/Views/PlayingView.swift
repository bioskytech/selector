import SwiftUI
import MusicKit

/// The night, playing. The room takes the colour of the record that's on.
struct PlayingView: View {
    @Environment(AppState.self) private var app
    @State private var confirmEnd = false

    var body: some View {
        ZStack {
            backdrop
            if let night = app.night, app.player.idx >= 0, app.player.idx < night.plan.seq.count {
                let k = app.player.idx
                let j = night.plan.seq[k]
                VStack(spacing: 0) {
                    HStack {
                        IconButton(system: "chevron.down", size: 19) { app.back() }
                        Spacer()
                        VStack(spacing: 1) {
                            Text(night.plan.title).font(.text(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                            if let p = app.planner?.phase(of: k, in: night.plan) {
                                Text("\(p.label), song \(k + 1) of \(night.plan.seq.count)").font(.text(12, .regular)).foregroundStyle(Theme.ink2)
                            }
                        }
                        Spacer()
                        Button("End") { confirmEnd = true }
                            .font(.text(15, .semibold)).foregroundStyle(Theme.ink2)
                            .frame(width: 44, height: 44)
                    }
                    .frame(height: 44)
                    .padding(.horizontal, 8)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            Cover(url: app.coverURL(k, size: 800), color: app.coverColor(j), radius: 18)
                                .aspectRatio(1, contentMode: .fit)
                                .shadow(color: .black.opacity(0.5), radius: 30, y: 16)
                                .padding(.horizontal, 14)
                                .padding(.top, 8)
                                .scaleEffect(app.player.playing ? 1 : 0.94)
                                .animation(.spring(response: 0.45, dampingFraction: 0.7), value: app.player.playing)
                                .id(j)
                                .transition(.opacity)

                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.trackName(j)).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(2)
                                    Text(app.trackArtists(j)).font(.text(17, .regular)).foregroundStyle(Theme.ink2).lineLimit(1)
                                }
                                Spacer()
                                Button { app.toggleLove() } label: {
                                    Image(systemName: app.lovedNow ? "heart.fill" : "heart")
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(app.lovedNow ? app.accent : Theme.ink)
                                        .frame(width: 48, height: 48)
                                        .background(Color.white.opacity(0.1), in: Circle())
                                        .symbolEffect(.bounce, value: app.lovedNow)
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityLabel(app.lovedNow ? "Loved" : "Love this song")
                            }

                            progress

                            HStack(spacing: 40) {
                                IconButton(system: "backward.fill", size: 26) { Task { await app.player.previous() } }
                                Button {
                                    Haptics.thud()
                                    Task { await app.player.toggle() }
                                } label: {
                                    Image(systemName: app.player.playing ? "pause.fill" : "play.fill")
                                        .font(.system(size: 30, weight: .heavy))
                                        .foregroundStyle(Theme.onColor)
                                        .frame(width: 76, height: 76)
                                        .background(Theme.ink, in: Circle())
                                        .contentTransition(.symbolEffect(.replace))
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityLabel(app.player.playing ? "Pause" : "Play")
                                IconButton(system: "forward.fill", size: 26) { Task { await app.skip() } }
                            }

                            if k + 1 < night.plan.seq.count { nextCard(night: night, k: k + 1) }

                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    app.steerReply = nil
                                    app.steerChosen = nil
                                    app.sheet = .steer
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "bubble.left.fill").font(.system(size: 14))
                                        Text("Tell your DJ anything").font(.text(16, .regular))
                                        Spacer()
                                    }
                                    .foregroundStyle(Theme.ink2)
                                    .padding(.horizontal, 18)
                                    .frame(height: 52)
                                    .background(Color.white.opacity(0.1), in: Capsule())
                                }
                                .buttonStyle(PressStyle())
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(Array(app.steerChips(short: true).enumerated()), id: \.offset) { _, c in
                                            Chip(label: c.label, light: true) {
                                                app.sheet = .steer
                                                app.doSteer([c.intent])
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .padding(.horizontal, -20)
                            }

                            Button {
                                if app.player.mode == .preview { app.sheet = .connect }
                            } label: {
                                Text(app.modeText + (app.player.mode == .preview ? " Get full songs" : ""))
                                    .font(.text(13, .regular)).foregroundStyle(Theme.ink3).multilineTextAlignment(.center)
                            }
                            .buttonStyle(.plain)
                            .padding(.bottom, 24)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            } else {
                VStack(spacing: 14) {
                    Spacer()
                    Text("Nothing's playing").font(.text(17, .semibold)).foregroundStyle(Theme.ink2)
                    GhostButton(title: "Back") { app.back() }
                    Spacer()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("End the night here?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End the night", role: .destructive) { app.endNight() }
            Button("Keep playing", role: .cancel) {}
        }
    }

    /// The artwork, blown up and blurred, with the plum night over it.
    private var backdrop: some View {
        let k = app.player.idx
        let j = app.night.flatMap { n in k >= 0 && k < n.plan.seq.count ? n.plan.seq[k] : nil }
        return ZStack {
            Theme.bg
            if let j {
                Cover(url: app.coverURL(k, size: 200), color: app.coverColor(j), radius: 0)
                    .blur(radius: 70)
                    .opacity(0.75)
                    .id(j)
                    .transition(.opacity)
            }
            LinearGradient(colors: [Theme.bg.opacity(0.25), Theme.bg.opacity(0.78), Theme.bg], startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: 0.8), value: j)
        .ignoresSafeArea()
    }

    private var progress: some View {
        let d = max(app.player.dur, 1)
        let e = min(app.player.elapsed, d)
        return VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule().fill(Theme.ink).frame(width: max(5, geo.size.width * e / d))
                }
            }
            .frame(height: 5)
            HStack {
                Text(Fmt.time(e))
                Spacer()
                Text("-" + Fmt.time(max(0, d - e)))
            }
            .font(.text(13, .regular)).foregroundStyle(Theme.ink2).monospacedDigit()
        }
    }

    private func nextCard(night: Night, k: Int) -> some View {
        let j = night.plan.seq[k]
        let d = max(app.player.dur, 1)
        let rem = max(0, d - app.player.elapsed)
        let blend = app.player.blend(after: k - 1)
        let blending = app.player.fading || (blend > 0 && rem <= blend + 0.5)
        let word = app.planner?.transitionWord(night.plan.seq[k - 1], j)
        return Button { app.go(.songs) } label: {
            HStack(spacing: 13) {
                Cover(url: app.coverURL(k, size: 200), color: app.coverColor(j), radius: 8).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(blending ? "Blending in now" : "Next, \(word?.lowercased() ?? "a smooth blend") in \(Fmt.time(rem))")
                        .font(.text(13, .semibold)).foregroundStyle(blending ? app.accent : Theme.ink2)
                    Text(app.trackName(j)).font(.text(16, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                }
                Spacer()
                Image(systemName: "list.bullet").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink2)
            }
            .padding(12)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

/// Tell your DJ: say it, or tap one. The DJ answers with what changes.
struct SteerSheet: View {
    @Environment(AppState.self) private var app
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        SheetFrame(title: "Tell your DJ", subtitle: "Ask for a song, an artist, a sound or a mood. Changes land after the song that's on.") {
            HStack(spacing: 8) {
                TextField("", text: $text, prompt: Text("Play Brown Munde, then bring it down").foregroundStyle(Theme.ink3))
                    .font(.text(16, .regular))
                    .foregroundStyle(Theme.ink)
                    .focused($typing)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.leading, 18)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.onColor)
                        .frame(width: 40, height: 40)
                        .background(app.accent, in: Circle())
                }
                .buttonStyle(PressStyle())
                .padding(.trailing, 7)
            }
            .frame(height: 54)
            .background(Theme.surface2, in: Capsule())

            if let reply = app.steerReply {
                VStack(alignment: .leading, spacing: 10) {
                    Text(reply).font(.text(17, .semibold)).foregroundStyle(Theme.onColor)
                        .fixedSize(horizontal: false, vertical: true)
                    if app.night?.undo != nil {
                        Button("Undo") { app.undoSteer() }
                            .font(.text(15, .bold)).foregroundStyle(Theme.onColor)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(Color.black.opacity(0.14), in: Capsule())
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(app.accent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            FlowLayout(spacing: 8) {
                ForEach(Array(app.steerChips(short: false).enumerated()), id: \.offset) { _, c in
                    Chip(label: c.label, on: app.steerChosen == c.intent.key) {
                        app.doSteer([c.intent])
                    }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: app.steerReply)
        .presentationDetents([.height(500), .large])
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        app.steerFromText(t)
        text = ""
    }
}

/// How the music is coming through, and how to get full songs.
struct ConnectSheet: View {
    @Environment(AppState.self) private var app

    private var full: Bool { app.authorized && app.subscribed == true && app.musicKitOK }

    var body: some View {
        SheetFrame(title: full ? "Apple Music is connected" : "Hear the full songs",
                   subtitle: full
                    ? "Nights play as full songs, blended into each other."
                    : (app.authorized && app.subscribed == true
                       ? "Apple Music isn't answering for this build, so you're hearing previews. MusicKit needs to be switched on for the app's identifier in the Apple Developer account."
                       : "Right now you hear 30 seconds of every song, blended. With an Apple Music subscription the same night plays in full.")) {
            VStack(spacing: 10) {
                if !full {
                    PrimaryButton(title: app.authorized ? (app.subscribed == true ? "Try again" : "Get Apple Music") : "Connect Apple Music", icon: nil, wide: true) {
                        Task { await app.connectAppleMusic() }
                    }
                    .musicSubscriptionOffer(isPresented: Binding(get: { app.showOffer }, set: { app.showOffer = $0 }))
                }
                GhostButton(title: full ? "Done" : "Keep the previews") { app.sheet = nil }
                    .frame(maxWidth: .infinity)
            }
        }
        .presentationDetents([.height(340)])
    }
}

/// The strip at the bottom of other screens while the night plays.
struct MiniPlayer: View {
    @Environment(AppState.self) private var app

    var body: some View {
        if let night = app.night, app.player.idx >= 0, app.player.idx < night.plan.seq.count {
            let k = app.player.idx
            let j = night.plan.seq[k]
            Button { app.go(.playing) } label: {
                HStack(spacing: 12) {
                    Cover(url: app.coverURL(k, size: 200), color: app.coverColor(j), radius: 8).frame(width: 42, height: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.trackName(j)).font(.text(15, .semibold)).foregroundStyle(Theme.onColor).lineLimit(1)
                        Text(app.trackArtist(j)).font(.text(13, .regular)).foregroundStyle(Theme.onColor.opacity(0.7)).lineLimit(1)
                    }
                    Spacer()
                    Button { Task { await app.player.toggle() } } label: {
                        Image(systemName: app.player.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .heavy))
                            .foregroundStyle(Theme.onColor)
                            .frame(width: 46, height: 46)
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.leading, 9)
                .padding(.trailing, 4)
                .padding(.vertical, 8)
                .background(app.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            }
            .buttonStyle(PressStyle())
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }
}
