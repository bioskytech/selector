import SwiftUI

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
                ctx.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.13)), lineWidth: 1.5)
                r += 8
            }
        }
    }
}

/// A record, seen from above. The label takes a colour.
struct Vinyl: View {
    var label: Color
    var body: some View {
        Canvas { ctx, size in
            let d = min(size.width, size.height)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func circle(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
            ctx.fill(circle(d / 2), with: .color(Color(hex: "#120A12")))
            var r = d * 0.2
            while r < d / 2 - 2 {
                ctx.stroke(circle(r), with: .color(.white.opacity(0.07)), lineWidth: 1)
                r += d * 0.022
            }
            ctx.fill(circle(d * 0.17), with: .color(label))
            ctx.fill(circle(d * 0.022), with: .color(Color(hex: "#120A12")))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Artwork when it has been found, a record sleeve otherwise. Size it from outside.
struct Cover: View {
    var url: URL?
    var color: Color
    var radius: CGFloat = 8

    var body: some View {
        Color.clear
            .overlay {
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
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

/// Sleeves pulled from the crate and fanned out.
struct Fan: View {
    let tiles: [(url: URL?, color: Color)]
    var size: CGFloat = 150

    var body: some View {
        let t = Array(tiles.prefix(4))
        let angles: [Double] = [-13, -4, 5, 14]
        let offsets: [CGFloat] = [-1.5, -0.5, 0.5, 1.5]
        ZStack {
            ForEach(Array(t.indices), id: \.self) { i in
                Cover(url: t[i].url, color: t[i].color, radius: 10)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.45), radius: 12, x: -4, y: 8)
                    .rotationEffect(.degrees(angles[i]))
                    .offset(x: offsets[i] * size * 0.36, y: abs(offsets[i]) * size * 0.06)
            }
        }
        .frame(height: size * 1.22)
        .frame(maxWidth: .infinity)
    }
}

extension AppState {
    /// Artwork for position `k` of the night, once it has been found.
    func coverURL(_ k: Int, size: Int = 300) -> URL? {
        night?.track(at: k)?.artworkURL(size)
    }

    /// Placeholder colour for a catalog track: its sound, shaded a little by its id.
    func coverColor(_ j: Int) -> Color {
        guard let night, let planner, j >= 0, j < planner.cat.count else { return Theme.surface3 }
        let key = planner.vibeKey(of: j, in: night.plan)
        let shades: [Double] = [0, -14, 10]
        return Color.shade(Vibes.hex(key), shades[(j * 37) % 3])
    }

    func trackName(_ j: Int) -> String { planner?.cat.t.n[j] ?? "" }
    func trackArtists(_ j: Int) -> String { planner?.cat.t.ar[j] ?? "" }
    func trackArtist(_ j: Int) -> String { Catalog.firstArtist(trackArtists(j)) }

    /// Four covers that stand for the night: the open, the build, the peak, the close.
    func nightTiles(size: Int = 400) -> [(url: URL?, color: Color)] {
        guard let night else { return [] }
        let n = night.plan.seq.count
        guard n > 0 else { return [] }
        return [0, n / 3, 2 * n / 3, n - 1].map { k in
            let kk = min(max(k, 0), n - 1)
            return (coverURL(kk, size: size), coverColor(night.plan.seq[kk]))
        }
    }
}

/// One song of the night, as a row.
struct SongRow: View {
    @Environment(AppState.self) private var app
    let k: Int
    var showTime = true

    var body: some View {
        if let night = app.night, k < night.plan.seq.count, k < night.am.count {
            let j = night.plan.seq[k]
            let now = app.player.isActive && app.player.idx == k
            let played = app.player.isActive && k < app.player.idx
            HStack(spacing: 13) {
                Cover(url: app.coverURL(k, size: 200), color: app.coverColor(j), radius: 8)
                    .frame(width: 50, height: 50)
                    .opacity(played ? 0.4 : 1)
                    .overlay {
                        if now { NowBars(color: app.accent).frame(width: 18, height: 16).padding(17).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous)) }
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.trackName(j))
                        .font(.text(16, .semibold))
                        .foregroundStyle(now ? app.accent : (played ? Theme.ink3 : Theme.ink))
                        .lineLimit(1)
                    Text(app.trackArtists(j).components(separatedBy: ", ").prefix(2).joined(separator: ", ") + (night.replaced.contains(k) ? "  ·  close match" : ""))
                        .font(.text(14, .regular))
                        .foregroundStyle(played ? Theme.ink3 : Theme.ink2)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if showTime {
                    Text(Fmt.clock(app.clock(at: k)))
                        .font(.text(13, .regular))
                        .foregroundStyle(Theme.ink3)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
    }
}

/// Three bars that move while a song plays.
struct NowBars: View {
    var color: Color
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule().fill(color)
                        .frame(maxHeight: .infinity)
                        .scaleEffect(y: 0.35 + 0.65 * abs(sin(t * (2.1 + Double(i) * 0.7) + Double(i))), anchor: .bottom)
                }
            }
        }
    }
}

/// How one song hands over to the next, when it's more than a smooth blend.
struct TransitionLabel: View {
    @Environment(AppState.self) private var app
    let word: String
    var body: some View {
        let hot = ["Bass drop", "Beat switch", "Speed up"].contains(word)
        HStack(spacing: 10) {
            Capsule().fill(hot ? app.accent : Theme.ink3).frame(width: 2, height: 16).padding(.leading, 24)
            Text(word)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hot ? app.accent : Theme.ink3)
            Spacer()
        }
        .padding(.leading, 0)
        .frame(height: 18)
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
                    let x = 6 + (W - 12) * (st[k] + Double(planner.cat.t.dur[plan.seq[k]]) / 2) / tot
                    let y = 8 + (H - 16) * (1 - (sm[k] - lo) / max(0.001, hi - lo))
                    return CGPoint(x: x, y: y)
                }
                let line = JourneyChart.curve(pts)
                let peakIndex: Int = {
                    guard let peak = planner.phases(plan).first(where: { $0.key == "peak" }) else { return 0 }
                    var best = min(peak.from, sm.count - 1), be = -1.0
                    for k in peak.from..<min(peak.to, sm.count) where sm[k] > be { be = sm[k]; best = k }
                    return best
                }()
                let nowIndex: Int? = app.player.isActive && app.player.idx >= 0 && app.player.idx < pts.count ? app.player.idx : nil
                let area = JourneyChart.area(line, from: pts[0].x, to: pts[pts.count - 1].x, floor: H)
                ZStack {
                    area.fill(LinearGradient(colors: [app.accent.opacity(0.42), app.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                    line.stroke(app.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    if let nowIndex {
                        Path { p in p.move(to: CGPoint(x: pts[nowIndex].x, y: 0)); p.addLine(to: CGPoint(x: pts[nowIndex].x, y: H)) }
                            .stroke(Theme.ink.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Circle().fill(Theme.ink).frame(width: 11, height: 11).position(pts[nowIndex])
                    }
                    Circle().fill(app.accent).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Theme.surface, lineWidth: 3))
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

/// The phases of the night under the chart, with the peak called out.
struct JourneyLabels: View {
    @Environment(AppState.self) private var app
    var body: some View {
        if let night = app.night, let planner = app.planner {
            let phases = planner.phases(night.plan)
            HStack(spacing: 0) {
                ForEach(phases) { p in
                    Text(p.key == "peak" ? "Peak \(Fmt.clock(app.clock(afterSeconds: p.start)))" : p.label)
                        .font(.system(size: 13, weight: p.key == "peak" ? .bold : .medium))
                        .foregroundStyle(p.key == "peak" ? app.accent : Theme.ink3)
                        .lineLimit(1)
                        .fixedSize()
                    if p.key != phases.last?.key { Spacer(minLength: 4) }
                }
            }
        }
    }
}

/// A list option with a check mark.
struct OptionRow: View {
    @Environment(AppState.self) private var app
    let title: String
    let subtitle: String
    var on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.text(17, .semibold)).foregroundStyle(Theme.ink)
                    Text(subtitle).font(.text(14, .regular)).foregroundStyle(Theme.ink2).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.onColor)
                    .frame(width: 26, height: 26)
                    .background(app.accent, in: Circle())
                    .opacity(on ? 1 : 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(on ? Theme.surface3 : Theme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

/// A list option with a switch.
struct ToggleRow: View {
    @Environment(AppState.self) private var app
    let title: String
    let subtitle: String
    @Binding var on: Bool
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.text(17, .semibold)).foregroundStyle(Theme.ink)
                Text(subtitle).font(.text(14, .regular)).foregroundStyle(Theme.ink2).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: $on).labelsHidden().tint(app.accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Sheet chrome: a poster title, then whatever the sheet holds.
struct SheetFrame<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Poster(text: title, size: 30)
                if let subtitle {
                    Text(subtitle).font(.text(15, .regular)).foregroundStyle(Theme.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 26)
            content
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
    }
}
