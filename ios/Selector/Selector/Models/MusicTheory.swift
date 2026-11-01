import Foundation

/// Camelot wheel position. "A" is minor, "B" is major.
struct Camelot: Equatable {
    let number: Int
    let major: Bool

    init(key: Int, mode: Int) {
        let kk = mode == 1 ? key : (key + 3) % 12
        number = ((kk * 7) % 12 + 7) % 12 + 1
        major = (mode == 1)
    }

    var text: String { "\(number)\(major ? "B" : "A")" }
    /// Hue in degrees, for the key chip colour.
    var hue: Double { Double(number - 1) * 30 }
}

enum KeyRelation: String {
    case same, relative, adjacent, energy2, diag, clash

    static func between(_ a: Camelot, _ b: Camelot) -> KeyRelation {
        var d = abs(a.number - b.number)
        d = min(d, 12 - d)
        let sameLetter = a.major == b.major
        if d == 0 && sameLetter { return .same }
        if d == 0 { return .relative }
        if d == 1 && sameLetter { return .adjacent }
        if d == 2 && sameLetter { return .energy2 }
        if d == 1 { return .diag }
        return .clash
    }

    var isHarmonic: Bool {
        switch self {
        case .same, .relative, .adjacent, .energy2: return true
        case .diag, .clash: return false
        }
    }

    var text: String {
        switch self {
        case .same: return "same key"
        case .relative: return "relative major/minor"
        case .adjacent: return "±1, harmonic"
        case .energy2: return "+2, energy boost"
        case .diag: return "diagonal move"
        case .clash: return "key clash"
        }
    }
}

/// Percent tempo gap after folding half/double time.
func tempoGapPercent(_ a: Double, _ b: Double) -> Double {
    guard a > 0, b > 0 else { return 50 }
    var best = Double.infinity
    for f in [0.5, 1.0, 2.0] {
        let v = abs(log2(b * f / a))
        if v < best { best = v }
    }
    return (pow(2, best) - 1) * 100
}

/// String normalisation shared by the planner and the Apple Music matcher.
enum Normalizer {
    static func artist(_ s: String) -> String {
        var x = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil).lowercased()
        if x.hasPrefix("the ") { x.removeFirst(4) }
        var scalars = String.UnicodeScalarView()
        for u in x.unicodeScalars where CharacterSet.alphanumerics.contains(u) { scalars.append(u) }
        return String(scalars)
    }

    /// Title without parentheticals or " - Remaster" tails.
    static func title(_ s: String) -> String {
        var x = s.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: " ", options: .regularExpression)
        if let r = x.range(of: #"\s+-\s+"#, options: .regularExpression) { x = String(x[..<r.lowerBound]) }
        return artist(x)
    }

    /// Key used to stop the same song appearing twice in a set (different editions).
    static func titleKey(_ s: String) -> String {
        var head = s
        if let r = s.range(of: #"\s[-(\[]"#, options: .regularExpression) { head = String(s[..<r.lowerBound]) }
        return String(artist(head).prefix(24))
    }

    /// A clean search term for the Apple Music catalog.
    static func searchTitle(_ s: String) -> String {
        var x = s
        x = x.replacingOccurrences(of: #"\(From\s+"[^"]*"\)"#, with: " ", options: [.regularExpression, .caseInsensitive])
        x = x.replacingOccurrences(of: #"\((feat|ft|with)\.?[^)]*\)"#, with: " ", options: [.regularExpression, .caseInsensitive])
        x = x.replacingOccurrences(of: #"\s+-\s+(From|Remaster|Remastered|Original|Radio|Extended|Single|Spotify).*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        x = x.replacingOccurrences(of: #"[\(\)\[\]"]"#, with: " ", options: .regularExpression)
        x = x.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return x.trimmingCharacters(in: .whitespaces)
    }
}

/// Text formatting shared by every screen.
enum Fmt {
    /// 0:00 or 1:02:03
    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, x = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, x) }
        return String(format: "%d:%02d", m, x)
    }

    /// "45 min", "2 h", "2 h 15 min"
    static func length(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        if m < 60 { return "\(m) min" }
        let h = m / 60, r = m % 60
        return r > 0 ? "\(h) h \(r) min" : "\(h) h"
    }

    /// "2 hours", "1 hour", "90 min"
    static func lengthWords(minutes: Int) -> String {
        if minutes % 60 == 0 { let h = minutes / 60; return h == 1 ? "1 hour" : "\(h) hours" }
        return length(Double(minutes * 60))
    }

    /// "6:35 PM" in the user's locale
    static func clock(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated)).minute(.twoDigits))
    }

    static func weekday(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().weekday(.wide))
    }

    /// Now, rounded up to the next five minutes: when a night planned now would start.
    static func roundedNow() -> Date {
        let now = Date()
        let secs = now.timeIntervalSince1970
        return Date(timeIntervalSince1970: (secs / 300).rounded(.up) * 300)
    }
}
