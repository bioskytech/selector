import Foundation
import MusicKit

/// Finds each planned track in the Apple Music catalog and remembers the answer.
actor AppleMusicMatcher {
    private var cache: [String: String] = [:]      // catalog key -> Apple song id ("" = not on Apple Music)
    private var songs: [String: Song] = [:]        // Apple song id -> Song
    private let defaultsKey = "selector.applemusic.matches.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode([String: String].self, from: data) {
            cache = saved
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    /// Returns the matching Apple Music song, or nil when the catalog has no good match.
    func find(track j: Int, in cat: Catalog, clean: Bool) async -> Song? {
        let t = cat.t
        let cacheKey = (clean ? "c:" : "") + t.id[j]
        if let known = cache[cacheKey] {
            if known.isEmpty { return nil }
            if let s = songs[known] { return s }
            if let s = await fetchSong(id: known) { songs[known] = s; return s }
        }

        let want = Normalizer.title(t.n[j])
        let artistKeys = t.ar[j].components(separatedBy: ", ").map(Normalizer.artist).filter { !$0.isEmpty }
        let title = Normalizer.searchTitle(t.n[j])
        let artist = t.ar[j].components(separatedBy: ", ").first ?? ""

        var best: Song?
        var bestScore = 0.0
        var searched = false
        for term in ["\(title) \(artist)", title] {
            guard let results = await search(term) else { continue }
            searched = true
            for s in results {
                guard s.playParameters != nil else { continue }
                if clean && s.contentRating == .explicit { continue }
                let tt = Normalizer.title(s.title)
                var titleScore = 0.0
                if tt == want { titleScore = 1 }
                else if (tt.contains(want) || want.contains(tt)) && min(tt.count, want.count) >= 4 { titleScore = 0.8 }
                let an = Normalizer.artist(s.artistName)
                let artistScore: Double = artistKeys.contains { an.contains($0) || $0.contains(an) } ? 1 : 0
                let dd = abs((s.duration ?? 0) - Double(t.dur[j]))
                let durationScore: Double = dd <= 4 ? 1 : (dd <= 15 ? 0.6 : (dd <= 40 ? 0.2 : 0))
                let score = titleScore * 0.55 + artistScore * 0.35 + durationScore * 0.10
                if score > bestScore { bestScore = score; best = s }
            }
            if bestScore >= 0.8 { break }
        }
        guard searched else { return nil }   // network trouble: don't remember a miss
        let hit = bestScore >= 0.72 ? best : nil
        cache[cacheKey] = hit?.id.rawValue ?? ""
        persist()
        if let hit { songs[hit.id.rawValue] = hit }
        return hit
    }

    private func search(_ term: String) async -> [Song]? {
        for attempt in 0..<3 {
            do {
                var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
                request.limit = 10
                let response = try await request.response()
                return Array(response.songs)
            } catch {
                try? await Task.sleep(nanoseconds: UInt64(600_000_000 * (attempt + 1)))
            }
        }
        return nil
    }

    private func fetchSong(id: String) async -> Song? {
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: MusicItemID(id))
        return try? await request.response().items.first
    }
}
