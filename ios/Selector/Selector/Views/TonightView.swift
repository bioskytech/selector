import SwiftUI

/// Home. One decision: start the night that's ready, or change it.
struct TonightView: View {
    @Environment(AppState.self) private var app

    private var dayline: String {
        let h = Calendar.current.component(.hour, from: Date())
        return Fmt.weekday(Date()) + (h < 12 ? " morning" : h < 17 ? " afternoon" : " evening")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Kicker(text: dayline)
                        Text("Tonight").font(.display(32)).foregroundStyle(Theme.ink)
                    }
                    Spacer()
                    Button {
                        if app.authorized {
                            app.say(app.subscribed == false ? "Connected, but this Apple ID has no Apple Music subscription" : "Apple Music connected")
                        } else {
                            Task { if await app.ensureAuthorized() { app.say("Apple Music connected") } }
                        }
                    } label: {
                        Text("B")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 36, height: 36)
                            .background(Theme.surface3, in: Circle())
                            .overlay(Circle().stroke(app.authorized && app.subscribed != false ? Theme.good : Color.clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 6)

                Button { app.go(.brief) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .bold))
                        Text("Tell your DJ what tonight is").font(.text(15))
                        Spacer()
                        Image(systemName: "mic").font(.system(size: 15, weight: .bold))
                    }
                    .foregroundStyle(Theme.ink2)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                    .background(Theme.surface2, in: Capsule())
                }
                .buttonStyle(.plain)

                heroCard

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Quick starts").font(.display(20)).foregroundStyle(Theme.ink)
                        Spacer()
                        Button("See all") { app.go(.brief); app.sheet = .occasion }
                            .font(.text(14, .bold)).foregroundStyle(Theme.ink2)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Occasion.all.filter { $0.key != app.settings.occasion }.prefix(6)) { o in
                                quickTile(o)
                            }
                        }
                    }
                    .scrollClipDisabled()
                }

                if !app.nights.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your nights").font(.display(20)).foregroundStyle(Theme.ink)
                        ForEach(app.nights.prefix(3)) { n in
                            nightRow(n)
                        }
                    }
                }

                Text("Your DJ learned from 5,040 real DJ sets. Songs play through your own Apple Music.")
                    .font(.text(12))
                    .foregroundStyle(Theme.ink3)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var heroCard: some View {
        let s = app.settings
        let sounds = s.sounds
        let cols = Array(sounds.prefix(4))
        let tiles: [(url: URL?, color: Color)] = (0..<4).map { i in
            let key = cols.isEmpty ? "pop" : cols[min(i, cols.count - 1)]
            let shades: [Double] = [0, -14, 12, -6]
            return (nil, Color.shade(Vibes.hex(key), shades[i]))
        }
        return VStack(alignment: .leading, spacing: 16) {
            Kicker(text: "Ready for you")
            HStack(alignment: .top, spacing: 16) {
                Mosaic(tiles: tiles).frame(width: 100, height: 100)
                VStack(alignment: .leading, spacing: 5) {
                    Text(s.title).font(.display(22)).foregroundStyle(Theme.ink).lineLimit(2)
                    Text("\(Fmt.length(Double(s.minutes * 60))) · \(sounds.prefix(3).map { Vibes.name($0) }.joined(separator: ", "))\(sounds.count > 3 ? " +\(sounds.count - 3)" : "")")
                        .font(.text(14)).foregroundStyle(Theme.ink2)
                    Text(app.taste.map { t in "Tuned to \(t.matched.prefix(2).joined(separator: " and "))\(t.matched.count > 2 ? " and more" : "")" } ?? "From the sounds you pick most")
                        .font(.text(12)).foregroundStyle(Theme.ink3)
                }
            }
            HStack(spacing: 10) {
                PrimaryButton(title: "Start the night") {
                    if app.planNight() { app.go(.plan) }
                }
                GhostButton(title: "Change") { app.go(.brief) }
            }
        }
        .padding(18)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.hair, lineWidth: 1))
    }

    private func quickTile(_ o: Occasion) -> some View {
        let key = o.weights.max { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) }?.key ?? "pop"
        let style = Vibes.style(key)
        return Button {
            app.applyOccasion(o.key)
            app.go(.brief)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RecordPattern(color: Color.shade(style.hex, -30))
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .offset(x: 78, y: 26)
                    .opacity(0.9)
                Text(o.label)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(style.dark ? Theme.accentInk : Theme.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .padding(12)
            }
            .frame(width: 128, height: 100, alignment: .bottomLeading)
            .background(Color(hex: style.hex))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
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
                Mosaic(tiles: tiles, radius: 4, gap: 2).frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(n.title).font(.text(15, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text("\(n.date) · \(Fmt.length(n.seconds))\(peak.isEmpty ? "" : " · peaked with \(peak)")")
                        .font(.text(13)).foregroundStyle(Theme.ink2).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink3)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
