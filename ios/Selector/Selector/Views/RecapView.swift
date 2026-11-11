import SwiftUI

/// The morning after: the night as a poster, ready to share.
struct RecapView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TopBar("", onBack: { app.home() })
            if let r = app.recap {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        poster(r)
                        HStack(spacing: 10) {
                            ShareLink(item: app.shareText(r)) {
                                HStack(spacing: 10) {
                                    Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .bold))
                                    Text("Share the night")
                                }
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(Theme.onColor)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(color(r), in: Capsule())
                            }
                            .buttonStyle(PressStyle())
                            GhostButton(title: "Play it again") { app.playAgain(r) }
                        }
                        if r.saved {
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.good)
                                Text("Saved to Apple Music as a playlist").font(.text(15, .medium)).foregroundStyle(Theme.ink2)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            } else {
                Spacer()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func keys(_ r: Recap) -> [String] {
        r.weights.filter { $0.value > 0 }.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map { $0.key }
    }
    private func color(_ r: Recap) -> Color { Color(hex: Vibes.hex(keys(r).first ?? "punjabi")) }

    private func poster(_ r: Recap) -> some View {
        let ks = keys(r)
        let a = color(r)
        let b = Color.shade(Vibes.hex(ks.first ?? "punjabi"), -22)
        let known = r.peakJ < (app.planner?.cat.count ?? 0)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(r.date) night").font(.text(15, .bold)).foregroundStyle(Theme.onColor.opacity(0.7))
            Poster(text: r.title, size: r.title.count > 16 ? 46 : 64, color: Theme.onColor)
                .padding(.top, 8)

            HStack(spacing: -16) {
                ForEach(0..<5, id: \.self) { i in
                    let key = ks.isEmpty ? "pop" : ks[i % ks.count]
                    let url = i < r.arts.count ? r.arts[i].flatMap { URL(string: $0) } : nil
                    Cover(url: url, color: Color.shade(Vibes.hex(key), Double(-12 * (i % 3)) - 18), radius: 8)
                        .frame(width: 76, height: 76)
                        .shadow(color: .black.opacity(0.35), radius: 8, x: -3, y: 4)
                        .rotationEffect(.degrees(Double(i - 2) * 4))
                        .zIndex(Double(i))
                }
            }
            .padding(.top, 22)

            VStack(alignment: .leading, spacing: 4) {
                Text("The floor peaked at \(r.peakAt) with").font(.text(15, .semibold)).foregroundStyle(Theme.onColor.opacity(0.7))
                Text(known ? Catalog.shortTitle(app.trackName(r.peakJ)) : "")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.onColor).lineLimit(2)
                Text(known ? app.trackArtists(r.peakJ) : "")
                    .font(.text(16, .medium)).foregroundStyle(Theme.onColor.opacity(0.78)).lineLimit(1)
            }
            .padding(.top, 26)

            HStack(alignment: .top, spacing: 28) {
                stat("\(r.songs)", "songs")
                stat(Fmt.length(r.seconds), "of music")
                if r.loved > 0 { stat("\(r.loved)", "loved") }
                if r.requests > 0 { stat("\(r.requests)", r.requests == 1 ? "request" : "requests") }
            }
            .padding(.top, 26)

            Text("Planned by Selector").font(.text(13, .bold)).foregroundStyle(Theme.onColor.opacity(0.55))
                .padding(.top, 22)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value.uppercased()).font(.poster(30)).foregroundStyle(Theme.onColor)
            Text(label).font(.text(13, .semibold)).foregroundStyle(Theme.onColor.opacity(0.7))
        }
    }
}
