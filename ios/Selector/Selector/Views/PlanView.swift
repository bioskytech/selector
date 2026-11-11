import SwiftUI

/// The plan: the sleeves, the DJ's word on how the night will go, and its shape.
struct PlanView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TopBar("", onBack: { app.back() }) {
                if !app.player.isActive {
                    Button("New take") { Haptics.tap(); app.newTake() }
                        .font(.text(16, .semibold)).foregroundStyle(Theme.ink2)
                        .frame(height: 44).padding(.trailing, 10)
                }
            }
            if let night = app.night, let planner = app.planner {
                let plan = night.plan
                let n = plan.seq.count
                let tot = planner.totalSeconds(plan)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Fan(tiles: app.nightTiles(), size: 142)
                            .padding(.top, 14)
                            .padding(.bottom, 14)

                        VStack(alignment: .leading, spacing: 12) {
                            Poster(text: plan.title, size: plan.title.count > 16 ? 42 : 56)
                            Text("\(n) songs, \(Fmt.length(tot)). Ends around \(Fmt.clock(app.clock(afterSeconds: tot))).")
                                .font(.text(16, .regular)).foregroundStyle(Theme.ink2)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                PrimaryButton(title: app.player.isActive ? "Back to the night" : (app.starting ? "Cueing up…" : "Start the night"), wide: true) {
                                    Task { await app.startNight(from: 0) }
                                }
                                Button {
                                    Haptics.tap()
                                    Task { await app.savePlaylist() }
                                } label: {
                                    Image(systemName: night.saved ? "checkmark" : "plus")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(night.saved ? Theme.onColor : Theme.ink)
                                        .frame(width: 56, height: 56)
                                        .background(night.saved ? app.accent : Theme.surface3, in: Circle())
                                }
                                .buttonStyle(PressStyle())
                                .accessibilityLabel(night.saved ? "Saved to Apple Music" : "Save as an Apple Music playlist")
                            }
                            Text(app.planStatus)
                                .font(.text(13, .regular)).foregroundStyle(Theme.ink3)
                                .frame(minHeight: 16)
                                .animation(.none, value: app.planStatus)
                        }

                        Text(planner.djNote(plan, startedAt: night.startedAt))
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(Theme.ink)
                            .lineSpacing(5)
                            .padding(.leading, 16)
                            .overlay(alignment: .leading) {
                                Capsule().fill(app.accent).frame(width: 4)
                            }

                        VStack(alignment: .leading, spacing: 10) {
                            JourneyChart().frame(height: 120)
                            JourneyLabels()
                        }
                        .padding(18)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("It opens with").font(.text(15, .semibold)).foregroundStyle(Theme.ink2).padding(.bottom, 4)
                            ForEach(Array(plan.seq.prefix(3).indices), id: \.self) { k in
                                Button { app.go(.songs) } label: { SongRow(k: k) }
                                    .buttonStyle(PressStyle())
                            }
                            Button {
                                app.go(.songs)
                            } label: {
                                HStack {
                                    Text("See all \(n) songs").font(.text(16, .semibold)).foregroundStyle(Theme.ink)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink3)
                                }
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(PressStyle())
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
}
