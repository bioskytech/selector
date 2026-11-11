import SwiftUI

/// Every song of the night, by phase. Swipe a row to swap or remove it.
struct SongsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            TopBar("\(app.night?.plan.seq.count ?? 0) songs", onBack: { app.back() })
            if let night = app.night, let planner = app.planner {
                let plan = night.plan
                let phases = planner.phases(plan)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(label: "All", on: app.phaseFilter == "all") { app.phaseFilter = "all" }
                        ForEach(phases) { p in
                            Chip(label: p.label, on: app.phaseFilter == p.key) { app.phaseFilter = p.key }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                }
                List {
                    ForEach(phases) { p in
                        if app.phaseFilter == "all" || app.phaseFilter == p.key {
                            Section {
                                ForEach(p.from..<p.to, id: \.self) { k in
                                    if k < plan.seq.count {
                                        if k > 0, let word = planner.transitionWord(plan.seq[k - 1], plan.seq[k]) {
                                            TransitionLabel(word: word)
                                                .listRowBackground(Theme.bg)
                                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                                .listRowSeparator(.hidden)
                                        }
                                        SongRow(k: k)
                                            .listRowBackground(Theme.bg)
                                            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                            .listRowSeparator(.hidden)
                                            .onTapGesture { Task { await app.playRow(k) } }
                                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                                Button { app.removeAt(k) } label: { Label("Remove", systemImage: "xmark") }
                                                    .tint(Theme.surface3)
                                                Button { app.swapAt(k) } label: { Label("Swap", systemImage: "arrow.left.arrow.right") }
                                                    .tint(app.accent)
                                            }
                                    }
                                }
                            } header: {
                                HStack(alignment: .lastTextBaseline) {
                                    Poster(text: p.label, size: 24)
                                    Spacer()
                                    Text("\(Fmt.clock(app.clock(at: p.from))) to \(Fmt.clock(app.clock(afterSeconds: p.end)))")
                                        .font(.text(13, .regular)).foregroundStyle(Theme.ink3)
                                }
                                .padding(.top, 10)
                                .padding(.bottom, 2)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                            }
                        }
                    }
                    Text("Swipe a song left to swap or remove it.")
                        .font(.text(13, .regular)).foregroundStyle(Theme.ink3)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 12).padding(.bottom, 90)
                        .listRowBackground(Theme.bg).listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)
            } else {
                Spacer()
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if !app.player.isActive && app.night != nil {
                PrimaryButton(title: app.starting ? "Cueing up…" : "Start the night", wide: true) {
                    Task { await app.startNight(from: 0) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 8)
                .background(LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg, Theme.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            }
        }
    }
}
