import SwiftUI
import WiiKit

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Namespace private var highlight

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    libraries
                    if !model.drives.isEmpty {
                        drives.transition(.opacity)
                    }
                    tools
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            if let job = model.queue.runningJob {
                SidebarProgress(job: job)
                    .transition(Motion.slide(from: .bottom))
            }
            AppearanceSwitch()
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, 4)
        }
        .animation(Motion.snappy, value: model.pane)
        .animation(Motion.snappy, value: model.drives.map(\.id))
        .animation(Motion.snappy, value: model.folderLibraries.map(\.id))
        .animation(Motion.gentle, value: model.queue.runningJob == nil)
    }

    private var libraries: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                SectionLabel(text: "Libraries")
                Spacer()
                Button { model.chooseLibrary() } label: {
                    Image(systemName: "plus").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Add a library")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 3)
            if model.folderLibraries.isEmpty {
                Text("None yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
            }
            ForEach(model.folderLibraries) { list in
                SidebarRow(
                    icon: "square.stack", title: list.name, count: list.games.count,
                    selected: model.pane == .library(list.id), namespace: highlight
                ) {
                    model.pane = .library(list.id)
                }
                .transition(.opacity)
                .contextMenu {
                    Button("Reload") { model.reload(list) }
                    if let folder = list.source.folder {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    }
                    Divider()
                    Button("Remove from Sidebar") { model.remove(list) }
                }
            }
        }
    }

    private var drives: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "Drives")
                .padding(.horizontal, 8)
                .padding(.bottom, 3)
            ForEach(model.drives) { drive in
                DriveRow(drive: drive, namespace: highlight)
                    .transition(Motion.slide(from: .leading))
            }
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 2) {
            SidebarRow(
                icon: "clock", title: "Activity", count: model.queue.activeCount == 0 ? nil : model.queue.activeCount,
                selected: model.pane == .activity, namespace: highlight
            ) {
                model.pane = .activity
            }
            SidebarRow(icon: "photo.on.rectangle", title: "Artwork", count: nil, selected: model.pane == .artwork, namespace: highlight) {
                model.pane = .artwork
            }
        }
    }
}

/// The selected row's background is one shared shape, so it glides between rows.
private struct RowBackground: ViewModifier {
    let selected: Bool
    let hovered: Bool
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content.background {
            let shape = RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
            if selected {
                shape.fill(Theme.selectedFill).matchedGeometryEffect(id: "sidebar-selection", in: namespace)
            } else if hovered {
                shape.fill(Theme.hoverFill)
            }
        }
    }
}

private struct CountLabel: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.tertiary)
            .contentTransition(.numericText())
            .animation(Motion.snappy, value: count)
    }
}

private struct SidebarRow: View {
    let icon: String
    let title: String
    let count: Int?
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if let count, count > 0 { CountLabel(count: count) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5.5)
            .contentShape(Rectangle())
            .modifier(RowBackground(selected: selected, hovered: hovered, namespace: namespace))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

private struct DriveRow: View {
    @Environment(AppModel.self) private var model
    let drive: DriveEntry
    let namespace: Namespace.ID
    @State private var hovered = false

    var body: some View {
        let library = model.library(for: drive)
        let selected = library.map { model.pane == .library($0.id) } ?? false
        Button { model.open(drive) } label: {
            VStack(spacing: 5) {
                HStack(spacing: 9) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(drive.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 4)
                    if hovered {
                        Button { model.eject(drive) } label: {
                            Image(systemName: "eject.fill").font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Eject")
                        .transition(.opacity)
                    } else if let count = library?.games.count, count > 0 {
                        CountLabel(count: count).transition(.opacity)
                    }
                }
                .animation(Motion.fade, value: hovered)
                if let used = model.usedFraction(of: drive) {
                    UsageBar(fraction: used, height: 3, color: .secondary.opacity(0.7))
                        .padding(.leading, 27)
                        .padding(.trailing, 2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .modifier(RowBackground(selected: selected, hovered: hovered, namespace: namespace))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Format…") { model.activeSheet = .format(preselected: drive.diskIdentifier) }
            Button("Eject") { model.eject(drive) }
        }
        .help("\(drive.identifier), \(byteText(drive.sizeBytes))")
    }
}

private struct SidebarProgress: View {
    @Environment(AppModel.self) private var model
    let job: Job

    private var counter: String? {
        model.queue.batchTotal > 1 ? "\(min(model.queue.batchDone + 1, model.queue.batchTotal)) of \(model.queue.batchTotal)" : nil
    }

    var body: some View {
        Button { model.pane = .activity } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(job.action).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if let counter {
                        Text(counter)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .contentTransition(.numericText())
                            .animation(Motion.snappy, value: counter)
                    }
                }
                Text(job.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(Motion.fade, value: job.title)
                UsageBar(fraction: job.fraction ?? 0.02, height: 4)
                if !job.detail.isEmpty {
                    Text(job.detail).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }
}

private struct AppearanceSwitch: View {
    @Environment(AppModel.self) private var model
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    withAnimation(Motion.snappy) { model.settings.appearance = mode }
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(model.settings.appearance == mode ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                        .background {
                            if model.settings.appearance == mode {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.selectedFill)
                                    .matchedGeometryEffect(id: "appearance", in: highlight)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(mode.label)
            }
        }
        .padding(2)
        .background(Theme.subtleFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
