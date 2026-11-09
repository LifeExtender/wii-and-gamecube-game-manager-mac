import SwiftUI
import WiiKit

struct FormatSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var selection: String?
    @State private var disks: [ExternalDisk] = []
    @State private var kind: DriveFormat = .fat32
    @State private var name = "WII"
    @State private var typed = ""
    @State private var working = false
    @State private var status = ""
    @State private var failure: String?
    @State private var loading = true

    private var chosen: ExternalDisk? { disks.first { $0.id == selection } }
    private var phrase: String { "ERASE \(selection ?? "")" }
    private var sizeProblem: String? { chosen.flatMap { DiskGuard.sizeRefusal(bytes: $0.facts.sizeBytes, format: kind) } }
    private var confirmed: Bool {
        typed.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(phrase) == .orderedSame
    }

    /// Says what is still needed, so the button is never disabled without explanation.
    private var blocker: String? {
        if chosen == nil { return "Choose a drive to continue." }
        if sizeProblem != nil { return nil }
        if kind == .fat32, !DiskGuard.isValidVolumeName(name) { return "Enter a name for the drive." }
        if !confirmed { return "Type \(phrase) in the box above to enable Erase Drive." }
        return nil
    }

    private var ready: Bool { blocker == nil && sizeProblem == nil && !working }

    var body: some View {
        SheetScaffold(title: "Format Drive", subtitle: "Everything on the chosen drive will be erased.", width: 540) {
            Group {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 110)
                } else if disks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "externaldrive")
                            .font(.system(size: 30, weight: .ultraLight))
                            .foregroundStyle(.tertiary)
                        Text("No external drive connected").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 110)
                } else {
                    form
                }
            }
            .disabled(working)
            if let sizeProblem { Text(sizeProblem).font(.callout).foregroundStyle(.red) }
            if working {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status).font(.callout).foregroundStyle(.secondary)
                }
            } else if let blocker, !disks.isEmpty {
                Text(blocker).font(.callout).foregroundStyle(.secondary)
            }
            if let failure { Text(failure).font(.callout).foregroundStyle(.red).textSelection(.enabled) }
        } actions: {
            Button("Refresh") { Task { await refresh() } }.disabled(working)
            Spacer()
            Button("Close", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
            Button("Erase Drive", role: .destructive) { Task { await erase() } }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .opacity(ready ? 1 : 0.4)
                .disabled(!ready)
        }
        .task { await refresh() }
        .onChange(of: selection) { typed = "" }
        .onChange(of: name) { _, new in
            let clean = DiskGuard.sanitizedVolumeName(new)
            if clean != new { name = clean }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Drive")
                ForEach(disks) { disk in
                    OptionCard(
                        title: "\(disk.facts.mediaName) · \(byteText(disk.facts.sizeBytes))",
                        detail: contents(of: disk),
                        selected: selection == disk.id,
                        action: { selection = disk.id }
                    ) {
                        Image(systemName: "externaldrive").foregroundStyle(.secondary).frame(width: 20)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Format")
                HStack(alignment: .top, spacing: 8) {
                    OptionCard(
                        title: "FAT32", detail: "Recommended. Holds Wii and GameCube games as ordinary files you can see in Finder.",
                        selected: kind == .fat32, action: { kind = .fat32 }
                    ) { EmptyView() }
                    OptionCard(
                        title: "WBFS", detail: "Wii games only, in a raw partition this Mac can't browse.",
                        selected: kind == .wbfs, action: { kind = .wbfs }
                    ) { EmptyView() }
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                if kind == .fat32 {
                    GridRow {
                        FieldLabel("Name")
                        HStack(spacing: 10) {
                            QuietField(placeholder: "WII", text: $name).frame(width: 180)
                            Text("Capitals, up to 11 characters").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if selection != nil {
                    GridRow {
                        FieldLabel("Confirm")
                        HStack(spacing: 8) {
                            QuietField(placeholder: "", text: $typed, monospaced: true)
                            Image(systemName: confirmed ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(confirmed ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.tertiary))
                        }
                    }
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Text("Type **\(phrase)** to confirm.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Names what would be lost, so the wrong drive is recognisable before anything is typed.
    private func contents(of disk: ExternalDisk) -> String {
        let parts = disk.partitions.filter { $0.content != "EFI" }.compactMap { partition -> String? in
            guard let mount = partition.mountPoint else {
                return partition.volumeName.isEmpty ? nil : partition.volumeName
            }
            let items = ((try? FileManager.default.contentsOfDirectory(atPath: mount)) ?? [])
                .filter { !$0.hasPrefix(".") }
                .sorted()
            if items.isEmpty { return "\(partition.volumeName): empty" }
            let head = items.prefix(4).joined(separator: ", ")
            return "\(partition.volumeName): \(items.count > 4 ? "\(head) and \(items.count - 4) more" : head)"
        }
        return parts.isEmpty ? "No readable volumes" : parts.joined(separator: "; ")
    }

    private func refresh() async {
        loading = true
        failure = nil
        do {
            disks = try await model.disks.listExternal().filter { $0.facts.sizeBytes <= DiskGuard.maxFAT32Bytes }
            if !disks.contains(where: { $0.id == selection }) { selection = nil }
        } catch {
            failure = error.localizedDescription
        }
        loading = false
    }

    private func erase() async {
        guard let chosen, confirmed else { return }
        working = true
        failure = nil
        let setStatus: @Sendable (String) -> Void = { text in Task { @MainActor in status = text } }
        let label = "\(chosen.facts.mediaName) (\(chosen.id))"
        let action = "Format \(kind == .fat32 ? "FAT32" : "WBFS")"
        model.forgetLibraries(onDisk: chosen.id)
        do {
            try await model.disks.format(snapshot: chosen.facts, as: kind, volumeName: kind == .fat32 ? name : "WBFS", status: setStatus)
            model.queue.note(title: label, action: action, result: "Done", succeeded: true)
            status = "Preparing the drive"
            await model.finishFormat(disk: chosen.id, kind: kind)
            working = false
            dismiss()
        } catch is OperationCancelled {
            working = false
            failure = "Cancelled at the password prompt. The drive's partition map may already have been rewritten."
        } catch {
            working = false
            failure = error.localizedDescription
            model.queue.note(title: label, action: action, result: error.localizedDescription, succeeded: false)
        }
    }
}
