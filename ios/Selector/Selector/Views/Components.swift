import SwiftUI
import MusicKit

/// A placeholder cover: the sound's colour with the grooves of a record.
struct RecordPattern: View {
    let color: Color
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color))
            let c = CGPoint(x: size.width * 0.68, y: size.height * 0.34)
            let maxR = hypot(size.width, size.height)
            var r: CGFloat = 1.5
            while r < maxR {
                let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.17)), lineWidth: 1.5)
                r += 8
            }
        }
    }
}

/// Artwork when Apple Music has it, a record otherwise. Size it from outside.
struct Cover: View {
    var url: URL?
    var color: Color
    var radius: CGFloat = 8

    var body: some View {
        Color.clear
            .overlay {
                if let url {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            RecordPattern(color: color)
                        }
                    }
                } else {
                    RecordPattern(color: color)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Four covers in a square.
struct Mosaic: View {
    let tiles: [(url: URL?, color: Color)]
    var radius: CGFloat = 6
    var gap: CGFloat = 3

    var body: some View {
        let t = Array(tiles.prefix(4))
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                Cover(url: t.count > 0 ? t[0].url : nil, color: t.count > 0 ? t[0].color : Theme.surface3, radius: radius)
                Cover(url: t.count > 1 ? t[1].url : nil, color: t.count > 1 ? t[1].color : Theme.surface3, radius: radius)
            }
            HStack(spacing: gap) {
                Cover(url: t.count > 2 ? t[2].url : nil, color: t.count > 2 ? t[2].color : Theme.surface3, radius: radius)
                Cover(url: t.count > 3 ? t[3].url : nil, color: t.count > 3 ? t[3].color : Theme.surface3, radius: radius)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

extension AppState {
    /// Artwork for position `k` of the night, if Apple Music had it.
    func coverURL(_ k: Int, size: Int = 300) -> URL? {
        night?.song(at: k)?.artwork?.url(width: size, height: size)
    }

    /// Placeholder colour for a catalog track: its sound, shaded a little by its id.
    func coverColor(_ j: Int) -> Color {
        guard let night, let planner, j >= 0, j < planner.cat.count else { return Theme.surface3 }
        let key = planner.vibeKey(of: j, in: night.plan)
        let shades: [Double] = [0, -14, 12]
        return Color.shade(Vibes.hex(key), shades[(j * 37) % 3])
    }

    func trackName(_ j: Int) -> String { planner?.cat.t.n[j] ?? "" }
    func trackArtists(_ j: Int) -> String { planner?.cat.t.ar[j] ?? "" }
    func trackArtist(_ j: Int) -> String { Catalog.firstArtist(trackArtists(j)) }
}

/// One song of the night, as a row.
struct SongRow: View {
    @Environment(AppState.self) private var app
    let k: Int
    var showTime = true
    var more = false

    var body: some View {
        if let night = app.night, k < night.plan.seq.count {
            let j = night.plan.seq[k]
            let now = app.player.isActive && app.player.idx == k
            let played = app.player.isActive && k < app.player.idx
            let state = night.am[k]
            HStack(spacing: 12) {
                Cover(url: app.coverURL(k, size: 200), color: app.coverColor(j), radius: 8)
                    .frame(width: 48, height: 48)
                    .opacity(played ? 0.45 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.trackName(j))
                        .font(.text(15, .bold))
                        .foregroundStyle(now ? Theme.accent : (played ? Theme.ink3 : Theme.ink))
                        .lineLimit(1)
                    HStack(spacing: 0) {
                        Text(night.plan.seq.indices.contains(k) ? app.trackArtists(j).components(separatedBy: ", ").prefix(2).joined(separator: ", ") : "")
                            .lineLimit(1)
                        if state.isMissing {
                            Text(" · not on Apple Music").foregroundStyle(Theme.ink3)
                        } else if night.replaced.contains(k) {
                            Text(" · close match").foregroundStyle(Theme.ink3)
                        }
                    }
                    .font(.text(13))
                    .foregroundStyle(played ? Theme.ink3 : Theme.ink2)
                }
                Spacer(minLength: 8)
                if showTime {
                    Text(Fmt.clock(app.clock(at: k)))
                        .font(.text(12, .bold))
                        .foregroundStyle(Theme.ink3)
                        .monospacedDigit()
                }
                if more {
                    Image(systemName: "ellipsis").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink3)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
    }
}

/// "BASS DROP" between two rows.
struct TransitionLabel: View {
    let word: String
    var body: some View {
        let hot = ["Bass drop", "Beat switch", "Speed up"].contains(word)
        HStack(spacing: 10) {
            Rectangle().fill(Theme.hair).frame(height: 1)
            Text(word.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(hot ? Theme.accent : Theme.ink3)
                .fixedSize()
            Rectangle().fill(Theme.hair).frame(height: 1)
        }
        .padding(.vertical, 2)
    }
}

/// The energy of the night as a line, with the peak marked.
struct JourneyChart: View {
    @Environment(AppState.self) private var app

    var body: some View {
        GeometryReader { geo in
            if let night = app.night, let planner = app.planner, night.plan.seq.count > 1 {
                let plan = night.plan
                let st = planner.startTimes(plan), tot = max(1, planner.totalSeconds(plan))
                let sm = planner.smoothedEnergy(plan)
                let lo = (sm.min() ?? 0) - 0.04, hi = (sm.max() ?? 1) + 0.04
                let W = geo.size.width, H = geo.size.height
                let pts: [CGPoint] = plan.seq.indices.map { k in
                    let x = 12 + (W - 24) * (st[k] + Double(planner.cat.t.dur[plan.seq[k]]) / 2) / tot
                    let y = 6 + (H - 12) * (1 - (sm[k] - lo) / max(0.001, hi - lo))
                    return CGPoint(x: x, y: y)
                }
                let line = JourneyChart.curve(pts)
                let peakIndex: Int = {
                    guard let peak = planner.phases(plan).first(where: { $0.key == "peak" }) else { return 0 }
                    var best = peak.from, be = -1.0
                    for k in peak.from..<min(peak.to, sm.count) where sm[k] > be { be = sm[k]; best = k }
                    return best
                }()
                let nowX: CGFloat? = app.player.isActive && app.player.idx >= 0 && app.player.idx < pts.count ? pts[app.player.idx].x : nil
                let area = JourneyChart.area(line, from: pts[0].x, to: pts[pts.count - 1].x, floor: H + 4)
                ZStack {
                    area.fill(LinearGradient(colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    line.stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    if let nowX {
                        Path { p in p.move(to: CGPoint(x: nowX, y: 0)); p.addLine(to: CGPoint(x: nowX, y: H)) }
                            .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    Circle().fill(Theme.accent).frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Theme.surface, lineWidth: 2))
                        .position(pts[peakIndex])
                }
            }
        }
    }

    static func area(_ line: Path, from x0: CGFloat, to x1: CGFloat, floor: CGFloat) -> Path {
        var a = line
        a.addLine(to: CGPoint(x: x1, y: floor))
        a.addLine(to: CGPoint(x: x0, y: floor))
        a.closeSubpath()
        return a
    }

    /// Catmull-Rom through the points, as cubic Béziers.
    static func curve(_ p: [CGPoint]) -> Path {
        var path = Path()
        guard let first = p.first else { return path }
        path.move(to: first)
        guard p.count > 1 else { return path }
        for i in 0..<(p.count - 1) {
            let p0 = p[max(i - 1, 0)], p1 = p[i], p2 = p[i + 1], p3 = p[min(i + 2, p.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}

/// A list option with a check mark.
struct OptionRow: View {
    let title: String
    let subtitle: String
    var on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.text(16, .bold)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.text(13)).foregroundStyle(Theme.ink2)
                }
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 26, height: 26)
                    .background(Theme.accent, in: Circle())
                    .opacity(on ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(on ? Theme.surface3 : Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// A list option with a switch.
struct ToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var on: Bool
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.text(16, .bold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.text(13)).foregroundStyle(Theme.ink2).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: $on).labelsHidden().tint(Theme.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Sheet chrome: title, then whatever the sheet holds.
struct SheetFrame<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.display(22)).foregroundStyle(Theme.ink)
                if let subtitle { Text(subtitle).font(.text(14)).foregroundStyle(Theme.ink2) }
            }
            .padding(.top, 18)
            content
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
    }
}
