import SwiftUI

/// Design tokens. Dark ground, coral accent, artwork-forward.
enum Theme {
    static let bg = Color(hex: "#0A0A0D")
    static let surface = Color(hex: "#15151A")
    static let surface2 = Color(hex: "#1D1D24")
    static let surface3 = Color(hex: "#23232B")
    static let ink = Color.white
    static let ink2 = Color(hex: "#A3A3AD")
    static let ink3 = Color(hex: "#6E6E78")
    static let accent = Color(hex: "#FF6A3D")
    static let accentInk = Color(hex: "#14080A")
    static let good = Color(hex: "#3DDC84")
    static let hair = Color.white.opacity(0.06)
    static let hair2 = Color.white.opacity(0.14)

    static func vibe(_ key: String) -> Color { Color(hex: Vibes.hex(key)) }
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

    /// The playing screen's tint: the artwork colour pulled down into the dark.
    static func tint(from cg: CGColor?) -> Color {
        guard let cg, let comps = cg.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil)?.components, comps.count >= 3 else {
            return Color(red: 26 / 255, green: 15 / 255, blue: 18 / 255)
        }
        let f = 0.28
        return Color(red: Double(comps[0]) * f + 10 / 255, green: Double(comps[1]) * f + 10 / 255, blue: Double(comps[2]) * f + 13 / 255)
    }

    static func tint(fromHex hex: String) -> Color {
        var h = hex
        if h.hasPrefix("#") { h.removeFirst() }
        var n: UInt64 = 0
        Scanner(string: h).scanHexInt64(&n)
        let f = 0.28
        return Color(red: Double((n >> 16) & 0xFF) / 255 * f + 10 / 255, green: Double((n >> 8) & 0xFF) / 255 * f + 10 / 255, blue: Double(n & 0xFF) / 255 * f + 13 / 255)
    }
}

extension Font {
    static func display(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy) }
    static func heading(_ size: CGFloat) -> Font { .system(size: size, weight: .bold) }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { .system(size: size, weight: weight) }
    static func small(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .bold) }
}

/// Small uppercase label: "READY FOR YOU", "UP NEXT · 3:21".
struct Kicker: View {
    let text: String
    var color: Color = Theme.ink2
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .heavy))
            .tracking(1.4)
            .foregroundStyle(color)
    }
}

/// The big coral pill button.
struct PrimaryButton: View {
    let title: String
    var icon: String? = "play.fill"
    var wide = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon { Image(systemName: icon).font(.system(size: 15, weight: .heavy)) }
                Text(title)
            }
            .font(.system(size: 16, weight: .heavy))
            .foregroundStyle(Theme.accentInk)
            .frame(maxWidth: wide ? .infinity : nil)
            .padding(.horizontal, 22)
            .frame(height: 54)
            .background(Theme.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Outlined pill button: "Change", "New take".
struct GhostButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 18)
                .frame(height: 46)
                .overlay(Capsule().stroke(Theme.hair2, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// A chip: steering requests, phases.
struct Chip: View {
    let label: String
    var icon: String? = nil
    var on = false
    var light = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12, weight: .heavy)) }
                Text(label).lineLimit(1)
            }
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(on ? Theme.accentInk : Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(on ? Theme.accent : (light ? Color.white.opacity(0.14) : Theme.surface3), in: Capsule())
        }
        .buttonStyle(.plain)
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
                .background(filled ? Theme.surface3 : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
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
            Text(title).font(.system(size: 17, weight: .heavy)).foregroundStyle(Theme.ink).lineLimit(1)
            HStack {
                if let onBack {
                    IconButton(system: "chevron.left", size: 20, action: onBack)
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
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(Theme.surface3, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            .padding(.horizontal, 32)
    }
}
