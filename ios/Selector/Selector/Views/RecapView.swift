import SwiftUI

/// The morning after: what the night was, shareable.
struct RecapView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TopBar("Last night", onBack: { app.home() })
            if let r = app.recap {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(r.title).font(.display(30)).foregroundStyle(Theme.ink)
                            Text("\(r.date) · \(Fmt.length(r.seconds)) · \(r.songs) songs\(r.requests == 0 ? " · no requests needed" : "")")
                                .font(.text(14)).foregroundStyle(Theme.ink2)
                        }
                        card(r)
                        HStack(spacing: 10) {
                            ShareLink(item: app.shareText(r)) {
                                HStack(spacing: 10) {
                                    Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .heavy))
                                    Text("Share the night")
                                }
                                .font(.system(size: 16, weight: .heavy))
                                .foregroundStyle(Theme.accentInk)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Theme.accent, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            Button { app.playAgain(r) } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 18, weight: .heavy))
                                    .foregroundStyle(Theme.ink)
                                    .frame(width: 54, height: 54)
                                    .overlay(Circle().stroke(Theme.hair2, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        if r.saved {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.good)
                                Text("Saved to Apple Music as a playlist").font(.text(14, .bold)).foregroundStyle(Theme.ink)
                                Spacer()
                            }
                            .padding(14)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private func card(_ r: Recap) -> some View {
        let keys = r.weights.filter { $0.value > 0 }.keys.sorted()
        let cols = [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)]
        return ZStack(alignment: .bottom) {
            VStack {
                LazyVGrid(columns: cols, spacing: 3) {
                    ForEach(0..<15, id: \.self) { i in
                        let key = keys.isEmpty ? "pop" : keys[i % keys.count]
                        let url = i < r.arts.count ? r.arts[i].flatMap { URL(string: $0) } : nil
                        Cover(url: url, color: Color.shade(Vibes.hex(key), Double((i % 3) * 9 - 9)), radius: 0)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
                .rotationEffect(.degrees(-8))
                .scaleEffect(1.25)
                .offset(x: -20, y: -30)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 14) {
                Kicker(text: "The floor peaked at \(r.peakAt)")
                HStack(spacing: 14) {
                    Cover(url: r.peakArt.flatMap { URL(string: $0) }, color: peakColor(r), radius: 12)
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(r.peakJ < (app.planner?.cat.count ?? 0) ? Catalog.shortTitle(app.trackName(r.peakJ)) : "")
                            .font(.display(24)).foregroundStyle(Theme.ink).lineLimit(2)
                        Text(r.peakJ < (app.planner?.cat.count ?? 0) ? app.trackArtists(r.peakJ) : "")
                            .font(.text(15)).foregroundStyle(Theme.ink2).lineLimit(1)
                    }
                }
                HStack(spacing: 24) {
                    stat("\(r.songs)", "songs")
                    stat("\(r.loved)", "you loved")
                    stat("\(r.requests)", r.requests == 1 ? "request" : "requests")
                }
                HStack(spacing: 8) {
                    Circle().fill(Theme.accent).frame(width: 14, height: 14)
                    Text("SELECTOR").font(.system(size: 12, weight: .heavy)).tracking(0.6).foregroundStyle(Theme.ink2)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Theme.surface.opacity(0), Theme.surface, Theme.surface], startPoint: .top, endPoint: .bottom)
                    .padding(.top, -60)
            )
        }
        .frame(height: 400)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.hair, lineWidth: 1))
    }

    private func peakColor(_ r: Recap) -> Color {
        let keys = r.weights.filter { $0.value > 0 }.keys.sorted()
        return Color(hex: Vibes.hex(keys.first ?? "punjabi"))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.display(20)).foregroundStyle(Theme.ink)
            Text(label).font(.text(12, .bold)).foregroundStyle(Theme.ink2)
        }
    }
}
