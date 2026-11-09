import SwiftUI
import WiiKit

struct GameCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let row: GameRow
    let selected: Bool
    let onDrive: Bool
    let job: Job?
    let justFinished: Bool
    let entranceDelay: Double?
    @State private var hovered = false
    @State private var tilt = CGSize.zero
    @State private var glare = UnitPoint.center
    @State private var size = CGSize(width: 1, height: 1)
    @State private var appeared: Bool

    init(row: GameRow, selected: Bool, onDrive: Bool, job: Job?, justFinished: Bool, entranceDelay: Double?) {
        self.row = row
        self.selected = selected
        self.onDrive = onDrive
        self.job = job
        self.justFinished = justFinished
        self.entranceDelay = entranceDelay
        _appeared = State(initialValue: entranceDelay == nil)
    }

    private var shadowStrength: Double { scheme == .dark ? 0.32 : 0.16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            cover
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text("\(row.gameID) · \(row.format)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared || Motion.reduced ? 0 : 12)
        .onAppear {
            model.requestArtwork(.flat, gameID: row.gameID)
            if let entranceDelay, !appeared {
                withAnimation(Motion.entrance(after: entranceDelay)) { appeared = true }
            }
        }
    }

    private var cover: some View {
        CoverTile(gameID: row.gameID)
            .overlay { if hovered && !Motion.reduced { glareLayer } }
            .overlay {
                if let job {
                    JobOverlay(job: job).transition(.opacity)
                }
            }
            .shadow(color: .black.opacity(hovered ? shadowStrength * 1.7 : shadowStrength), radius: hovered ? 14 : 6, y: hovered ? 8 : 3)
            .overlay(alignment: .bottomTrailing) {
                if onDrive && job == nil && !justFinished {
                    OnDriveMark().padding(6).transition(Motion.badge)
                }
            }
            .overlay {
                if justFinished {
                    CompletionMark().transition(Motion.badge)
                }
            }
            .overlay {
                if selected {
                    SelectionRing(corner: Theme.coverCorner + 3, inset: 4)
                }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .rotation3DEffect(.degrees(tilt.width), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
            .rotation3DEffect(.degrees(tilt.height), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
            .scaleEffect(hovered && !Motion.reduced ? 1.025 : 1)
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hovered = true
                    let across = point.x / max(size.width, 1)
                    let down = point.y / max(size.height, 1)
                    glare = UnitPoint(x: across, y: down)
                    if !Motion.reduced { tilt = CGSize(width: (across - 0.5) * 9, height: (0.5 - down) * 9) }
                case .ended:
                    hovered = false
                    tilt = .zero
                }
            }
            .animation(Motion.reduced ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.78), value: tilt)
            .animation(Motion.reduced ? nil : .easeOut(duration: 0.16), value: hovered)
            .animation(Motion.pop, value: selected)
            .animation(Motion.pop, value: onDrive)
            .animation(Motion.pop, value: justFinished)
            .animation(Motion.fade, value: job == nil)
    }

    /// A soft highlight that follows the pointer, as if light were catching the case.
    private var glareLayer: some View {
        RadialGradient(
            colors: [.white.opacity(0.26), .white.opacity(0)], center: glare,
            startRadius: 0, endRadius: max(size.width, 60) * 0.85
        )
        .blendMode(.plusLighter)
        .clipShape(RoundedRectangle(cornerRadius: Theme.coverCorner, style: .continuous))
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

private struct OnDriveMark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 19, height: 19)
            .background(Theme.accent, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .help("Already on a connected drive")
    }
}

/// Plays over a cover for a moment when its copy finishes.
private struct CompletionMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.coverCorner, style: .continuous)
                .fill(.black.opacity(0.28))
            Image(systemName: "checkmark")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Theme.accent, in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        }
    }
}

/// Dims a cover while its game is queued or being written.
private struct JobOverlay: View {
    let job: Job

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.coverCorner, style: .continuous)
                .fill(.black.opacity(0.52))
            if job.state == .running {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: job.fraction ?? 0.02)
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.3), value: job.fraction)
                    Text((job.fraction ?? 0), format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                        .animation(Motion.snappy, value: job.fraction)
                }
                .frame(width: 52, height: 52)
                .transition(Motion.badge)
            } else {
                Text("Waiting")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .transition(.opacity)
            }
        }
        .animation(Motion.pop, value: job.state == .running)
    }
}
