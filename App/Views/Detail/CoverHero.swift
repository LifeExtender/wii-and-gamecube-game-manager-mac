import SwiftUI
import WiiKit

/// A soft wash of the cover's own colours behind the top of the panel.
struct AmbientBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    let gameID: String

    var body: some View {
        Color.clear
            .frame(height: 400)
            .overlay {
                Artwork(kind: .flat, gameID: gameID, pixels: 120, showsPlaceholder: false)
                    .scaleEffect(1.6)
                    .blur(radius: 64)
                    .saturation(1.35)
                    .opacity(scheme == .dark ? 0.5 : 0.42)
            }
            .clipped()
            .mask(LinearGradient(colors: [.black, .black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
    }
}

private enum CoverMode: String, CaseIterable, Identifiable {
    case cover = "Cover", threeD = "3D", disc = "Disc", full = "Full"
    var id: String { rawValue }
}

struct CoverHero: View {
    @Environment(AppModel.self) private var model
    let gameID: String
    @State private var mode: CoverMode = .cover
    @State private var hasDisc = false
    @State private var discOut = false
    @State private var spinning = false

    var body: some View {
        VStack(spacing: 12) {
            artwork.frame(height: 236)
            HStack(spacing: 16) {
                ForEach(CoverMode.allCases) { option in
                    Button(option.rawValue) { select(option) }
                        .buttonStyle(.plain)
                        .font(.caption.weight(mode == option ? .semibold : .regular))
                        .foregroundStyle(mode == option ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                }
            }
        }
        .onAppear {
            hasDisc = model.hasCover(.disc, gameID: gameID)
            model.requestArtwork(.flat, gameID: gameID)
            model.requestArtwork(.disc, gameID: gameID)
            if hasDisc { slideDiscOut() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .artworkSaved)) { note in
            if note.object as? String == "disc/\(gameID)" {
                hasDisc = true
                slideDiscOut()
            }
        }
    }

    private func slideDiscOut() {
        withAnimation(Motion.reduced ? nil : .spring(response: 0.6, dampingFraction: 0.76).delay(0.1)) { discOut = true }
    }

    private func select(_ option: CoverMode) {
        withAnimation(Motion.fade) { mode = option }
        switch option {
        case .cover: break
        case .threeD: model.requestArtwork(.threeD, gameID: gameID)
        case .disc: model.requestArtwork(.disc, gameID: gameID)
        case .full: model.requestArtwork(.full, gameID: gameID)
        }
    }

    /// The default view slides the disc out from behind its case, and spins it under the pointer.
    @ViewBuilder
    private var artwork: some View {
        switch mode {
        case .cover:
            ZStack {
                if hasDisc {
                    Artwork(kind: .disc, gameID: gameID, pixels: 500, fill: false, showsPlaceholder: false)
                        .frame(width: 148, height: 148)
                        .rotationEffect(.degrees(spinning ? 360 : 0))
                        .animation(
                            spinning ? .linear(duration: 3.6).repeatForever(autoreverses: false) : .spring(response: 0.7, dampingFraction: 0.8),
                            value: spinning
                        )
                        .rotationEffect(.degrees(discOut ? 0 : -80))
                        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                        .offset(x: discOut ? 56 : 0)
                }
                CoverTile(gameID: gameID, pixels: 640)
                    .frame(height: 226)
                    .shadow(color: .black.opacity(0.28), radius: 14, y: 7)
                    .offset(x: discOut ? -26 : 0)
            }
            .contentShape(Rectangle())
            .onHover { spinning = $0 && hasDisc && !Motion.reduced }
            .transition(.opacity)
        case .threeD: Artwork(kind: .threeD, gameID: gameID, pixels: 640, fill: false).transition(.opacity)
        case .disc: Artwork(kind: .disc, gameID: gameID, pixels: 640, fill: false).transition(.opacity)
        case .full: Artwork(kind: .full, gameID: gameID, pixels: 1024, fill: false).transition(.opacity)
        }
    }
}
