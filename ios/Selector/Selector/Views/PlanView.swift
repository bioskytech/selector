import SwiftUI

/// The plan: what the DJ will do tonight, in a sentence, then the journey.
struct PlanView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TopBar("", onBack: { app.back() }) {
                Button("New take") { app.newTake() }
                    .font(.text(15, .bold)).foregroundStyle(Theme.ink2)
                    .frame(height: 44).padding(.trailing, 8)
            }
            if let night = app.night, let planner = app.planner {
                let plan = night.plan
                let n = plan.seq.count
                let tot = planner.totalSeconds(plan)
                ScrollView {
                    VStack(spacing: 18) {
                        Mosaic(tiles: [0, n / 3, 2 * n / 3, n - 1].map { k in
                            let kk = min(max(k, 0), max(0, n - 1))
                            return (app.coverURL(kk), app.coverColor(plan.seq.isEmpty ? 0 : plan.seq[kk]))
                        }, radius: 10, gap: 4)
                        .frame(width: 200, height: 200)
                        .padding(.top, 6)

                        VStack(spacing: 6) {
                            Text(plan.title).font(.display(28)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                            Text("\(Fmt.length(tot)) · \(n) songs · ends \(Fmt.clock(app.clock(afterSeconds: tot)))")
                                .font(.text(14)).foregroundStyle(Theme.ink2)
                        }

                        HStack(spacing: 10) {
                            PrimaryButton(title: app.player.isActive ? "Back to the night" : "Start the night") {
                                Task { await app.startNight(from: 0) }
                            }
                            Button {
                                Task { await app.savePlaylist() }
                            } label: {
                                Image(systemName: night.saved ? "checkmark" : "plus")
                                    .font(.system(size: 20, weight: .heavy))
                                    .foregroundStyle(night.saved ? Theme.accentInk : Theme.ink)
                                    .frame(width: 54, height: 54)
                                    .background(night.saved ? Theme.accent : Color.clear, in: Circle())
                                    .overlay(Circle().stroke(night.saved ? Color.clear : Theme.hair2, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                        Text(app.planStatus)
                            .font(.text(12)).foregroundStyle(Theme.ink3)
                            .multilineTextAlignment(.center)
                            .frame(minHeight: 16)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                Circle().fill(Theme.accent).frame(width: 18, height: 18)
                                    .overlay(Circle().fill(Theme.accentInk).frame(width: 6, height: 6))
                                Kicker(text: "Your DJ")
                            }
                            Text(planner.djNote(plan, startedAt: night.startedAt))
                                .font(.text(15))
                                .foregroundStyle(Theme.ink)
                                .lineSpacing(3)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        VStack(alignment: .leading, spacing: 8) {
                            JourneyChart().frame(height: 64)
                            HStack {
                                ForEach(planner.phases(plan)) { p in
                                    if p.key == "peak" {
                                        Text("Peak · \(peakWhen(p, planner: planner, startedAt: night.startedAt))")
                                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.accent)
                                    } else {
                                        Text(p.label).font(.text(12, .bold)).foregroundStyle(Theme.ink3)
                                    }
                                    if p.key != planner.phases(plan).last?.key { Spacer() }
                                }
                            }
                        }
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                        VStack(spacing: 0) {
                            ForEach(Array(plan.seq.prefix(2).indices), id: \.self) { k in
                                Button { app.go(.songs) } label: { SongRow(k: k) }
                                    .buttonStyle(.plain)
                            }
                            Button {
                                app.go(.songs)
                            } label: {
                                HStack {
                                    Text("All \(n) songs").font(.text(15, .bold)).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink3)
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            } else {
                Spacer()
                ProgressView().tint(Theme.ink)
                Spacer()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private func peakWhen(_ p: Phase, planner: SetPlanner, startedAt: Date?) -> String {
        var when = planner.whenText(p.start, startedAt: startedAt)
        if when.hasPrefix("at ") { when.removeFirst(3) }
        if when.hasPrefix("about ") { when.removeFirst(6) }
        return when
    }
}
