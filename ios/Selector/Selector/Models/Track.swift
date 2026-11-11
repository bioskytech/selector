import Foundation
import MusicKit
import CoreGraphics

/// A planned song, found on a service. With `song` it can play in full through Apple Music;
/// without it (found through the public iTunes lookup) it has artwork and a 30-second preview.
struct Track {
    let id: String
    var song: Song?
    var previewURL: URL?
    var duration: Double?
    private var artTemplate: String?      // artwork URL containing "100x100"
    private var artwork: Artwork?

    init(song: Song) {
        id = song.id.rawValue
        self.song = song
        previewURL = song.previewAssets?.first?.url
        duration = song.duration
        artwork = song.artwork
    }

    init(id: String, previewURL: URL?, duration: Double?, artworkURL100: String?) {
        self.id = id
        self.previewURL = previewURL
        self.duration = duration
        artTemplate = artworkURL100
    }

    func artworkURL(_ size: Int) -> URL? {
        if let artwork { return artwork.url(width: size, height: size) }
        guard let artTemplate else { return nil }
        return URL(string: artTemplate.replacingOccurrences(of: "100x100", with: "\(size)x\(size)"))
    }

    var tint: CGColor? { artwork?.backgroundColor }
}
