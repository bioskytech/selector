import SwiftUI
import CoreText
import UIKit

/// The look: a plum night, ivory type, and one loud colour that belongs to tonight's lead sound.
/// Titles are set like gig posters (Anton, capitals); everything you read at length is the system face.
enum Theme {
    static let bg = Color(hex: "#140B1F")
    static let surface = Color(hex: "#20132E")
    static let surface2 = Color(hex: "#2B1A3C")
    static let surface3 = Color(hex: "#3A2550")
    static let ink = Color(hex: "#FFF3E4")
    static let ink2 = Color(hex: "#BBAACB")
    static let ink3 = Color(hex: "#806F92")
    static let marigold = "#FFB300"
    /// Type that sits on a colour field.
    static let onColor = Color(hex: "#1A0B16")
    static let good = Color(hex: "#5BD66B")
    static let hair = Color.white.opacity(0.07)
    static let hair2 = Color.white.opacity(0.16)

    static func vibe(_ key: String) -> Color { Color(hex: Vibes.hex(key)) }

    /// Makes the bundled display face available. Safe to call more than once.
    static func registerFonts() {
        guard let url = Bundle.main.url(forResource: "Anton-Regular", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thud() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

extension AppState {
    /// The sound that leads tonight: its colour is the app's accent.
    var leadVibe: String {
        if let night { return night.plan.soundsByWeight.first ?? "punjabi" }
        return settings.sounds.first ?? "punjabi"
    }
    var accentHex: String { Vibes.all[leadVibe]?.hex ?? Theme.marigold }
    var accent: Color { Color(hex: accentHex) }
    /// A second colour for gradients: the next sound of the night, or a warmer shade of the first.
    var accent2: Color {
        let sounds = night?.plan.soundsByWeight ?? settings.sounds
        if sounds.count > 1 { return Color(hex: Vibes.hex(sounds[1])) }
        return Color.shade(accentHex, -22)
    }
}

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        var n: UInt64 = 0
        Scanner(string: h).scanHexInt64(&n)
        let r = Double((n >> 16) & 0xFF) / 255, g = Double((n >> 8) & 0xFF) / 255, b = Double(n & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Lighten (positive) or darken (negative) by a percentage.
    static func shade(_ hex: String, _ pct: Double) -> Color {
        var h = hex
        if h.hasPrefix("#") { h.removeFirst() }
        var n: UInt64 = 0
        Scanner(string: h).scanHexInt64(&n)
        let f = 1 + pct / 100
        func c(_ v: UInt64) -> Double { min(max(Double(v) * f, 0), 255) / 255 }
        return Color(red: c((n >> 16) & 0xFF), green: c((n >> 8) & 0xFF), blue: c(n & 0xFF))
    }
}

extension Font {
    /// Poster type. Use with capitals.
    static func poster(_ size: CGFloat) -> Font { .custom("Anton-Regular", fixedSize: size) }
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font { .system(size: size, weight: weight) }
    static func small(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .semibold) }
}

/// A poster headline: Anton, capitals, lines stacked tight the way a gig poster sets them.
struct Poster: View {
    let text: String
    var size: CGFloat = 40
    var color: Color = Theme.ink
    var lines: Int = 3
    var body: some View {
        let words = text.uppercased().split(separator: " ").map(String.init)
        PosterLines(size: size) {
            ForEach(Array(words.enumerated()), id: \.offset) { _, w in
                Text(w).font(.poster(size)).foregroundStyle(color).lineLimit(1).fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Wraps words into lines with the leading Anton wants: capitals nearly touching.
/// (Text can't set leading tighter than the font's own, so the words are placed by hand.)
struct PosterLines: Layout {
    var size: CGFloat
    private var leading: CGFloat { size * 0.99 }
    private var gap: CGFloat { size * 0.24 }
    private var capTop: CGFloat { size * 0.30 }      // empty space above the capitals in the font's box

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(Int, CGFloat)]] {
        var out: [[(Int, CGFloat)]] = [[]]
        var x: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let w = s.sizeThatFits(.unspecified).width
            if x + w > width && x > 0 { out.append([]); x = 0 }
            out[out.count - 1].append((i, x))
            x += w + gap
        }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        let r = rows(subviews, width: width)
        var widest: CGFloat = 0
        for row in r { if let last = row.last { widest = max(widest, last.1 + subviews[last.0].sizeThatFits(.unspecified).width) } }
        return CGSize(width: min(width, widest), height: CGFloat(max(r.count, 1) - 1) * leading + size * 0.90)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (line, row) in rows(subviews, width: bounds.width).enumerated() {
            for (i, x) in row {
                subviews[i].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + CGFloat(line) * leading - capTop), proposal: .unspecified)
            }
        }
    }
}

/// A quiet label above or beside content.
struct Kicker: View {
    let text: String
    var color: Color = Theme.ink2
    var body: some View {
        Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(color)
    }
}

/// The main action: a pill in tonight's colour.
struct PrimaryButton: View {
    @Environment(AppState.self) private var app
    let title: String
    var icon: String? = "play.fill"
    var wide = false
    var onColor = false          // sitting on a colour field: go dark instead
    let action: () -> Void
    var body: some View {
        Button {
            Haptics.thud()
            action()
        } label: {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .heavy)) }
                Text(title)
            }
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(onColor ? Theme.ink : Theme.onColor)
            .frame(maxWidth: wide ? .infinity : nil)
            .padding(.horizontal, 24)
            .frame(height: 56)
            .background(onColor ? Theme.onColor : app.accent, in: Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// Buttons sink a little when pressed.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A secondary action.
struct GhostButton: View {
    let title: String
    var onColor = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(onColor ? Theme.onColor : Theme.ink)
                .padding(.horizontal, 20)
                .frame(height: 56)
                .background((onColor ? Color.black.opacity(0.14) : Theme.surface3), in: Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// A chip: steering requests, phases.
struct Chip: View {
    @Environment(AppState.self) private var app
    let label: String
    var icon: String? = nil
    var on = false
    var light = false
    let action: () -> Void
    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .heavy)) }
                Text(label).lineLimit(1)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(on ? Theme.onColor : Theme.ink)
            .padding(.horizontal, 15)
            .frame(height: 40)
            .background(on ? app.accent : (light ? Color.white.opacity(0.13) : Theme.surface3), in: Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

/// Round icon button, 44pt.
struct IconButton: View {
    let system: String
    var size: CGFloat = 22
    var filled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 44, height: 44)
                .background(filled ? Color.white.opacity(0.12) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
    }
}

/// Top bar with a back chevron and a centred title.
struct TopBar<Trailing: View>: View {
    let title: String
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, onBack: (() -> Void)? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        ZStack {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
            HStack {
                if let onBack {
                    IconButton(system: "chevron.left", size: 19, action: onBack)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
                Spacer()
                trailing
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
    }
}

extension TopBar where Trailing == EmptyView {
    init(_ title: String, onBack: (() -> Void)? = nil) {
        self.init(title, onBack: onBack) { EmptyView() }
    }
}

/// Lays chips out in rows that wrap.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.width && x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

/// A short message that floats up from the bottom.
struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.onColor)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            .padding(.horizontal, 28)
    }
}
