import ImageIO
import SwiftUI
import WiiKit

/// Decodes and downsamples artwork off the main thread, keeping recent results in memory.
enum ArtworkCache {
    private static let memory = NSCache<NSString, NSImage>()

    static func cached(_ key: String) -> NSImage? { memory.object(forKey: key as NSString) }

    static func load(_ url: URL, pixels: Int, key: String) async -> NSImage? {
        let thumbnail = await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        guard let thumbnail else { return nil }
        let image = NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        memory.setObject(image, forKey: key as NSString)
        return image
    }
}

struct Artwork: View {
    @Environment(AppModel.self) private var model
    let kind: CoverKind
    let gameID: String
    var pixels = 480
    var fill = true
    var showsPlaceholder = true
    @State private var image: NSImage?

    private var artKey: String { "\(kind.rawValue)/\(gameID)" }
    private var cacheKey: String { "\(artKey)@\(pixels)" }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: fill ? .fill : .fit)
            } else if showsPlaceholder {
                ArtworkPlaceholder(gameID: gameID)
            } else {
                Color.clear
            }
        }
        .task(id: cacheKey) { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .artworkSaved)) { note in
            if note.object as? String == artKey { Task { await refresh() } }
        }
    }

    private func refresh() async {
        if let cached = ArtworkCache.cached(cacheKey), image != nil || model.hasCover(kind, gameID: gameID) {
            image = cached
            return
        }
        guard model.hasCover(kind, gameID: gameID) else {
            image = nil
            return
        }
        let loaded = await ArtworkCache.load(model.coverFile(kind, gameID: gameID), pixels: pixels, key: cacheKey)
        withAnimation(.easeOut(duration: 0.22)) { image = loaded }
    }
}

/// Shown until art arrives, and for games GameTDB has no art for.
struct ArtworkPlaceholder: View {
    let gameID: String

    var body: some View {
        ZStack {
            Theme.subtleFill
            VStack(spacing: 8) {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 26, weight: .ultraLight))
                    .foregroundStyle(.tertiary)
                Text(gameID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// The game's front cover at a fixed aspect, used by the grid, list and detail views.
struct CoverTile: View {
    let gameID: String
    var pixels = 480
    var corner = Theme.coverCorner

    var body: some View {
        Color.clear
            .aspectRatio(Theme.coverAspect, contentMode: .fit)
            .overlay { Artwork(kind: .flat, gameID: gameID, pixels: pixels) }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Theme.coverEdge, lineWidth: 0.5)
            }
    }
}
