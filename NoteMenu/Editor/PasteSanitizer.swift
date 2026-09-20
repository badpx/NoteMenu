import AppKit

/// 粘贴规则（EditorSpec §8）：图片拦截与富文本字体归一。
enum PasteSanitizer {
    /// 仅当剪贴板直接携带图像数据（截图/“拷贝图像”）或图像文件 URL（Finder 复制）时拦截；
    /// 其余（纯文本、富文本）走默认粘贴逻辑。
    /// 同一张图常以多种表示（public.png + public.tiff）同时存在于剪贴板，
    /// 只取第一种可解码的表示，避免一次粘贴插入多张相同的图。
    static func imagesOnPasteboard(_ pasteboard: NSPasteboard) -> [NSImage] {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data) {
                return [image]
            }
        }

        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
        ]
        var images: [NSImage] = []
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] {
            for url in urls {
                if let image = NSImage(contentsOf: url) {
                    images.append(image)
                }
            }
        }
        return images
    }

    /// 外部富文本粘贴的字体归一：统一为系统字体（保留粗/斜 trait；下划线/删除线/
    /// 列表段落样式不动），粗体大字号映射到编辑器标题档位（24/18px），等宽映射为代码字体。
    static func normalizeFonts(in range: NSRange, of storage: NSTextStorage) {
        guard range.length > 0 else { return }
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            guard let font = value as? NSFont else { return }
            let traits = NSFontManager.shared.traits(of: font)
            let newFont: NSFont
            if HTMLExporter.isCodeFont(font) {
                newFont = HTMLExporter.codeFont
            } else {
                var size = HTMLExporter.bodyFontSize
                if traits.contains(.boldFontMask) {
                    if font.pointSize >= HTMLExporter.h1FontSize - 1 {
                        size = HTMLExporter.h1FontSize
                    } else if font.pointSize >= HTMLExporter.h2FontSize - 1 {
                        size = HTMLExporter.h2FontSize
                    }
                }
                var converted = NSFont.systemFont(ofSize: size)
                if traits.contains(.boldFontMask) {
                    converted = NSFontManager.shared.convert(converted, toHaveTrait: .boldFontMask)
                }
                if traits.contains(.italicFontMask) {
                    converted = NSFontManager.shared.convert(converted, toHaveTrait: .italicFontMask)
                }
                newFont = converted
            }
            storage.addAttribute(.font, value: newFont, range: subrange)
        }
        storage.endEditing()
    }
}
