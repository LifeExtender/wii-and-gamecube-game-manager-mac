import SwiftUI
import WiiKit

@MainActor
private func subject(_ games: [Game], _ model: AppModel) -> String {
    games.count == 1 ? model.displayTitle(for: games[0]) : "\(games.count) games"
}

private struct DestinationField: View {
    @Environment(AppModel.self) private var model
    @Binding var destination: URL?

    var body: some View {
        HStack(spacing: 8) {
            Text(destination?.path ?? "Not chosen")
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(destination == nil ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Choose…") { destination = model.chooseDestination() ?? destination }
        }
    }
}

struct ConvertSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: ConvertDraft

    private var heading: String { draft.games.first?.isOnPartition == true ? "Extract" : "Convert" }

    private var preview: String? {
        guard let first = draft.games.first else { return nil }
        let base = URL(fileURLWithPath: "/")
        let url = Naming.outputURL(
            base: base, gameID: first.gameID, title: model.displayTitle(for: first), format: draft.format,
            naming: draft.naming, subdirectories: draft.subdirectories)
        return String(url.path.dropFirst())
    }

    var body: some View {
        SheetScaffold(title: heading, subtitle: subject(draft.games, model)) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    FieldLabel("Format")
                    Picker("Format", selection: $draft.format) {
                        Text("WBFS").tag(OutputFormat.wbfs)
                        Text("ISO").tag(OutputFormat.iso)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .tint(Theme.accent)
                    .frame(width: 160)
                }
                GridRow {
                    FieldLabel("Split")
                    Picker("Split", selection: $draft.split) {
                        ForEach(SplitMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    FieldLabel("Layout")
                    Toggle("Put each game in its own folder", isOn: $draft.subdirectories)
                        .tint(Theme.accent)
                }
                if !draft.subdirectories {
                    GridRow {
                        FieldLabel("Name")
                        Picker("Name", selection: $draft.naming) {
                            ForEach(NamingStyle.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }
                GridRow {
                    FieldLabel("Save to")
                    DestinationField(destination: $draft.destination)
                }
                if let preview {
                    GridRow {
                        FieldLabel("Creates")
                        Text(preview)
                            .font(.callout.monospaced())
                            .lineLimit(2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } actions: {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(heading) {
                if let destination = draft.destination { model.enqueueConvert(draft, destination: destination) }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .primaryAction()
            .disabled(draft.destination == nil)
        }
    }
}

struct TransferSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: TransferDraft
    @State private var destination: URL?

    private var heading: String { draft.move ? "Move" : "Copy" }

    var body: some View {
        SheetScaffold(title: heading, subtitle: subject(draft.games, model)) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    FieldLabel("Layout")
                    Toggle("Put each game in its own folder", isOn: $draft.subdirectories)
                        .tint(Theme.accent)
                }
                GridRow {
                    FieldLabel("Save to")
                    DestinationField(destination: $destination)
                }
            }
        } actions: {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(heading) {
                if let destination { model.enqueueTransfer(draft, destination: destination) }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .primaryAction()
            .disabled(destination == nil)
        }
    }
}

struct ResplitSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let games: [Game]
    @State private var split: SplitMode = .fourGB

    var body: some View {
        SheetScaffold(title: "Resplit", subtitle: subject(games, model)) {
            Picker("Split", selection: $split) {
                ForEach(SplitMode.allCases) { Text($0.label).tag($0) }
            }
            .fixedSize()
        } actions: {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Resplit") {
                model.enqueueResplit(games, split: split)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .primaryAction()
        }
    }
}

struct CustomTitleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let game: Game
    @State private var title = ""

    var body: some View {
        SheetScaffold(title: "Custom Title", subtitle: game.gameID) {
            QuietField(placeholder: "Leave empty to use the title list", text: $title)
                .onAppear { title = model.customTitles[game.gameID] ?? "" }
        } actions: {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Save") {
                model.setCustomTitle(title, for: game.gameID)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .primaryAction()
        }
    }
}
