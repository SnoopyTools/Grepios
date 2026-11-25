import Foundation

// MARK: - Options

struct GrepOptions: Codable, Equatable {
    var ignoreCase = false        // -i
    var fixedString = false       // -F
    var wholeWord = false         // -w
    var invert = false            // -v
    var recursive = true          // -r
    var includeHidden = false
    var skipBinary = true         // -I
    var contextLines = 0          // -C
    var maxMatchesPerFile = 0     // -m (0 = unlimited)
    var includeGlob = ""          // --include, e.g. "*.swift, *.txt"
    var excludeGlob = ""          // --exclude
    var maxFileSizeMB = 50
}

// MARK: - Results

struct Span: Hashable {
    let location: Int   // UTF-16 offset
    let length: Int
}

struct ResultLine: Identifiable, Hashable {
    enum Kind: Hashable { case match, context, separator }
    let id = UUID()
    let number: Int
    let text: String
    let spans: [Span]
    let kind: Kind
}

struct FileResult: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let root: URL          // security-scoped root this file lives under
    let displayPath: String
    let lines: [ResultLine]
    let matchCount: Int

    static func == (a: FileResult, b: FileResult) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum GrepEvent {
    case file(FileResult)
    case progress(scanned: Int)
    case finished(scanned: Int, truncated: Bool)
}

enum GrepError: LocalizedError {
    case emptyPattern
    case invalidPattern(String)

    var errorDescription: String? {
        switch self {
        case .emptyPattern: return "Enter a pattern to search for."
        case .invalidPattern(let p): return "Invalid regular expression: \(p)"
        }
    }
}

// MARK: - Engine

enum GrepEngine {
    static let maxDisplayLineLength = 2000

    static func makeRegex(_ pattern: String, _ o: GrepOptions) throws -> NSRegularExpression {
        guard !pattern.isEmpty else { throw GrepError.emptyPattern }
        var p = o.fixedString ? NSRegularExpression.escapedPattern(for: pattern) : pattern
        if o.wholeWord { p = "\\b(?:\(p))\\b" }
        var opts: NSRegularExpression.Options = []
        if o.ignoreCase { opts.insert(.caseInsensitive) }
        do { return try NSRegularExpression(pattern: p, options: opts) }
        catch { throw GrepError.invalidPattern(pattern) }
    }

    /// Splits on \n and \r\n (Swift treats \r\n as one Character).
    static func splitLines(_ s: String) -> [String] {
        var lines = s.split(omittingEmptySubsequences: false,
                            whereSeparator: { $0 == "\n" || $0 == "\r\n" }).map(String.init)
        if lines.last == "" { lines.removeLast() }
        return lines
    }

    static func spans(in line: String, regex: NSRegularExpression) -> [Span] {
        let len = (line as NSString).length
        return regex.matches(in: line, range: NSRange(location: 0, length: len))
            .filter { $0.range.length > 0 }
            .map { Span(location: $0.range.location, length: $0.range.length) }
    }

    static func globs(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == " " })
            .map(String.init).filter { !$0.isEmpty }
    }

    static func matchesAny(_ name: String, _ globs: [String]) -> Bool {
        globs.contains { fnmatch($0, name, 0) == 0 }
    }

    static func relativePath(_ url: URL, root: URL) -> String {
        let r = root.standardizedFileURL.resolvingSymlinksInPath().path
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        if p.hasPrefix(r + "/") {
            return root.lastPathComponent + "/" + String(p.dropFirst(r.count + 1))
        }
        return url.lastPathComponent
    }

    private static func displayLine(_ number: Int, _ text: String, _ spans: [Span], _ kind: ResultLine.Kind) -> ResultLine {
        let ns = text as NSString
        guard ns.length > maxDisplayLineLength else {
            return ResultLine(number: number, text: text, spans: spans, kind: kind)
        }
        let cut = ns.rangeOfComposedCharacterSequence(at: maxDisplayLineLength - 1).location
        let kept = spans.filter { $0.location + $0.length <= cut }
        return ResultLine(number: number, text: ns.substring(to: cut) + " …", spans: kept, kind: kind)
    }

    /// Searches one file. Returns nil if nothing selected or file unreadable/binary.
    static func searchFile(_ url: URL, root: URL, regex: NSRegularExpression, options o: GrepOptions) -> FileResult? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        if o.skipBinary, data.prefix(8192).contains(0) { return nil }
        let lines = splitLines(String(decoding: data, as: UTF8.self))

        var selected: [Int: [Span]] = [:]
        var order: [Int] = []
        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            let ms = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            if !ms.isEmpty != o.invert {
                selected[i] = o.invert ? [] : ms.filter { $0.range.length > 0 }
                    .map { Span(location: $0.range.location, length: $0.range.length) }
                order.append(i)
                if o.maxMatchesPerFile > 0 && order.count >= o.maxMatchesPerFile { break }
            }
        }
        guard !order.isEmpty else { return nil }

        let c = max(0, o.contextLines)
        var out: [ResultLine] = []
        var lastPrinted = -1
        for i in order {
            let start = max(0, i - c, lastPrinted + 1)
            if c > 0, lastPrinted >= 0, start > lastPrinted + 1 {
                out.append(ResultLine(number: 0, text: "--", spans: [], kind: .separator))
            }
            for j in start..<i { out.append(displayLine(j + 1, lines[j], [], .context)) }
            out.append(displayLine(i + 1, lines[i], selected[i] ?? [], .match))
            lastPrinted = i
            var j = i + 1
            while j < lines.count, j <= i + c, selected[j] == nil {
                out.append(displayLine(j + 1, lines[j], [], .context))
                lastPrinted = j
                j += 1
            }
        }
        return FileResult(url: url, root: root, displayPath: relativePath(url, root: root),
                          lines: out, matchCount: order.count)
    }

    /// Walks the roots synchronously. Uses nextObject() rather than for-in so it is safe to call from a Task.
    static func searchSync(regex: NSRegularExpression, roots: [URL], options o: GrepOptions, lineLimit: Int,
                           isCancelled: @escaping () -> Bool, emit: @escaping (GrepEvent) -> Void) {
        let include = globs(o.includeGlob)
        let exclude = globs(o.excludeGlob)
        let maxBytes = o.maxFileSizeMB * 1_048_576
        var scanned = 0, totalLines = 0, truncated = false
        let fm = FileManager.default

        outer: for root in roots {
            let access = root.startAccessingSecurityScopedResource()
            defer { if access { root.stopAccessingSecurityScopedResource() } }

            let handle: (URL) -> Bool = { url in
                if isCancelled() { return false }
                let name = url.lastPathComponent
                if !include.isEmpty && !matchesAny(name, include) { return true }
                if matchesAny(name, exclude) { return true }
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxBytes { return true }
                scanned += 1
                if let r = searchFile(url, root: root, regex: regex, options: o) {
                    totalLines += r.lines.count
                    emit(.file(r))
                    if totalLines >= lineLimit { truncated = true; return false }
                }
                if scanned % 50 == 0 { emit(.progress(scanned: scanned)) }
                return true
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: root.path, isDirectory: &isDir) else { continue }
            if !isDir.boolValue {
                if !handle(root) { break outer }
                continue
            }
            var eopts: FileManager.DirectoryEnumerationOptions = []
            if !o.includeHidden { eopts.insert(.skipsHiddenFiles) }
            if !o.recursive { eopts.insert(.skipsSubdirectoryDescendants) }
            guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                         options: eopts) else { continue }
            while let item = en.nextObject() as? URL {
                guard (try? item.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                if !handle(item) { break outer }
            }
        }
        emit(.finished(scanned: scanned, truncated: truncated))
    }

    static func run(pattern: String, roots: [URL], options: GrepOptions,
                    lineLimit: Int = 20_000) -> AsyncThrowingStream<GrepEvent, Error> {
        AsyncThrowingStream { cont in
            let task = Task.detached(priority: .userInitiated) {
                do {
                    let regex = try GrepEngine.makeRegex(pattern, options)
                    GrepEngine.searchSync(regex: regex, roots: roots, options: options, lineLimit: lineLimit,
                               isCancelled: { Task.isCancelled }, emit: { cont.yield($0) })
                    cont.finish()
                } catch {
                    cont.finish(throwing: error)
                }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}
