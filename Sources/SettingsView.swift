import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var model: SearchModel
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if model.roots.isEmpty {
                        Label("App Documents", systemImage: "folder")
                        Text("Files ▸ On My iPhone ▸ grepios. Add folders below to search elsewhere.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(model.roots) { root in
                        Label(root.url.lastPathComponent, systemImage: root.isDirectory ? "folder" : "doc")
                    }
                    .onDelete { model.removeRoots(at: $0) }
                    Button { showImporter = true } label: {
                        Label("Add Folder or Files…", systemImage: "plus")
                    }
                } header: {
                    Text("Search In")
                } footer: {
                    if !model.roots.isEmpty { Text("Swipe left to remove a location.") }
                }

                Section("Matching") {
                    Toggle("Ignore case  (-i)", isOn: $model.options.ignoreCase)
                    Toggle("Literal text, not regex  (-F)", isOn: $model.options.fixedString)
                    Toggle("Whole words only  (-w)", isOn: $model.options.wholeWord)
                    Toggle("Invert match  (-v)", isOn: $model.options.invert)
                }

                Section {
                    Toggle("Recurse into subfolders  (-r)", isOn: $model.options.recursive)
                    Toggle("Include hidden files", isOn: $model.options.includeHidden)
                    Toggle("Skip binary files  (-I)", isOn: $model.options.skipBinary)
                    LabeledContent("Include") {
                        TextField("*.swift, *.txt", text: $model.options.includeGlob)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Exclude") {
                        TextField("*.log", text: $model.options.excludeGlob)
                            .multilineTextAlignment(.trailing)
                    }
                    Stepper("Max file size: \(model.options.maxFileSizeMB) MB",
                            value: $model.options.maxFileSizeMB, in: 1...500, step: 5)
                } header: {
                    Text("Files")
                } footer: {
                    Text("Include/exclude take filename globs separated by commas.")
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)

                Section("Output") {
                    Stepper("Context lines: \(model.options.contextLines)  (-C)",
                            value: $model.options.contextLines, in: 0...20)
                    Stepper("Max matches per file: \(model.options.maxMatchesPerFile == 0 ? "∞" : String(model.options.maxMatchesPerFile))  (-m)",
                            value: $model.options.maxMatchesPerFile, in: 0...10_000)
                }

                Section {
                    Button("Reset Options", role: .destructive) { model.options = GrepOptions() }
                }
            }
            .navigationTitle("Search Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.folder, .item],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { model.addRoots(urls) }
            }
        }
    }
}
