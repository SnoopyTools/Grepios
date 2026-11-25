import Foundation
import SwiftUI

struct SearchRoot: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let isDirectory: Bool
}

@MainActor
final class SearchModel: ObservableObject {
    @Published var pattern = ""
    @Published var options: GrepOptions { didSet { saveOptions() } }
    @Published private(set) var roots: [SearchRoot] = []
    @Published private(set) var results: [FileResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var scanned = 0
    @Published private(set) var hasSearched = false
    @Published private(set) var truncated = false
    @Published var errorMessage: String?
    private(set) var activeRegex: NSRegularExpression?

    private var task: Task<Void, Never>?
    private var generation = UUID()

    static let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    private let optionsKey = "grepOptions"
    private let rootsKey = "rootBookmarks"

    init() {
        if let d = UserDefaults.standard.data(forKey: optionsKey),
           let o = try? JSONDecoder().decode(GrepOptions.self, from: d) {
            options = o
        } else {
            options = GrepOptions()
        }
        loadRoots()
        seedWelcomeFile()
    }

    // MARK: Derived

    var totalMatches: Int { results.reduce(0) { $0 + $1.matchCount } }

    var scopeDescription: String {
        roots.isEmpty ? "App Documents" : roots.map(\.url.lastPathComponent).joined(separator: ", ")
    }

    var statusText: String {
        if isSearching { return "Searching… \(scanned) files scanned" }
        guard hasSearched else { return "Ready" }
        var s = "\(totalMatches) \(totalMatches == 1 ? "match" : "matches") in \(results.count) \(results.count == 1 ? "file" : "files") · \(scanned) scanned"
        if truncated { s += " · results capped" }
        return s
    }

    /// grep-style text: path:line:text for matches, path-line-text for context.
    var exportText: String {
        var out: [String] = []
        for f in results {
            for l in f.lines {
                switch l.kind {
                case .match: out.append("\(f.displayPath):\(l.number):\(l.text)")
                case .context: out.append("\(f.displayPath)-\(l.number)-\(l.text)")
                case .separator: out.append("--")
                }
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: Search

    func start() {
        task?.cancel()
        errorMessage = nil
        guard !pattern.isEmpty else { return }
        do { activeRegex = try GrepEngine.makeRegex(pattern, options) }
        catch { errorMessage = error.localizedDescription; return }

        results = []
        scanned = 0
        truncated = false
        isSearching = true
        hasSearched = true

        let gen = UUID()
        generation = gen
        let urls = roots.isEmpty ? [Self.documentsURL] : roots.map(\.url)
        let stream = GrepEngine.run(pattern: pattern, roots: urls, options: options)

        task = Task { [weak self] in
            do {
                for try await ev in stream {
                    guard let self, self.generation == gen else { return }
                    switch ev {
                    case .file(let r): self.results.append(r)
                    case .progress(let n): self.scanned = n
                    case .finished(let n, let t): self.scanned = n; self.truncated = t
                    }
                }
            } catch {
                if self?.generation == gen { self?.errorMessage = error.localizedDescription }
            }
            if self?.generation == gen { self?.isSearching = false }
        }
    }

    func stop() {
        task?.cancel()
        isSearching = false
    }

    func rerunIfNeeded() {
        if hasSearched && !pattern.isEmpty { start() }
    }

    // MARK: Roots (persisted as bookmarks)

    func addRoots(_ urls: [URL]) {
        for url in urls where !roots.contains(where: { $0.url == url }) {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            roots.append(SearchRoot(url: url, isDirectory: isDir))
        }
        saveRoots()
    }

    func removeRoots(at offsets: IndexSet) {
        roots.remove(atOffsets: offsets)
        saveRoots()
    }

    private func saveRoots() {
        let data: [Data] = roots.compactMap { root in
            let ok = root.url.startAccessingSecurityScopedResource()
            defer { if ok { root.url.stopAccessingSecurityScopedResource() } }
            return try? root.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        UserDefaults.standard.set(data, forKey: rootsKey)
    }

    private func loadRoots() {
        guard let list = UserDefaults.standard.array(forKey: rootsKey) as? [Data] else { return }
        roots = list.compactMap { d in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: d, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            else { return nil }
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return SearchRoot(url: url, isDirectory: isDir)
        }
    }

    private func saveOptions() {
        if let d = try? JSONEncoder().encode(options) { UserDefaults.standard.set(d, forKey: optionsKey) }
    }

    private func seedWelcomeFile() {
        let key = "seededWelcome"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let text = """
        Welcome to grepios — grep for iOS.
        Try searching for "grep" or the regex  ^W\\w+
        Drop files into Files > On My iPhone > grepios to search them here,
        or tap the folder row to add any folder from the Files app.
        TODO: search something interesting
        """
        try? text.write(to: Self.documentsURL.appendingPathComponent("Welcome.txt"), atomically: true, encoding: .utf8)
    }
}
