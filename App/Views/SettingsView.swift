import SwiftUI
import WiiKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $model.settings.appearance) {
                    ForEach(AppearanceMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Library") {
                Toggle("Include subfolders", isOn: $model.settings.recurse)
                Toggle("Suggest games missing from connected drives", isOn: $model.settings.suggestMissing)
                Picker("Copy", selection: $model.settings.copyMode) {
                    ForEach(CopyMode.allCases) { Text($0.label).tag($0) }
                }
                Picker("Title language", selection: $model.settings.titleLanguage) {
                    ForEach(GameTDB.languages, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: model.settings.titleLanguage) {
                    model.updateTitles()
                    Task { await model.loadInfoFromDisk() }
                }
            }
            Section("Artwork") {
                Toggle("Download artwork automatically", isOn: $model.settings.autoDownloadCovers)
                Toggle("Prefer custom disc art", isOn: $model.settings.preferCustomDisc)
                Toggle("Prefer high quality full covers", isOn: $model.settings.highQualityFull)
                ForEach(CoverKind.allCases) { kind in
                    LabeledContent("\(kind.label) folder") {
                        HStack {
                            Text(model.coverFolder(kind).lastPathComponent).lineLimit(1)
                            Button("Choose…") {
                                if let url = model.chooseDestination() { model.settings.coverFolders[kind.rawValue] = url.path }
                            }
                        }
                    }
                    .help(model.coverFolder(kind).path)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 500)
    }
}
