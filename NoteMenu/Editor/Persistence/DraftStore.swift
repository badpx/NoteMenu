import AppKit

/// A versioned, self-contained atomic envelope avoids half-written manifest/asset pairs.
final class DraftStore {
    struct Envelope: Codable {
        var version = 1
        var document: EditorDocument
        var session: EditorSession?
    }
    let directory: URL
    var url: URL { directory.appendingPathComponent("draft-v1.json") }
    var legacyURL: URL { directory.appendingPathComponent("draft.rtfd") }
    private let queue = DispatchQueue(label: "NoteMenu.DraftStore")
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private(set) var lastError: Error?
    private(set) var restoredSession: EditorSession?
    private var damagedSource = false

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NoteMenu")) {
        self.directory = directory
    }

    func restore() throws -> EditorDocument? {
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
                guard envelope.version == 1 else { throw EditorDataError.unsupportedVersion }
                let document = try envelope.document.validated()
                guard document.assets.values.allSatisfy({ NSImage(data: $0.data) != nil }) else { throw EditorDataError.invalidDocument }
                if let session = envelope.session {
                    guard session.insertionStyle.marks.subtracting(.supported).isEmpty, session.affinity <= 1 else { throw EditorDataError.invalidDocument }
                    if let font = session.insertionStyle.font, ![12, 14, 18, 24].contains(font.size) { throw EditorDataError.invalidDocument }
                }
                restoredSession = envelope.session
                return document
            } catch {
                damagedSource = true
                lastError = error
                // Do not silently replace a damaged new draft with stale legacy content.
                throw error
            }
        }
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }
        let legacy: NSAttributedString
        if let wrapper = try? FileWrapper(url: legacyURL, options: .immediate), wrapper.isDirectory,
           let attributed = NSAttributedString(rtfdFileWrapper: wrapper, documentAttributes: nil) {
            legacy = attributed
        } else {
            let data = try Data(contentsOf: legacyURL)
            guard let attributed = NSAttributedString(rtfd: data, documentAttributes: nil) else { throw EditorDataError.invalidDocument }
            legacy = attributed
        }
        let document = ClipboardCodec.importRich(legacy)
        persist(document)
        flush()
        return document
    }

    func persist(_ document: EditorDocument, session: EditorSession? = nil) {
        lock.lock(); generation &+= 1; let token = generation; lock.unlock()
        var pruned = document
        pruned.pruneAssets()
        let snapshot = pruned
        queue.async { [self] in
            lock.lock(); let current = token == generation; lock.unlock()
            guard current else { return }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if damagedSource, FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.copyItem(at: url, to: directory.appendingPathComponent("draft-recovery-\(UUID().uuidString).json"))
                    damagedSource = false
                }
                let hasInputFormat = session.map { $0.insertionStyle != .plain } ?? false
                if snapshot.isPristine && !hasInputFormat {
                    if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                    // Retire the legacy source so it cannot resurrect after a successful clear.
                    if FileManager.default.fileExists(atPath: legacyURL.path) {
                        try FileManager.default.moveItem(at: legacyURL, to: directory.appendingPathComponent("draft-legacy-\(UUID().uuidString).rtfd"))
                    }
                } else {
                    let data = try JSONEncoder().encode(Envelope(document: snapshot, session: session))
                    try data.write(to: url, options: .atomic)
                }
                lastError = nil
            } catch { lastError = error }
        }
    }

    func flush() { queue.sync {} }
}
