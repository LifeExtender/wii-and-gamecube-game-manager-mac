import AppKit
import Observation
import QuartzCore
import WiiKit

/// The app's shared state. Features live in extensions, one file per concern.
@MainActor @Observable
final class AppModel {
    let engine: Engine
    let disks: DiskService
    let queue = JobQueue()

    var libraries: [GameList] = []
    var drives: [DriveEntry] = []
    var pane: Pane?
    var activeSheet: ActiveSheet?
    var notice: Notice?
    var detailVisible = true
    var detailTab: DetailTab = .overview
    var artworkRevision = 0
    var titles = TitleDatabase()
    var info: [String: GameInfo] = [:]
    var customTitles: [String: String] = [:]
    var verification: [String: Verification] = [:]

    var settings: AppSettings {
        didSet {
            saveSettings()
            if oldValue.appearance != settings.appearance { applyAppearance(crossfade: true) }
        }
    }

    @ObservationIgnored var discInfoCache: [String: DiscInfo] = [:]
    @ObservationIgnored var discNumbers: [String: Int] = [:]
    @ObservationIgnored var sizeEstimates: [String: Int64] = [:]
    @ObservationIgnored var artQueue: [(CoverKind, String)] = []
    @ObservationIgnored var artRequested = Set<String>()
    @ObservationIgnored var artTask: Task<Void, Never>?
    @ObservationIgnored private var driveMonitor: DriveMonitor?

    static let supportFolder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Wii Game Manager", isDirectory: true)
    }()

    init() {
        let tools = Tools(directory: Bundle.main.executableURL!.deletingLastPathComponent())
        engine = Engine(tools: tools)
        disks = DiskService(tools: tools)
        settings = Self.loadSettings()
        applyAppearance()
        try? FileManager.default.createDirectory(at: Self.supportFolder, withIntermediateDirectories: true)
        loadCustomTitles()
        loadTitlesFromDisk()
        Task { await self.loadInfoFromDisk() }

        queue.onGameFinished = { [weak self] in self?.reloadMountedDrives() }
        queue.onDrained = { [weak self] in self?.reloadAll() }

        restoreLibraries()
        if titles.isEmpty { updateTitles() }
        driveMonitor = DriveMonitor { [weak self] in self?.refreshDrives() }
        refreshDrives()
    }

    private static func loadSettings() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "settings"),
            let saved = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return saved
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "settings") }
    }

    /// A fade added to the window's layer dissolves from the old colours to the new ones.
    private func applyAppearance(crossfade: Bool = false) {
        if crossfade, !Motion.reduced,
            let window = NSApp.mainWindow ?? NSApp.windows.first(where: \.isVisible),
            let layer = window.contentView?.superview?.layer ?? window.contentView?.layer
        {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.3
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "appearanceChange")
        }
        NSApplication.shared.appearance = settings.appearance.nsAppearance
    }

    func chooseDestination() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func showLicences() {
        if let url = Bundle.main.url(forResource: "gpl-2.0", withExtension: "txt") { NSWorkspace.shared.open(url) }
    }
}
