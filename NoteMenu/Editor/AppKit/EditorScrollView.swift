import AppKit

/// SwiftUI assigns the viewport size after the restored draft has entered text storage.
/// Reconcile the document height once the viewport has its real dimensions.
final class EditorScrollView: NSScrollView {
    override func layout() {
        super.layout()
        (documentView as? EditorTextView)?.updateDocumentHeight()
    }
}
