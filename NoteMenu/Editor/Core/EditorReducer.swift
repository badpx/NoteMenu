import Foundation

enum EditorCommand {
    case block(BlockKind)
    case list(ListKind)
    case toggle(InlineMarks)
    case indent(Int)
    case newline
    case backspaceAtStart
    case replace(NSRange, EditorDocument, preserveBlocks: Bool)
}

enum EditorReducer {
    @discardableResult
    static func apply(_ command: EditorCommand, to state: inout EditorSnapshot) -> Bool {
        let before = state
        let map = PositionMap(state.document)
        state.session.selection = map.clamped(state.session.selection)
        let selection = state.session.selection
        let indices = map.paragraphs(in: selection)
        switch command {
        case .block(let kind):
            guard kind.isValid else { return false }
            for i in indices {
                state.document.paragraphs[i].kind = kind
                for j in state.document.paragraphs[i].runs.indices { state.document.paragraphs[i].runs[j].style.font = nil }
            }
            resetInsertion(&state)
        case .list(let kind):
            let remove = indices.allSatisfy { state.document.paragraphs[$0].kind.list?.kind == kind }
            for i in indices {
                let depth = state.document.paragraphs[i].kind.list?.depth ?? 1
                state.document.paragraphs[i].kind = remove ? .body : .list(kind, depth)
                for j in state.document.paragraphs[i].runs.indices { state.document.paragraphs[i].runs[j].style.font = nil }
            }
            resetInsertion(&state)
        case .indent(let change):
            for i in indices {
                guard let list = state.document.paragraphs[i].kind.list else { continue }
                let depth = list.depth + change
                state.document.paragraphs[i].kind = depth < 1 ? .body : .list(list.kind, min(3, depth))
            }
        case .toggle(let mark):
            if selection.length == 0 {
                if state.session.insertionStyle.marks.contains(mark) { state.session.insertionStyle.marks.subtract(mark) }
                else { state.session.insertionStyle.marks.formUnion(mark) }
                state.session.explicitInsertionStyle = true
            } else {
                var selected: [InlineRun] = []
                for i in indices {
                    let r = NSIntersectionRange(selection, map.range(of: i))
                    selected += state.document.paragraphs[i].slice(NSRange(location: max(0, r.location - map.starts[i]), length: r.length))
                        .filter { $0.assetID == nil }
                }
                let remove = !selected.isEmpty && selected.allSatisfy { $0.style.marks.contains(mark) }
                transformRuns(in: selection, state: &state) { style in
                    if remove { style.marks.subtract(mark) } else { style.marks.formUnion(mark) }
                }
            }
        case .newline:
            if selection.length > 0 {
                state.document.replace(selection, with: .plain(""))
                state.session.selection.length = 0
            }
            let currentMap = PositionMap(state.document)
            let position = currentMap.position(at: state.session.selection.location)
            let paragraph = state.document.paragraphs[position.index]
            if paragraph.isEmpty, let list = paragraph.kind.list {
                state.document.paragraphs[position.index].kind = list.depth > 1 ? .list(list.kind, list.depth - 1) : .body
            } else if paragraph.isEmpty, case .heading = paragraph.kind {
                state.document.paragraphs[position.index].kind = .body
            } else {
                let next: BlockKind
                switch paragraph.kind {
                case .list: next = paragraph.kind
                case .codeLine: next = paragraph.isEmpty ? .body : .codeLine
                default: next = .body
                }
                let fragment = EditorDocument(paragraphs: [Paragraph(kind: paragraph.kind), Paragraph(kind: next)])
                state.document.replace(state.session.selection, with: fragment, preserveBlocks: true)
                if next != paragraph.kind {
                    for j in state.document.paragraphs[position.index + 1].runs.indices {
                        state.document.paragraphs[position.index + 1].runs[j].style.font = nil
                    }
                }
                state.session.selection.location += 1
            }
            resetInsertion(&state)
        case .backspaceAtStart:
            let position = map.position(at: selection.location)
            guard selection.length == 0, position.offset == 0 else { return false }
            let kind = state.document.paragraphs[position.index].kind
            switch kind {
            case .body: return false
            case .list(let type, let depth): state.document.paragraphs[position.index].kind = depth > 1 ? .list(type, depth - 1) : .body
            default: state.document.paragraphs[position.index].kind = .body
            }
            for j in state.document.paragraphs[position.index].runs.indices { state.document.paragraphs[position.index].runs[j].style.font = nil }
            resetInsertion(&state)
        case .replace(let range, let fragment, let preserve):
            let safe = map.clamped(range)
            state.document.replace(safe, with: fragment, preserveBlocks: preserve)
            state.session.selection = NSRange(location: safe.location + fragment.length, length: 0)
        }
        return before != state
    }

    static func resetInsertion(_ state: inout EditorSnapshot) {
        state.session.insertionStyle = .plain
        state.session.explicitInsertionStyle = true
    }

    static func transformRuns(in range: NSRange, state: inout EditorSnapshot, transform: (inout InlineStyle) -> Void) {
        let map = PositionMap(state.document)
        for i in map.paragraphs(in: range) {
            let paragraph = state.document.paragraphs[i]
            let r = NSIntersectionRange(range, map.range(of: i))
            guard r.length > 0 else { continue }
            let start = r.location - map.starts[i]
            var middle = paragraph.slice(NSRange(location: start, length: r.length))
            for j in middle.indices where middle[j].assetID == nil { transform(&middle[j].style) }
            state.document.paragraphs[i].runs = Paragraph.coalesced(
                paragraph.slice(NSRange(location: 0, length: start)) + middle +
                paragraph.slice(NSRange(location: start + r.length, length: paragraph.length - start - r.length)))
        }
    }
}
