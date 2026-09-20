import Foundation

enum MarkdownTriggerEngine {
    enum Plan { case block(NSRange, BlockKind); case inline(NSRange, Int, InlineMarks) }

    static func plan(in state: EditorSnapshot, inserted: String) -> Plan? {
        guard state.session.selection.length == 0, !inserted.isEmpty else { return nil }
        let map = PositionMap(state.document)
        let cursor = map.position(at: state.session.selection.location)
        let paragraph = state.document.paragraphs[cursor.index]
        guard !paragraph.kind.isCode else { return nil }
        let prefix = (paragraph.text as NSString).substring(to: cursor.offset)
        if inserted.hasSuffix(" "), paragraph.kind.list == nil {
            let block: BlockKind?
            switch prefix {
            case "# ": block = .heading(1)
            case "## ": block = .heading(2)
            case "### ": block = .heading(3)
            case "- ", "* ": block = .list(.unordered, 1)
            case "``` ": block = .codeLine
            default:
                block = prefix.range(of: "^[1-9][0-9]?\\. $", options: .regularExpression) != nil ? .list(.ordered, 1) : nil
            }
            if let block { return .block(NSRange(location: map.starts[cursor.index], length: cursor.offset), block) }
        }
        guard let last = prefix.last, ["*", "_", "~", "`"].contains(last), inserted.last == last else { return nil }
        let units = Array(prefix.utf16)
        guard let marker = String(last).utf16.first else { return nil }
        var closingStart = units.count - 1
        while closingStart > 0 && units[closingStart - 1] == marker { closingStart -= 1 }
        let width = units.count - closingStart
        let mark: InlineMarks
        switch (last, width) {
        case ("*", 2), ("_", 2): mark = .bold
        case ("*", 1), ("_", 1): mark = .italic
        case ("~", 2): mark = .strike
        case ("`", 1): mark = .code
        default: return nil
        }
        var i = closingStart - 1
        while i >= 0 {
            guard units[i] == marker else { i -= 1; continue }
            let end = i + 1
            while i >= 0 && units[i] == marker { i -= 1 }
            let start = i + 1
            guard end - start == width else { continue }
            let contentRange = NSRange(location: end, length: closingStart - end)
            guard contentRange.length > 0 else { return nil }
            let content = (prefix as NSString).substring(with: contentRange)
            guard let first = content.unicodeScalars.first, let lastScalar = content.unicodeScalars.last,
                  !CharacterSet.whitespacesAndNewlines.contains(first), !CharacterSet.whitespacesAndNewlines.contains(lastScalar),
                  !content.utf16.contains(marker), !content.contains("\u{FFFC}") else { return nil }
            if start > 0 {
                let before = (prefix as NSString).substring(to: start)
                guard let scalar = before.unicodeScalars.last,
                      CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).contains(scalar) else { return nil }
            }
            let span = NSRange(location: start, length: units.count - start)
            guard !paragraph.slice(span).contains(where: { $0.style.marks.contains(.code) }) else { return nil }
            return .inline(NSRange(location: map.starts[cursor.index] + start, length: span.length), width, mark)
        }
        return nil
    }

    static func apply(_ plan: Plan, to state: inout EditorSnapshot) {
        switch plan {
        case .block(let range, let kind):
            state.document.replace(range, with: .plain(""))
            state.session.selection = NSRange(location: range.location, length: 0)
            EditorReducer.apply(.block(kind), to: &state)
        case .inline(let range, let width, let mark):
            let content = NSRange(location: range.location + width, length: range.length - width * 2)
            var fragment = state.document.fragment(in: content)
            for i in fragment.paragraphs.indices {
                for j in fragment.paragraphs[i].runs.indices { fragment.paragraphs[i].runs[j].style.marks.formUnion(mark) }
            }
            state.document.replace(range, with: fragment)
            state.session.selection = NSRange(location: range.location + fragment.length, length: 0)
            EditorReducer.resetInsertion(&state)
        }
    }
}
