import AppKit
import Foundation

/// 通过 AppleScript 把笔记写入系统「备忘录」。
/// 正文为白名单 HTML，首行作标题；图片先落盘临时文件再以附件形式追加。
enum NotesSaver {
    struct NoteContent {
        let title: String
        let bodyHTML: String
        let images: [NSImage]
    }

    enum SaveResult {
        case success
        case unauthorized(String)
        case failed(String)
    }

    static func save(_ content: NoteContent) -> SaveResult {
        var imagePaths: [String] = []
        for image in content.images {
            guard let png = pngData(for: image) else { continue }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("NoteMenu-\(UUID().uuidString).png")
            do {
                try png.write(to: url)
                imagePaths.append(url.path)
            } catch {
                return .failed("图片写入临时文件失败：\(error.localizedDescription)")
            }
        }
        defer {
            for path in imagePaths {
                try? FileManager.default.removeItem(atPath: path)
            }
        }

        var lines = [
            "tell application \"Notes\"",
            "    tell folder \"Notes\" of default account",
            "        set newNote to make new note with properties {name:\"\(escape(content.title))\", body:\"\(escape(content.bodyHTML))\"}",
        ]
        for path in imagePaths {
            lines.append("        make new attachment at newNote with data (POSIX file \"\(escape(path))\")")
        }
        lines.append("    end tell")
        lines.append("end tell")

        var errorDictionary: NSDictionary?
        let script = NSAppleScript(source: lines.joined(separator: "\n"))
        script?.executeAndReturnError(&errorDictionary)

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

    /// NSImage → PNG 数据（粘贴入编辑区与写出临时文件共用）。
    static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
