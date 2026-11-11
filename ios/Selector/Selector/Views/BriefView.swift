import SwiftUI

/// The brief: occasion, length, crowd, sounds. Then "Plan the night".
struct BriefView: View {
    @Environment(AppState.self) private var app

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            TopBar("", onBack: { app.back() }) {
                Button("Reset") { app.applyOccasion("sangeet") }
                    .font(.text(16, .semibold)).foregroundStyle(Theme.ink2)
                    .frame(height: 44).padding(.trailing, 10)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Poster(text: "What's the night?", size: 40).padding(.bottom, 6)
                    rowCard(label: "Occasion", value: Occasion.named(app.settings.occasion)?.label ?? "Custom", detail: nil) { app.sheet = .occasion }
                    rowCard(label: "Length", value: Fmt.lengthWords(minutes: app.settings.minutes), detail: "ends \(app.endsAt(minutes: app.settings.minutes))") { app.sheet = .length }
                    rowCard(label: "Crowd", value: app.settings.clean ? "Family-friendly" : "Anything goes", detail: app.settings.fam >= 0.65 ? "songs we know" : "surprise us") { app.sheet = .crowd }

                    HStack(alignment: .lastTextBaseline) {
                        Poster(text: "Sounds", size: 28)
                        Spacer()
                        Text("Star up to two headliners").font(.text(13, .regular)).foregroundStyle(Theme.ink3)
                    }
                    .padding(.top, 16)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Vibes.order, id: \.self) { key in
                            VibeTile(key: key)
                        }
                    }

                    tasteCard
                        .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 100)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Plan the night", icon: nil, wide: true) {
                if app.planNight() { app.go(.plan) }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        }
    }

    private func rowCard(label: String, value: String, detail: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label).font(.text(13, .semibold)).foregroundStyle(Theme.ink3)
                    HStack(spacing: 6) {
                        Text(value).font(.text(18, .semibold)).foregroundStyle(Theme.ink)
                        if let detail { Text(detail).font(.text(15, .regular)).foregroundStyle(Theme.ink2) }
                    }
                    .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var tasteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Poster(text: "Your taste", size: 24)
            Text(app.taste.map { t in
                var s = "\(t.source). Your DJ knows \(t.matched.count) of your artists"
                if !t.matched.isEmpty { s += ": " + t.matched.prefix(5).joined(separator: ", ") }
                if t.matched.count > 5 { s += " and \(t.matched.count - 5) more" }
                return s + "."
            } ?? "Not loaded yet. Your DJ leans on the sounds you pick and what's popular.")
                .font(.text(14)).foregroundStyle(Theme.ink2)
            HStack(spacing: 8) {
                Chip(label: "Use my Apple Music") { Task { await app.tasteFromLibrary() } }
                Chip(label: "Type artists") { app.sheet = .taste }
                if app.taste != nil { Chip(label: "Clear") { app.clearTaste() } }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// One sound: tap to include it, star it to make it the headliner.
struct VibeTile: View {
    @Environment(AppState.self) private var app
    let key: String

    var body: some View {
        let style = Vibes.style(key)
        let w = app.settings.weights[key] ?? 0
        let on = w > 0, head = w >= 3
        let fill = Color(hex: style.hex)
        let textColor: Color = on ? Theme.onColor : Theme.ink
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(on ? fill : Theme.surface)
            Button { Haptics.tap(); app.toggleVibe(key) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Spacer(minLength: 0)
                    Text(style.label).font(.system(size: 17, weight: .bold)).foregroundStyle(textColor).lineLimit(2)
                    Text(key == "mideast" ? "mostly Turkish for now" : "\((app.planner?.vibe(key)?.n ?? 0).formatted()) songs")
                        .font(.text(12, .regular)).foregroundStyle(textColor.opacity(on ? 0.7 : 0.5))
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
                .padding(.top, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack {
                Circle().fill(fill).frame(width: 10, height: 10).opacity(on ? 0 : 1)
                Spacer()
                if on {
                    Button { Haptics.tap(); app.starVibe(key) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: head ? "star.fill" : "star").font(.system(size: 11, weight: .heavy))
                            if head { Text("Headliner").font(.system(size: 11, weight: .heavy)) }
                        }
                        .foregroundStyle(head ? Theme.ink : textColor)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(head ? Theme.onColor : Color.black.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .frame(height: 96)
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

// MARK: - Sheets

struct OccasionSheet: View {
    @Environment(AppState.self) private var app
    var body: some View {
        SheetFrame(title: "What's tonight?") {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Occasion.all) { o in
                        OptionRow(title: o.label, subtitle: o.desc, on: app.settings.occasion == o.key) {
                            app.applyOccasion(o.key)
                            app.sheet = nil
                        }
                    }
                }
            }
        }
    }
}

struct LengthSheet: View {
    @Environment(AppState.self) private var app
    var body: some View {
        SheetFrame(title: "How long?") {
            VStack(spacing: 8) {
                ForEach(Occasion.lengths, id: \.self) { m in
                    OptionRow(title: Fmt.length(Double(m * 60)), subtitle: "ends around \(app.endsAt(minutes: m))", on: app.settings.minutes == m) {
                        app.setMinutes(m)
                        app.sheet = nil
                    }
                }
            }
        }
    }
}

struct CrowdSheet: View {
    @Environment(AppState.self) private var app
    var body: some View {
        SheetFrame(title: "Who's in the room?") {
            VStack(spacing: 8) {
                ToggleRow(title: "Family-friendly", subtitle: "No explicit versions",
                          on: Binding(get: { app.settings.clean }, set: { app.setClean($0) }))
                OptionRow(title: "Songs we know", subtitle: "The hits, the sing-alongs", on: app.settings.fam >= 0.65) { app.setFamiliar(true) }
                OptionRow(title: "Surprise us", subtitle: "Deeper cuts, fewer obvious picks", on: app.settings.fam < 0.65) { app.setFamiliar(false) }
                if let t = app.taste {
                    ToggleRow(title: "Lean on my taste", subtitle: t.matched.prefix(3).joined(separator: ", "),
                              on: Binding(get: { app.settings.useTaste }, set: { app.setUseTaste($0) }))
                }
            }
        }
    }
}

struct TasteSheet: View {
    @Environment(AppState.self) private var app
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        SheetFrame(title: "Artists you love", subtitle: "A few names, separated by commas. Your DJ also plays the artists DJs put next to them.") {
            TextField("Diljit Dosanjh, Bad Bunny, Fred again..", text: $text, axis: .vertical)
                .font(.text(16))
                .foregroundStyle(Theme.ink)
                .lineLimit(3...5)
                .padding(14)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .focused($focused)
            PrimaryButton(title: "Use these", icon: nil, wide: true) { app.tasteFromText(text) }
        }
        .onAppear {
            if let t = app.taste, t.source.hasPrefix("You typed") { text = t.matched.joined(separator: ", ") }
            focused = true
        }
    }
}
