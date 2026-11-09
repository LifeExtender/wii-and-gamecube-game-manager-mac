import AppKit
import SwiftUI
import WiiKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    /// Quitting mid-copy would strand the running tool and leave a partial file on the drive.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.queue.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Work is still in progress"
        alert.informativeText = "Quitting now cancels it. Games that have already finished are safe."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Working")
        alert.addButton(withTitle: "Cancel and Quit")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        Task {
            await model.queue.cancelAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct WiiGameManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    private var model: AppModel { delegate.model }

    var body: some Scene {
        Window("Wii and GameCube Game Manager", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 1040, minHeight: 640)
        }
        .defaultSize(width: 1380, height: 840)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Library…") { model.chooseLibrary() }.keyboardShortcut("o")
                Divider()
                Button("Format External Drive…") { model.activeSheet = .format(preselected: nil) }
            }
            CommandGroup(after: .toolbar) {
                Picker(
                    "Appearance",
                    selection: Binding(get: { model.settings.appearance }, set: { model.settings.appearance = $0 })
                ) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                Divider()
                Button("View as Grid") { model.settings.layout = .grid }.keyboardShortcut("1")
                Button("View as List") { model.settings.layout = .list }.keyboardShortcut("2")
                Button(model.detailVisible ? "Hide Details" : "Show Details") { model.detailVisible.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Divider()
                Button("Reload") { model.reloadAll() }.keyboardShortcut("r")
            }
            CommandMenu("Library") {
                Button("Update Title List") { model.updateTitles() }
                Button("Update Game Database") { model.updateDatabase() }
            }
            CommandGroup(replacing: .help) {
                Button("Open Source Licence (GPL)") { model.showLicences() }
            }
        }

        Settings {
            SettingsView().environment(model)
        }
    }
}
