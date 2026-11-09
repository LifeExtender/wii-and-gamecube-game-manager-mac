import SwiftUI
import WiiKit

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 236, max: 290)
        } detail: {
            Group {
                switch model.pane {
                case .activity: ActivityView().transition(.opacity)
                case .artwork: ArtworkView().transition(.opacity)
                default:
                    if let list = model.currentList {
                        LibraryView(list: list).id(list.id).transition(.opacity)
                    } else {
                        WelcomeView().transition(.opacity)
                    }
                }
            }
            .animation(Motion.fade, value: model.pane)
            .background(Theme.canvas)
            .overlay { if dropTargeted { DropHighlight() } }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.addByDropping(urls)
            return !urls.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .sheet(item: $model.activeSheet) { sheet in
            switch sheet {
            case .convert(let draft): ConvertSheet(draft: draft)
            case .transfer(let draft): TransferSheet(draft: draft)
            case .resplit(let games): ResplitSheet(games: games)
            case .format(let preselected): FormatSheet(selection: preselected)
            case .customTitle(let game): CustomTitleSheet(game: game)
            case .addGames(let list, let preselected): AddGamesSheet(drive: list, preselected: preselected)
            }
        }
        .alert(item: $model.notice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message))
        }
    }
}

private struct DropHighlight: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
            .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .padding(10)
            .allowsHitTesting(false)
    }
}

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text("Your games, in one place")
                    .font(.system(size: 22, weight: .semibold))
                Text("Drop a folder or disc image anywhere in this window.")
                    .foregroundStyle(.secondary)
            }
            Button("Add Library…") { model.chooseLibrary() }
                .controlSize(.large)
                .primaryAction()
            Text("ISO · WBFS · WDF · CISO · WIA · GCZ")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 10)
        .onAppear { withAnimation(Motion.entrance(after: 0.05)) { appeared = true } }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Wii Game Manager")
    }
}
