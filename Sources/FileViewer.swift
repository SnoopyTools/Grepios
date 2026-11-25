import SwiftUI

struct FileViewer: View {
    let target: LineTarget
    let regex: NSRegularExpression?

    @State private var lines: [String] = []
    @State private var loaded = false
    @State private var loadError: String?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(lines.indices, id: \.self) { i in
                        row(i).id(i + 1)
                    }
                }
                .padding(.vertical, 8)
            }
            .onChange(of: loaded) { _, isLoaded in
                guard isLoaded else { return }
                DispatchQueue.main.async { proxy.scrollTo(target.line, anchor: .center) }
            }
        }
        .overlay {
            if !loaded { ProgressView() }
            if let loadError { ContentUnavailableView("Can't open file", systemImage: "exclamationmark.triangle",
                                                      description: Text(loadError)) }
        }
        .navigationTitle(target.file.url.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { UIPasteboard.general.string = target.file.url.path } label: {
                        Label("Copy Path", systemImage: "link")
                    }
                    Button { UIPasteboard.general.string = lines.joined(separator: "\n") } label: {
                        Label("Copy Contents", systemImage: "doc.on.doc")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .task { await load() }
    }

    private func row(_ i: Int) -> some View {
        let number = i + 1
        let text = lines[i]
        let spans = regex.map { GrepEngine.spans(in: text, regex: $0) } ?? []
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .trailing)
            Text(highlight(text.isEmpty ? " " : text, spans))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(number == target.line ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    private func load() async {
        guard !loaded else { return }
        let root = target.file.root
        let url = target.file.url
        let result: Result<[String], Error> = await Task.detached {
            let ok = root.startAccessingSecurityScopedResource()
            defer { if ok { root.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                return .success(GrepEngine.splitLines(String(decoding: data, as: UTF8.self)))
            } catch {
                return .failure(error)
            }
        }.value
        switch result {
        case .success(let l): lines = l
        case .failure(let e): loadError = e.localizedDescription
        }
        loaded = true
    }
}
