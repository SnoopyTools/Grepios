import SwiftUI

struct LineTarget: Hashable {
    let file: FileResult
    let line: Int
}

struct ContentView: View {
    @StateObject private var model = SearchModel()
    @State private var showSettings = false
    @FocusState private var patternFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                results
                statusBar
            }
            .navigationTitle("grepios")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $showSettings, onDismiss: { model.rerunIfNeeded() }) {
                SettingsView(model: model)
            }
            .navigationDestination(for: LineTarget.self) { target in
                FileViewer(target: target, regex: model.activeRegex)
            }
            .alert("Error", isPresented: Binding(get: { model.errorMessage != nil },
                                                 set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("pattern (regex)", text: $model.pattern)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($patternFocused)
                    .onSubmit { model.start() }
                if !model.pattern.isEmpty {
                    Button { model.pattern = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("-i", "Ignore case", \.ignoreCase)
                    chip("-F", "Literal", \.fixedString)
                    chip("-w", "Whole word", \.wholeWord)
                    chip("-v", "Invert", \.invert)
                    chip("-r", "Recursive", \.recursive)
                }
            }

            Button { showSettings = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text("in ").foregroundColor(.secondary) + Text(model.scopeDescription)
                    Spacer(minLength: 0)
                    Image(systemName: "slider.horizontal.3")
                }
                .font(.footnote)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
        .padding()
    }

    private func chip(_ flag: String, _ label: String, _ key: WritableKeyPath<GrepOptions, Bool>) -> some View {
        FlagChip(flag: flag, label: label, isOn: model.options[keyPath: key]) {
            model.options[keyPath: key].toggle()
            model.rerunIfNeeded()
        }
    }

    // MARK: Results

    private var results: some View {
        List {
            ForEach(model.results) { file in
                Section {
                    ForEach(file.lines) { line in
                        if line.kind == .separator {
                            Text("--")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        } else {
                            NavigationLink(value: LineTarget(file: file, line: line.number)) {
                                LineRow(line: line)
                            }
                            .contextMenu {
                                Button { UIPasteboard.general.string = line.text } label: {
                                    Label("Copy Line", systemImage: "doc.on.doc")
                                }
                                Button { UIPasteboard.general.string = "\(file.displayPath):\(line.number):\(line.text)" } label: {
                                    Label("Copy as grep output", systemImage: "terminal")
                                }
                                Button { UIPasteboard.general.string = file.url.path } label: {
                                    Label("Copy File Path", systemImage: "link")
                                }
                            }
                        }
                    }
                } header: {
                    HStack {
                        Image(systemName: "doc.text")
                        Text(file.displayPath).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text("\(file.matchCount)")
                            .font(.caption.monospacedDigit().bold())
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
        .overlay {
            if model.results.isEmpty && !model.isSearching {
                if model.hasSearched {
                    ContentUnavailableView.search(text: model.pattern)
                } else {
                    ContentUnavailableView("Search file contents",
                                           systemImage: "text.magnifyingglass",
                                           description: Text("Type a regular expression and tap Search.\nChoose folders with the folder row above."))
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isSearching { ProgressView().controlSize(.small) }
            Text(model.statusText)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !model.results.isEmpty {
                ShareLink(item: model.exportText) { Image(systemName: "square.and.arrow.up") }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if model.isSearching {
                Button("Stop") { model.stop() }
            } else {
                Button("Search") {
                    patternFocused = false
                    model.start()
                }
                .bold()
                .disabled(model.pattern.isEmpty)
            }
        }
    }
}

// MARK: - Pieces

struct FlagChip: View {
    let flag: String
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(flag).font(.system(.caption, design: .monospaced).bold())
                Text(label).font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground), in: Capsule())
            .overlay(Capsule().strokeBorder(isOn ? Color.accentColor : Color.clear, lineWidth: 1))
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct LineRow: View {
    let line: ResultLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(line.number)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(line.kind == .match ? Color.accentColor : Color.secondary)
                .frame(minWidth: 34, alignment: .trailing)
            Text(highlight(line.text, line.spans))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(line.kind == .context ? Color.secondary : Color.primary)
                .lineLimit(4)
        }
    }
}

func highlight(_ text: String, _ spans: [Span]) -> AttributedString {
    var a = AttributedString(text)
    for s in spans {
        if let r = Range(NSRange(location: s.location, length: s.length), in: a) {
            a[r].backgroundColor = Color.yellow.opacity(0.45)
            a[r].foregroundColor = Color.primary
            a[r].inlinePresentationIntent = .stronglyEmphasized
        }
    }
    return a
}
