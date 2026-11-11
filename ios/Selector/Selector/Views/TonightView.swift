import SwiftUI

/// Home. Tonight's poster, ready to start; or say what tonight is in a sentence.
struct TonightView: View {
    @Environment(AppState.self) private var app
    @State private var ask = ""
    @FocusState private var asking: Bool

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return Fmt.weekday(Date()) + (h < 12 ? " morning" : h < 17 ? " afternoon" : " evening")
    }

    /// A night that was planned or started and not finished.
    private var openNight: Night? {
        guard let n = app.night, n.startedAt != nil || app.player.isActive else { return nil }
        return n
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .center) {
                    Text(greeting).font(.text(15, .semibold)).foregroundStyle(Theme.ink2)
                    Spacer()
                    Button {
                        app.sheet = .connect
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(app.authorized && app.subscribed == true ? Theme.good : Theme.ink3).frame(width: 8, height: 8)
                            Text(app.authorized && app.subscribed == true ? "Apple Music" : "Previews")
                                .font(.text(13, .semibold)).foregroundStyle(Theme.ink2)
                        }
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Theme.surface2, in: Capsule())
                    }
                    .buttonStyle(PressStyle())
                }
                .padding(.top, 8)

                poster

                VStack(alignment: .leading, spacing: 10) {
                    Text("Or describe the night").font(.text(15, .semibold)).foregroundStyle(Theme.ink2)
                    HStack(spacing: 8) {
                        TextField("", text: $ask, prompt: Text("House party, hip-hop and afrobeats, till 1am").foregroundStyle(Theme.ink3))
                            .font(.text(16, .regular))
                            .foregroundStyle(Theme.ink)
                            .focused($asking)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .padding(.leading, 18)
                        Button(action: submit) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(ask.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.ink3 : Theme.onColor)
                                .frame(width: 40, height: 40)
                                .background(ask.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.surface3 : app.accent, in: Circle())
                        }
                        .buttonStyle(PressStyle())
                        .padding(.trailing, 7)
                    }
                    .frame(height: 54)
                    .background(Theme.surface2, in: Capsule())
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Other nights").font(.text(15, .semibold)).foregroundStyle(Theme.ink2)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Occasion.all.filter { $0.key != app.settings.occasion }) { o in
                                quickPoster(o)
                            }
                        }
                    }
                    .scrollClipDisabled()
                }

                if !app.nights.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Nights you've played").font(.text(15, .semibold)).foregroundStyle(Theme.ink2)
                        ForEach(app.nights.prefix(4)) { n in
                            nightRow(n)
                        }
                    }
                }
                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func submit() {
        let text = ask.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        asking = false
        app.planFromText(text)
        if app.current == .plan { ask = "" }
    }

    // MARK: Tonight's poster

    private var poster: some View {
        let s = app.settings
        let open = openNight
        let title = open?.plan.title ?? s.title
        let sounds = open?.plan.soundsByWeight ?? s.sounds
        let length = open.map { _ in "" } ?? Fmt.lengthWords(minutes: s.minutes)
        return ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [app.accent, app.accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
            Vinyl(label: Theme.ink)
                .frame(width: 250)
                .offset(x: 78, y: 70)
            VStack(alignment: .leading, spacing: 0) {
                Text(open != nil ? (app.player.isActive ? "Playing now" : "Pick up where you left off") : "Tonight")
                    .font(.text(15, .bold)).foregroundStyle(Theme.onColor.opacity(0.7))
                Spacer(minLength: 12)
                Poster(text: title, size: 64, color: Theme.onColor, lines: 3)
                    .padding(.trailing, 40)
                Text(([length] + sounds.prefix(3).map { Vibes.name($0) }).filter { !$0.isEmpty }.joined(separator: ", ") + (sounds.count > 3 ? " and more" : ""))
                    .font(.text(16, .semibold)).foregroundStyle(Theme.onColor.opacity(0.78))
                    .padding(.top, 10)
                    .padding(.trailing, 90)
                HStack(spacing: 10) {
                    if open != nil {
                        PrimaryButton(title: app.player.isActive ? "Back to the night" : "Continue", onColor: true) {
                            app.go(app.player.isActive ? .playing : .plan)
                        }
                    } else {
                        PrimaryButton(title: "Start the night", onColor: true) {
                            if app.planNight() { app.go(.plan) }
                        }
                        GhostButton(title: "Change", onColor: true) { app.go(.brief) }
                    }
                }
                .padding(.top, 22)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(height: 400)
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .animation(.easeInOut(duration: 0.35), value: app.accentHex)
    }

    private func quickPoster(_ o: Occasion) -> some View {
        let sounds = o.weights.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map { $0.key }
        let a = Color(hex: Vibes.hex(sounds.first ?? "pop"))
        let b = sounds.count > 1 ? Color(hex: Vibes.hex(sounds[1])) : a
        return Button {
            Haptics.tap()
            app.applyOccasion(o.key)
            if app.planNight() { app.go(.plan) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Text(Fmt.length(Double(o.minutes * 60))).font(.text(13, .bold)).foregroundStyle(Theme.onColor.opacity(0.65))
                Spacer()
                Poster(text: o.label, size: 25, color: Theme.onColor, lines: 3)
            }
            .padding(14)
            .frame(width: 150, height: 180, alignment: .topLeading)
            .background(LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }

    private func nightRow(_ n: Recap) -> some View {
        let keys = n.weights.filter { $0.value > 0 }.keys.sorted()
        let tiles: [(url: URL?, color: Color)] = (0..<4).map { q in
            let key = keys.isEmpty ? "pop" : keys[q % keys.count]
            return (n.arts.count > q ? n.arts[q].flatMap { URL(string: $0) } : nil, Color.shade(Vibes.hex(key), Double(-10 * q)))
        }
        let peak = n.peakJ < (app.planner?.cat.count ?? 0) ? Catalog.shortTitle(app.trackName(n.peakJ)) : ""
        return Button {
            app.recap = n
            app.go(.recap)
        } label: {
            HStack(spacing: 14) {
                Mosaic(tiles: tiles, radius: 4, gap: 2).frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 3) {
                    Text(n.title).font(.text(16, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text("\(n.date), \(Fmt.length(n.seconds))\(peak.isEmpty ? "" : ". Peaked with \(peak)")")
                        .font(.text(14, .regular)).foregroundStyle(Theme.ink2).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink3)
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(PressStyle())
    }
}
