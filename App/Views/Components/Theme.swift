import AppKit
import SwiftUI

enum Theme {
    /// The one colour in the interface. Everything else is neutral.
    static let accent = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.18, green: 0.60, blue: 0.91, alpha: 1)
                : NSColor(srgbRed: 0.02, green: 0.49, blue: 0.80, alpha: 1)
        })

    /// The main content surface.
    static let canvas = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0.118, green: 0.118, blue: 0.125, alpha: 1)
                : NSColor(srgbRed: 0.98, green: 0.98, blue: 0.985, alpha: 1)
        })

    static let coverEdge = Color.primary.opacity(0.1)
    static let hairline = Color.primary.opacity(0.08)
    static let subtleFill = Color.primary.opacity(0.045)
    static let hoverFill = Color.primary.opacity(0.06)
    static let selectedFill = Color.primary.opacity(0.1)

    static let coverAspect: CGFloat = 160.0 / 224.0
    static let coverCorner: CGFloat = 7
    static let rowCorner: CGFloat = 7
}

/// Every animation in the app, so timing stays consistent. Honours the system's Reduce Motion setting.
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Navigation and highlights.
    static var snappy: Animation? { reduced ? nil : .snappy(duration: 0.26) }
    /// Things settling into place.
    static var gentle: Animation? { reduced ? nil : .spring(response: 0.42, dampingFraction: 0.82) }
    /// Small elements appearing, with a slight overshoot.
    static var pop: Animation? { reduced ? nil : .spring(response: 0.3, dampingFraction: 0.68) }
    /// Crossfades. Kept under Reduce Motion, which limits movement rather than fades.
    static var fade: Animation { .easeOut(duration: 0.18) }

    static func entrance(after delay: Double) -> Animation? {
        reduced ? nil : .spring(response: 0.4, dampingFraction: 0.86).delay(delay)
    }

    static var content: AnyTransition { reduced ? .opacity : .opacity.combined(with: .offset(y: 6)) }
    static var card: AnyTransition { reduced ? .opacity : .scale(scale: 0.94).combined(with: .opacity) }
    static var badge: AnyTransition { reduced ? .opacity : .scale(scale: 0.4).combined(with: .opacity) }

    static func slide(from edge: Edge) -> AnyTransition {
        reduced ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

extension Notification.Name {
    static let artworkSaved = Notification.Name("WiiGameManager.artworkSaved")
}

func byteText(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
