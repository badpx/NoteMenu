import Foundation

/// Selection scopes follow list ancestry and treat adjacent code lines as one block.
enum SelectionExpander {
    static func scopes(in document: EditorDocument, at paragraphIndex: Int) -> [NSRange] {
        let map = PositionMap(document)
        let index = min(max(0, paragraphIndex), document.paragraphs.count - 1)
        var scopes: [NSRange] = []

        func append(_ first: Int, _ last: Int) {
            let start = map.starts[first]
            let end = NSMaxRange(map.range(of: last))
            let range = NSRange(location: start, length: end - start)
            if scopes.last != range { scopes.append(range) }
        }

        if let list = document.paragraphs[index].kind.list {
            func subtreeEnd(_ root: Int, depth: Int) -> Int {
                var end = root
                while end + 1 < document.paragraphs.count,
                      let next = document.paragraphs[end + 1].kind.list,
                      next.depth > depth {
                    end += 1
                }
                return end
            }

            append(index, index)

            // Walk the contiguous list backwards through successively shallower ancestors.
            // An orphaned level is its own root until a shallower item appears before it.
            var root = index
            var depth = list.depth
            var candidate = index
            while candidate > 0 {
                candidate -= 1
                guard let previous = document.paragraphs[candidate].kind.list else { break }
                if previous.depth < depth {
                    root = candidate
                    depth = previous.depth
                }
            }
            if root != index {
                append(root, subtreeEnd(root, depth: depth))
            }
        } else if document.paragraphs[index].kind.isCode {
            var first = index
            var last = index
            while first > 0, document.paragraphs[first - 1].kind.isCode { first -= 1 }
            while last + 1 < document.paragraphs.count, document.paragraphs[last + 1].kind.isCode { last += 1 }
            append(first, last)
        } else {
            append(index, index)
        }

        append(0, document.paragraphs.count - 1)
        return scopes
    }
}
