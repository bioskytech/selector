import SwiftUI
import MusicKit

/// The night, playing. Artwork, transport, what's next, and the steering row.
struct PlayingView: View {
    @Environment(AppState.self) private var app

    private var tint: Color {
        guard let night = app.night, app.player.idx >= 0, app.player.idx < night.plan.seq.count else { return Theme.bg }
        if let cg = night.track(at: app.player.idx)?.tint { return Color.tint(from: cg) }
        let key = app.planner?.vibeKey(of: night.plan.seq[app.player.idx], in: night.plan) ?? "pop"
        return Color.tint(fromHex: Vibes.hex(key))
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [tint, Theme.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            if let night = app.night, app.player.idx >= 0, app.player.idx < night.plan.seq.count {
                let k = app.player.idx
                let j = night.plan.seq[k]
                VStack(spacing: 0) {
                    ZStack {
                        VStack(spacing: 2) {
                            Kicker(text: "Playing")
                            Text(night.plan.title).font(.text(13, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                        }
                        HStack {
                            IconButton(system: "chevron.down", size: 20) { app.back() }
                            Spacer()
                        }
                    }
                    .frame(height: 44)
                    .padding(.horizontal, 8)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 18) {
                            Cover(url: app.coverURL(k, size: 800), color: app.coverColor(j), radius: 20)
                                .aspectRatio(1, contentMode: .fit)
                                .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                                .padding(.top, 10)

                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(app.trackName(j)).font(.display(24)).foregroundStyle(Theme.ink).lineLimit(2)
                                    Text(app.trackArtists(j)).font(.text(15)).foregroundStyle(Theme.ink2).lineLimit(1)
                                }
                                Spacer()
                                Button { app.toggleLove() } label: {
                                    Image(systemName: app.lovedNow ? "heart.fill" : "heart")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(app.lovedNow ? Theme.accent : Theme.ink2)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                            }

                            progress

                            HStack(spacing: 34) {
                                IconButton(system: "backward.fill", size: 24) { Task { await app.player.previous() } }
                                Button { Task { await app.player.toggle() } } label: {
                                    Image(systemName: app.player.playing ? "pause.fill" : "play.fill")
                                        .font(.system(size: 28, weight: .heavy))
                                        .foregroundStyle(Theme.accentInk)
                                        .frame(width: 68, height: 68)
                                        .background(Color.white, in: Circle())
                                }
                                .buttonStyle(.plain)
                                IconButton(system: "forward.fill", size: 24) { Task { await app.player.next() } }
                            }
                            .padding(.vertical, 4)

                            if k + 1 < night.plan.seq.count { nextCard(night: night, k: k + 1) }

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(app.steerChips(short: true).enumerated()), id: \.offset) { _, c in
                                        Chip(label: c.label, icon: c.action == "up" ? "arrow.up" : (c.action == "down" ? "arrow.down" : nil), light: true) {
                                            app.steerReply = nil
                                            app.steerChosen = nil
                                            app.sheet = .steer
                                            app.doSteer(c.action, c.arg)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            .padding(.horizontal, -20)

                            Text(app.modeText).font(.text(11)).foregroundStyle(Theme.ink3).multilineTextAlignment(.center)
                                .padding(.bottom, 24)
                        }
                        .padding(.horizontal, 20)
                    }
                }
            } else {
                VStack {
                    Spacer()
                    Text("Nothing playing").font(.text(15)).foregroundStyle(Theme.ink2)
                    Spacer()
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var progress: some View {
        let d = max(app.player.dur, 1)
        let e = min(app.player.elapsed, d)
        return VStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(Color.white).frame(width: geo.size.width * e / d)
                }
            }
            .frame(height: 4)
            HStack {
                Text(Fmt.time(e))
                Spacer()
                Text("−" + Fmt.time(max(0, d - e)))
            }
            .font(.text(12)).foregroundStyle(Theme.ink2).monospacedDigit()
        }
    }

    private func nextCard(night: Night, k: Int) -> some View {
        let j = night.plan.seq[k]
        let d = max(app.player.dur, 1)
        let rem = max(0, d - app.player.elapsed)
        let blending = app.player.fading || (app.player.crossfade > 0 && rem <= max(app.player.crossfade, 10) + 0.5)
        return Button { app.go(.songs) } label: {
            HStack(spacing: 12) {
                Cover(url: app.coverURL(k, size: 200), color: app.coverColor(j), radius: 8).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Kicker(text: blending ? "Blending in · \(Fmt.time(rem))" : "Up next · \(Fmt.time(rem))", color: blending ? Theme.accent : Theme.ink2)
                    HStack(spacing: 4) {
                        Text(app.trackName(j)).font(.text(14, .bold)).foregroundStyle(Theme.ink)
                        Text("· " + app.trackArtist(j)).font(.text(14)).foregroundStyle(Theme.ink2)
                    }
                    .lineLimit(1)
                }
                Spacer()
                ZStack {
                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 3)
                    Circle().trim(from: 0, to: min(1, app.player.elapsed / d)).stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 24, height: 24)
            }
            .padding(12)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Tell your DJ: chips, a free-text request, and the DJ's reply.
struct SteerSheet: View {
    @Environment(AppState.self) private var app
    @State private var text = ""

    var body: some View {
        SheetFrame(title: "Tell your DJ", subtitle: "Changes land after the current song, so the floor never feels it.") {
            FlowLayout(spacing: 8) {
                ForEach(Array(app.steerChips(short: false).enumerated()), id: \.offset) { _, c in
                    Chip(label: c.label, icon: c.action == "up" ? "arrow.up" : (c.action == "down" ? "arrow.down" : nil),
                         on: app.steerChosen == c.action + "|" + (c.arg ?? "")) {
                        app.doSteer(c.action, c.arg)
                    }
                }
            }
            if let reply = app.steerReply {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Theme.accentInk.opacity(0.25)).frame(width: 18, height: 18)
                            .overlay(Circle().fill(Theme.accentInk).frame(width: 6, height: 6))
                        Text(reply).font(.text(15, .bold)).foregroundStyle(Theme.accentInk)
                    }
                    if app.night?.undo != nil {
                        Button("Undo") { app.undoSteer() }
                            .font(.text(14, .heavy)).foregroundStyle(Theme.accentInk).underline()
                            .padding(.leading, 28)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            HStack(spacing: 8) {
                TextField("Or say it your way: slow it down after this", text: $text)
                    .font(.text(15))
                    .foregroundStyle(Theme.ink)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .padding(.horizontal, 16)
                    .frame(height: 46)
                    .background(Theme.surface2, in: Capsule())
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(Theme.accentInk)
                        .frame(width: 46, height: 46)
                        .background(Theme.accent, in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .presentationDetents([.height(440), .large])
    }

    private func send() {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        app.steerFromText(t)
        if app.steerChosen != nil { text = "" }
    }
}

/// No subscription on this Apple ID: previews, or a subscription offer.
struct ConnectSheet: View {
    @Environment(AppState.self) private var app

    var body: some View {
        SheetFrame(title: "Hear the whole night", subtitle: "Full songs need an Apple Music subscription on this iPhone. You can still hear 30-second previews of every song, blended.") {
            VStack(spacing: 10) {
                PrimaryButton(title: "Play previews", icon: "play.fill", wide: true) {
                    Task { await app.play(.preview, from: app.pendingStart) }
                }
                Button {
                    app.showOffer = true
                } label: {
                    Text("Get Apple Music")
                        .font(.text(16, .heavy))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .overlay(Capsule().stroke(Theme.hair2, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .musicSubscriptionOffer(isPresented: Binding(get: { app.showOffer }, set: { app.showOffer = $0 }))
            }
        }
        .presentationDetents([.height(300)])
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
                    Cover(url: app.coverURL(k, size: 200), color: app.coverColor(j), radius: 8).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.trackName(j)).font(.text(14, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                        Text(app.trackArtist(j)).font(.text(12)).foregroundStyle(Theme.ink2).lineLimit(1)
                    }
                    Spacer()
                    Button { Task { await app.player.toggle() } } label: {
                        Image(systemName: app.player.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .padding(.vertical, 8)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.hair, lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
        }
    }
}
