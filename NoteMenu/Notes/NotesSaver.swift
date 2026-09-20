import AppKit
import Foundation

/// 通过 AppleScript 把笔记写入系统「备忘录」。
/// 正文为白名单 HTML，首行作标题；图片先落盘临时文件再以附件形式追加。
enum NotesSaver {
    struct NoteContent {
        let bodyHTML: String
        let images: [NSImage]
    }

    enum SaveResult: Equatable {
        case success
        case unauthorized(String)
        case failed(String)
    }

    static func save(_ content: NoteContent) -> SaveResult {
        var imagePaths: [String] = []
        defer {
            for path in imagePaths { try? FileManager.default.removeItem(atPath: path) }
        }
        for image in content.images {
            guard let png = pngData(for: image) else { return .failed("无法编码图片附件") }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("NoteMenu-\(UUID().uuidString).png")
            do {
                try png.write(to: url)
                imagePaths.append(url.path)
            } catch {
                return .failed("图片写入临时文件失败：\(error.localizedDescription)")
            }
        }
        let script = Self.makeScript(
            bodyHTML: content.bodyHTML,
            imagePaths: imagePaths
        )

        var errorDictionary: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return .failed("无法创建备忘录保存脚本") }
        appleScript.executeAndReturnError(&errorDictionary)

        guard let errorDictionary else { return .success }

        let number = (errorDictionary[NSAppleScript.errorNumber] as? Int) ?? 0
        let message = (errorDictionary[NSAppleScript.errorMessage] as? String) ?? "未知错误（\(number)）"
        // -1743: errAEEventNotPermitted，用户尚未授权本 App 控制备忘录。
        if number == -1743
            || message.localizedCaseInsensitiveContains("not authorized")
            || message.contains("不允许") {
            return .unauthorized(message)
        }
        return .failed(message)
    }

    /// AppleScript 字符串字面量转义。
    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// 组装写入备忘录的 AppleScript。
    static func makeScript(bodyHTML: String, imagePaths: [String]) -> String {
        var lines = [
            "tell application \"Notes\"",
            "    tell folder \"Notes\" of default account",
            "        set newNote to make new note with properties {body:\"\(escape(bodyHTML))\"}",
        ]
        for path in imagePaths {
            lines.append("        make new attachment at newNote with data (POSIX file \"\(escape(path))\")")
        }
        if !imagePaths.isEmpty {
            // macOS 26 的 Notes 会把每次 make new attachment 复制成两张相邻同名附件；
            // 临时文件名按 UUID 生成必然互不相同，故相邻同名即重复副本，从尾部往前删除。
            // 在旧系统上无重复（相邻名称不同），此逻辑为空操作。
            lines.append("        set attachmentNames to name of every attachment of newNote")
            lines.append("        repeat with i from (count of attachmentNames) to 2 by -1")
            lines.append("            if (item i of attachmentNames) = (item (i - 1) of attachmentNames) then")
            lines.append("                delete attachment i of newNote")
            lines.append("            end if")
            lines.append("        end repeat")
        }
        lines.append("    end tell")
        lines.append("end tell")
        return lines.joined(separator: "\n")
    }

    /// NSImage → PNG 数据（粘贴入编辑区与写出临时文件共用）。
    static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
