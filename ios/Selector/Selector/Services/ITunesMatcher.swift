import Foundation

/// Finds songs through Apple's public iTunes lookup: artwork and a 30-second preview,
/// with no sign-in and no Apple Music setup. Used when Apple Music isn't connected.
/// The lookup allows roughly 20 requests a minute, so requests are spaced out.
actor ITunesMatcher {
    private struct Hit: Codable {
        var id: String
        var preview: String?
        var art: String?
        var dur: Double?
    }
    private struct Response: Decodable {
        struct Item: Decodable {
            let trackId: Int?
            let trackName: String?
            let artistName: String?
            let trackTimeMillis: Double?
            let previewUrl: String?
            let artworkUrl100: String?
            let trackExplicitness: String?
        }
        let results: [Item]
    }

    private var cache: [String: Hit?] = [:]
    private var saved: [String: Hit] = [:]
    private var lastRequest = Date.distantPast
    private var spacing: TimeInterval = 1.3
    private let defaultsKey = "selector.itunes.matches.v1"
    private let country: String

    init() {
        country = Locale.current.region?.identifier ?? "US"
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let s = try? JSONDecoder().decode([String: Hit].self, from: data) {
            saved = s
        }
    }

    /// nil = not found. Throws only when the lookup itself is unreachable.
    func find(track j: Int, in cat: Catalog, clean: Bool) async throws -> Track? {
        let t = cat.t
        let key = (clean ? "c:" : "") + t.id[j]
        if let known = saved[key] { return track(known) }
        if let known = cache[key] { return known.map(track) }

        let title = Normalizer.searchTitle(t.n[j])
        let artist = Catalog.firstArtist(t.ar[j])
        let want = Normalizer.title(t.n[j])
        let artistKeys = t.ar[j].components(separatedBy: ", ").map(Normalizer.artist).filter { !$0.isEmpty }

        let items = try await search("\(title) \(artist)")
        var best: Response.Item?
        var bestScore = 0.0
        for s in items {
            guard s.previewUrl != nil, let name = s.trackName else { continue }
            if clean && s.trackExplicitness == "explicit" { continue }
            let tt = Normalizer.title(name)
            var titleScore = 0.0
            if tt == want { titleScore = 1 }
            else if (tt.contains(want) || want.contains(tt)) && min(tt.count, want.count) >= 4 { titleScore = 0.8 }
            let an = Normalizer.artist(s.artistName ?? "")
            let artistScore: Double = artistKeys.contains { an.contains($0) || $0.contains(an) } ? 1 : 0
            let dd = abs((s.trackTimeMillis ?? 0) / 1000 - Double(t.dur[j]))
            let durationScore: Double = dd <= 4 ? 1 : (dd <= 15 ? 0.6 : (dd <= 40 ? 0.2 : 0))
            let score = titleScore * 0.55 + artistScore * 0.35 + durationScore * 0.10
            if score > bestScore { bestScore = score; best = s }
        }
        guard bestScore >= 0.72, let b = best, let id = b.trackId else {
            cache[key] = .some(nil)
            return nil
        }
        let hit = Hit(id: String(id), preview: b.previewUrl, art: b.artworkUrl100, dur: b.trackTimeMillis.map { $0 / 1000 })
        saved[key] = hit
        if let data = try? JSONEncoder().encode(saved) { UserDefaults.standard.set(data, forKey: defaultsKey) }
        return track(hit)
    }

    private func track(_ h: Hit) -> Track {
        Track(id: h.id, previewURL: h.preview.flatMap { URL(string: $0) }, duration: h.dur, artworkURL100: h.art)
    }

    private func search(_ term: String) async throws -> [Response.Item] {
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term", value: term), URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "8"), URLQueryItem(name: "country", value: country),
        ]
        guard let url = comps.url else { return [] }
        var lastError: Error = URLError(.badServerResponse)
        for attempt in 0..<3 {
            // Reserve the next slot before sleeping, so calls that overlap still stay spaced out.
            let slot = max(Date(), lastRequest.addingTimeInterval(spacing))
            lastRequest = slot
            let wait = slot.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 403 || code == 429 {
                    // Asked too fast: slow down and wait it out.
                    spacing = min(spacing + 1, 4)
                    try? await Task.sleep(nanoseconds: UInt64(12 + 10 * attempt) * 1_000_000_000)
                    continue
                }
                guard code == 200 else { throw URLError(.badServerResponse) }
                return try JSONDecoder().decode(Response.self, from: data).results
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        throw lastError
    }
}
