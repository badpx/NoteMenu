import AppKit

/// 列表几何与编号：纯函数（EditorSpec §6）。不含任何状态，全部离线可测。
enum ListLayout {
    /// 每级缩进（headIndent = indentPerLevel × level）。
    static let indentPerLevel: CGFloat = 22
    /// 最大嵌套层级。
    static let maxLevel = 3
    /// 标记右缘与排水区右缘的距离。
    static let markerTrailingGap: CGFloat = 4

    static func headIndent(level: Int) -> CGFloat {
        indentPerLevel * CGFloat(max(0, min(level, maxLevel)))
    }

    /// 无序标记按层级：L1 • / L2 ◦ / L3 ▪；有序各级均为 "N."。
    static func markerText(ordered: Bool, number: Int, level: Int) -> String {
        if ordered { return "\(number)." }
        switch level {
        case 2: return "◦"
        case 3: return "▪"
        default: return "•"
        }
    }

    /// 每个段落的列表序号（各级独立从 1 计数；深入新层级重排、回到浅层截断更深层、
    /// 被非列表段落打断后清零）。非列表段落为 nil。
    static func numbers(for formats: [ParagraphFormat]) -> [Int?] {
        var result: [Int?] = []
        var counters: [Int] = []
        var formatsStack: [Bool] = []  // 每层是否有序

        for format in formats {
            guard format.isList else {
                counters.removeAll()
                formatsStack.removeAll()
                result.append(nil)
                continue
            }
            let level = min(format.listLevel, maxLevel)
            if counters.count > level {
                counters = Array(counters.prefix(level))
                formatsStack = Array(formatsStack.prefix(level))
            }
            while counters.count < level {
                counters.append(0)
                formatsStack.append(format.ordered)
            }
            if formatsStack[level - 1] == format.ordered {
                counters[level - 1] += 1
            } else {
                counters[level - 1] = 1
                formatsStack[level - 1] = format.ordered
            }
            result.append(counters[level - 1])
        }
        return result
    }
}
