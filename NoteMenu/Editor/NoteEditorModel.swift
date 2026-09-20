import AppKit
import SwiftUI

final class NoteEditorModel: ObservableObject {
    let bridge: AppKitInputBridge
    let drafts: DraftStore
    private var pendingPersist: DispatchWorkItem?
    private var lastPersistRevision: UInt64?
    private(set) var recoveryMessage: String?
    @Published private(set) var isSaving = false
    private static let saveQueue = DispatchQueue(label: "NoteMenu.save", qos: .userInitiated)

    init(drafts: DraftStore = DraftStore(), restore: Bool = true) {
        self.bridge = AppKitInputBridge()
        self.drafts = drafts
        if restore {
            do { if let document = try drafts.restore() { bridge.load(document, session: drafts.restoredSession) } }
            catch { recoveryMessage = "草稿读取失败，原文件已保留：\(error.localizedDescription)" }
        }
        bridge.onChange = { [weak self] in
            guard let self else { return }
            self.objectWillChange.send()
            guard !self.bridge.isComposing, self.lastPersistRevision != self.bridge.document.revision else { return }
            self.lastPersistRevision = self.bridge.document.revision
            self.pendingPersist?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.persistDraft() }
            self.pendingPersist = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
    }

    var isEmpty: Bool { !bridge.document.canSend }
    var images: [NSImage] { bridge.document.assetOrder.compactMap { bridge.document.assets[$0].flatMap { NSImage(data: $0.data) } } }
    var attachmentCount: Int { bridge.document.assetOrder.count }
    var isComposing: Bool { bridge.isComposing }
    var selectedBlock: BlockKind? {
        let indices = PositionMap(bridge.document).paragraphs(in: bridge.state.session.selection)
        let first = bridge.document.paragraphs[indices.lowerBound].kind
        return indices.allSatisfy { bridge.document.paragraphs[$0].kind == first } ? first : nil
    }
    func isActive(_ mark: InlineMarks) -> Bool {
        let selection = bridge.state.session.selection
        if selection.length == 0 { return bridge.state.session.insertionStyle.marks.contains(mark) }
        let runs = bridge.document.fragment(in: selection).paragraphs.flatMap(\.runs).filter { $0.assetID == nil }
        return !runs.isEmpty && runs.allSatisfy { $0.style.marks.contains(mark) }
    }

    func toggleBold() { bridge.execute(.toggle(.bold), name: "粗体") }
    func toggleItalic() { bridge.execute(.toggle(.italic), name: "斜体") }
    func toggleUnderline() { bridge.execute(.toggle(.underline), name: "下划线") }
    func toggleStrike() { bridge.execute(.toggle(.strike), name: "删除线") }
    func setBlock(_ kind: BlockKind) { bridge.execute(.block(kind), name: "段落样式") }
    func toggleList(_ kind: ListKind) { bridge.execute(.list(kind), name: "列表") }

    func exportContent() -> NotesSaver.NoteContent? {
        guard !bridge.isComposing, !isEmpty else { return nil }
        let result = HTMLExporter.export(bridge.document)
        return NotesSaver.NoteContent(bodyHTML: result.bodyHTML, images: images)
    }

    @discardableResult
    func save(using writer: (NotesSaver.NoteContent) -> NotesSaver.SaveResult = NotesSaver.save) -> NotesSaver.SaveResult? {
        guard let content = exportContent() else { return nil }
        let revision = bridge.document.revision
        let result = writer(content)
        if result == .success, bridge.document.revision == revision { clear() }
        return result
    }

    func clear() {
        pendingPersist?.cancel(); pendingPersist = nil
        bridge.load(EditorDocument())
        persistDraft()
    }

    func saveAsync(using writer: @escaping (NotesSaver.NoteContent) -> NotesSaver.SaveResult = NotesSaver.save,
                   completion: @escaping (NotesSaver.SaveResult) -> Void) {
        guard !isSaving, let content = exportContent() else { return }
        let revision = bridge.document.revision
        isSaving = true
        Self.saveQueue.async {
            let result = autoreleasepool { writer(content) }
            DispatchQueue.main.async {
                if result == .success, self.bridge.document.revision == revision { self.clear() }
                self.isSaving = false
                completion(result)
            }
        }
    }

    func persistDraft() {
        pendingPersist?.cancel(); pendingPersist = nil
        // During composition the bridge still exposes only the last committed document.
        drafts.persist(bridge.document, session: bridge.state.session)
    }

    func flushPendingPersist() {
        if pendingPersist != nil { persistDraft() }
        drafts.flush()
    }

    deinit { pendingPersist?.cancel() }
}
