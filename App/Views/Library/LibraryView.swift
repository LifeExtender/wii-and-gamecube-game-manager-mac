import SwiftUI
import WiiKit

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @Bindable var list: GameList

    var body: some View {
        @Bindable var model = model
        let rows = model.rows(for: list)
        let prompt = model.syncPrompt(on: list)
        VStack(spacing: 0) {
            LibraryHeader(list: list)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            if let prompt {
                SyncBanner(prompt: prompt)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            content(rows)
                .animation(Motion.fade, value: model.settings.layout)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            LibraryFooter(list: list, rows: rows)
        }
        .animation(.easeOut(duration: 0.22), value: prompt?.games.count)
        .navigationTitle(list.name)
        .toolbar(removing: .title)
        .searchable(text: $list.search, placement: .toolbar, prompt: "Search")
        .toolbar { toolbar }
        .inspector(isPresented: $model.detailVisible) {
            DetailPane(list: list)
                .inspectorColumnWidth(min: 310, ideal: 348, max: 440)
        }
    }

    @ViewBuilder
    private func content(_ rows: [GameRow]) -> some View {
        if let message = list.message {
            ContentUnavailableView("This Library Could Not Be Read", systemImage: "exclamationmark.triangle", description: Text(message))
        } else if rows.isEmpty && list.isLoading {
            ProgressView()
        } else if rows.isEmpty && list.isDrive && list.search.isEmpty {
            EmptyDriveView(list: list)
        } else if rows.isEmpty {
            ContentUnavailableView(
                list.search.isEmpty ? "No Games Here" : "No Matches", systemImage: "opticaldisc",
                description: Text(list.search.isEmpty ? "No Wii or GameCube disc images were found." : "Try a different search."))
        } else if model.settings.layout == .grid {
            GameGrid(list: list, rows: rows).transition(.opacity)
        } else {
            GameTable(list: list, rows: rows).transition(.opacity)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var model = model
        ToolbarItem {
            Picker("View", selection: $model.settings.layout) {
                Image(systemName: "square.grid.2x2").tag(LibraryLayout.grid)
                Image(systemName: "list.bullet").tag(LibraryLayout.list)
            }
            .pickerStyle(.segmented)
            .help("Change view")
        }
        ToolbarItem {
            Menu {
                sortButton("Title", KeyPathComparator(\GameRow.title))
                sortButton("Game ID", KeyPathComparator(\GameRow.gameID))
                sortButton("Size", KeyPathComparator(\GameRow.sizeBytes, order: .reverse))
                sortButton("Region", KeyPathComparator(\GameRow.region))
                sortButton("Format", KeyPathComparator(\GameRow.format))
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            .help("Sort")
        }
        ToolbarItem {
            Button { model.detailVisible.toggle() } label: {
                Label("Details", systemImage: "sidebar.trailing")
            }
            .help("Show or hide details")
        }
    }

    private func sortButton(_ title: String, _ comparator: KeyPathComparator<GameRow>) -> some View {
        Button {
            list.sortOrder = [comparator]
        } label: {
            if list.sortOrder.first?.keyPath == comparator.keyPath {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
