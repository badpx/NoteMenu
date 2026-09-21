import AppKit
import Foundation
import OSAKit

/// Saves through Notes' AppleScript API without changing focus or using the clipboard.
enum NotesSaver {
    struct NoteContent {
        let bodyHTML: String
        /// One image per occurrence, in the same order as HTMLExporter.imagePlaceholder.
        let images: [NSImage]
    }

    enum SaveResult: Equatable {
        case success
        case unauthorized(String)
        case failed(String)
    }

    struct ScriptError: LocalizedError {
        let number: Int
        let message: String
        var errorDescription: String? { message }
    }

    static func runScript(_ source: String) throws -> String {
        guard let language = OSALanguage(forName: "AppleScript"), language.isThreadSafe else {
            throw ScriptError(number: 0, message: "系统 AppleScript 引擎不支持后台执行")
        }
        // Own the language instance for this invocation: never share a script component
        // across threads. Apple events originate from NoteMenu, using its sandbox/TCC
        // permissions, rather than from an external osascript process.
        let instance = OSALanguageInstance(language: language)
        let script = OSAScript(source: source, from: nil, languageInstance: instance, using: [])
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            throw ScriptError(number: error[OSAScriptErrorNumber] as? Int ?? 0,
                              message: error[OSAScriptErrorMessage] as? String ?? "备忘录保存失败")
        }
        return result?.stringValue ?? ""
    }

    static func save(_ content: NoteContent) -> SaveResult {
        save(content, execute: runScript)
    }

    /// Injection keeps automated failure tests out of the user's Notes database.
    static func save(_ content: NoteContent, execute: (String) throws -> String,
                     temporaryRoot: URL = FileManager.default.temporaryDirectory,
                     verificationAttempts: Int = 20) -> SaveResult {
        let fm = FileManager.default
        let directory = temporaryRoot.appendingPathComponent("NoteMenu-\(UUID().uuidString)", isDirectory: true)
        var preserveFiles = false
        var noteID: String?
        defer { if !preserveFiles { try? fm.removeItem(at: directory) } }
        do {
            var payloads: [Data] = []
            var paths: [String] = []
            if !content.images.isEmpty { try fm.createDirectory(at: directory, withIntermediateDirectories: true) }
            for (i, image) in content.images.enumerated() {
                guard let data = pngData(for: image) else { throw ScriptError(number: 0, message: "无法编码图片附件") }
                let file = directory.appendingPathComponent("image-\(i).png")
                try data.write(to: file, options: .atomic)
                payloads.append(data)
                paths.append(file.path)
            }
            let html = try resolveHTML(content.bodyHTML, imagePaths: paths)
            // Acquire the note ID before any attachment work so later failures can roll back.
            // On an ambiguous create error, retain sources rather than assuming no note exists.
            preserveFiles = !paths.isEmpty
            let id = try execute(makeScript(bodyHTML: html.initial))
            guard !id.isEmpty else { throw ScriptError(number: 0, message: "备忘录未返回笔记标识，请检查是否已创建笔记") }
            noteID = id
            if !paths.isEmpty {
                _ = try execute(attachmentScript(noteID: id, html: html.final, paths: paths))
                let exports = paths.indices.map { directory.appendingPathComponent("verify-\($0).png") }
                var verified = false
                let deadline = Date().addingTimeInterval(8)
                for attempt in 0..<max(1, verificationAttempts) {
                    for file in exports { try? fm.removeItem(at: file) }
                    do {
                        _ = try execute(verificationScript(noteID: id, exports: exports))
                        verified = zip(exports, payloads).allSatisfy { (try? Data(contentsOf: $0.0)) == $0.1 }
                    } catch let error as ScriptError where error.number == -1743 { throw error }
                    catch { /* Import may still be finishing; retry within a bounded window. */ }
                    if verified || Date() >= deadline { break }
                    if attempt + 1 < verificationAttempts { Thread.sleep(forTimeInterval: 0.1) }
                }
                guard verified else { throw ScriptError(number: 0, message: "图片附件完整性校验失败，草稿已保留") }
            }
            preserveFiles = false
            return .success
        } catch {
            var detail = error.localizedDescription
            if let id = noteID {
                do {
                    _ = try execute("with timeout of 10 seconds\ntell application \"Notes\" to delete note id \(quote(id))\nend timeout")
                    preserveFiles = false
                } catch {
                    detail += "；未能移除未完成笔记，请先检查备忘录，避免重试产生重复笔记"
                }
            }
            if preserveFiles { detail += "；图片临时文件保留在 \(directory.path)" }
            if let error = error as? ScriptError, error.number == -1743 { return .unauthorized(detail) }
            return .failed(detail)
        }
    }

    static func resolveHTML(_ html: String, imagePaths: [String]) throws -> (initial: String, final: String) {
        var initial = html
        var final = html
        for (i, path) in imagePaths.enumerated() {
            let marker = HTMLExporter.imagePlaceholder(i)
            guard final.components(separatedBy: marker).count == 2 else {
                throw ScriptError(number: 0, message: "图片与正文位置不一致，未保存")
            }
            initial = initial.replacingOccurrences(of: marker, with: "")
            let url = HTMLExporter.escape(URL(fileURLWithPath: path).absoluteString).replacingOccurrences(of: "\"", with: "&quot;")
            final = final.replacingOccurrences(of: marker, with: "<img src=\"\(url)\">")
        }
        guard !final.contains("<!--NoteMenuImage:") else {
            throw ScriptError(number: 0, message: "图片数据缺失，未保存")
        }
        return (initial, final)
    }

    static func quote(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Pure-text creation stays a single background AppleEvent transaction.
    static func makeScript(bodyHTML: String) -> String {
        """
        with timeout of 30 seconds
            tell application "Notes"
                set newNote to make new note at default folder of default account with properties {body:\(quote(bodyHTML))}
                return id of newNote
            end tell
        end timeout
        """
    }

    static func attachmentScript(noteID: String, html: String, paths: [String]) -> String {
        var lines = ["with timeout of 30 seconds", "tell application \"Notes\"", "set newNote to note id \(quote(noteID))"]
        for path in paths {
            lines.append("make new attachment at newNote with data (POSIX file \(quote(path)))")
        }
        // Local files must first be handed to Notes via its attachment API. Replacing the
        // body then imports exactly the requested occurrences; no name-based deduplication.
        lines.append("set body of newNote to \(quote(html))")
        lines += ["end tell", "end timeout"]
        return lines.joined(separator: "\n")
    }

    static func verificationScript(noteID: String, exports: [URL]) -> String {
        var lines = ["with timeout of 5 seconds", "tell application \"Notes\"", "set n to note id \(quote(noteID))",
                     "if (count of attachments of n) is not \(exports.count) then error \"图片数量不一致\""]
        for (i, file) in exports.enumerated() {
            lines.append("save attachment \(i + 1) of n in POSIX file \(quote(file.path))")
        }
        lines += ["end tell", "end timeout"]
        return lines.joined(separator: "\n")
    }

    static func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
