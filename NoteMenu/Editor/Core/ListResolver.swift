import Foundation

enum ListResolver {
    static let maxDepth = 8
    static let unorderedMarkers = ["●", "○", "◆", "◇", "■", "□", "▲", "△"]

    struct Item: Equatable {
        var index: Int
        var kind: ListKind
        var depth: Int
        var exportDepth: Int
        var number: Int
        var marker: String { kind == .ordered ? "\(number)." : ListResolver.unorderedMarkers[depth - 1] }
    }
    private struct Level { var depth: Int; var kind: ListKind; var number: Int }

    static func resolve(_ document: EditorDocument) -> [Int: Item] {
        var levels: [Level] = []
        var result: [Int: Item] = [:]
        for (i, paragraph) in document.paragraphs.enumerated() {
            guard let list = paragraph.kind.list else { levels.removeAll(); continue }
            while let last = levels.last, last.depth > list.depth { levels.removeLast() }
            if let last = levels.last, last.depth == list.depth {
                if last.kind == list.kind { levels[levels.count - 1].number += 1 }
                else { levels[levels.count - 1] = Level(depth: list.depth, kind: list.kind, number: 1) }
            } else { levels.append(Level(depth: list.depth, kind: list.kind, number: 1)) }
            result[i] = Item(index: i, kind: list.kind, depth: list.depth, exportDepth: levels.count, number: levels.last!.number)
        }
        return result
    }
}
