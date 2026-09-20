import Foundation

struct PositionMap {
    struct Position { var index: Int; var offset: Int }
    let starts: [Int]
    let lengths: [Int]
    let length: Int

    init(_ document: EditorDocument) {
        var offset = 0
        var starts: [Int] = []
        for paragraph in document.paragraphs {
            starts.append(offset)
            offset += paragraph.length + 1
        }
        self.starts = starts
        self.lengths = document.paragraphs.map(\.length)
        self.length = max(0, offset - 1)
    }

    func position(at offset: Int) -> Position {
        let offset = min(max(0, offset), length)
        var low = 0, high = starts.count
        while low + 1 < high {
            let mid = (low + high) / 2
            if starts[mid] <= offset { low = mid } else { high = mid }
        }
        return Position(index: low, offset: min(lengths[low], offset - starts[low]))
    }

    func clamped(_ range: NSRange) -> NSRange {
        let location = min(max(0, range.location == NSNotFound ? length : range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }

    func paragraphs(in range: NSRange) -> ClosedRange<Int> {
        let range = clamped(range)
        return position(at: range.location).index...position(at: range.length == 0 ? range.location : NSMaxRange(range) - 1).index
    }

    func range(of index: Int, includingSeparator: Bool = false) -> NSRange {
        NSRange(location: starts[index], length: lengths[index] + (includingSeparator && index < starts.count - 1 ? 1 : 0))
    }
}
