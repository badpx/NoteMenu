import SwiftUI
import UniformTypeIdentifiers

struct NoteEditorView: View {
    private static let barHeight: CGFloat = 36
    @StateObject private var model: NoteEditorModel
    @State private var isPinned: Bool
    @State private var isSaveHovered = false
    @State private var showSavedNotice = false
    @State private var folders: [NotesFolder] = []
    @State private var targetFolder: NotesFolder? = FolderCatalog.target
    @State private var catalogState: CatalogState = .loading

    private enum CatalogState {
        case loading, loaded
        case failed(message: String, unauthorized: Bool)
    }

    private let resizeHandler: PanelResizeHandler
    private let onClose: () -> Void
    private let onPinChanged: (Bool) -> Void
    private let onSaved: () -> Void

    init(
        isPinned: Bool,
        resizeHandler: PanelResizeHandler,
        onClose: @escaping () -> Void,
        onPinChanged: @escaping (Bool) -> Void,
        onSaved: @escaping () -> Void,
        model: NoteEditorModel = NoteEditorModel(),
        saveAction: ((NotesSaver.NoteContent) -> NotesSaver.SaveResult)? = nil
    ) {
        _isPinned = State(initialValue: isPinned)
        self.resizeHandler = resizeHandler
        self.onClose = onClose
        self.onPinChanged = onPinChanged
        self.onSaved = onSaved
        self._model = StateObject(wrappedValue: model)
        self.saveAction = saveAction
    }

    private let saveAction: ((NotesSaver.NoteContent) -> NotesSaver.SaveResult)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            RichTextEditor(model: model, onSend: send)
            Divider()
            toolbar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(resizeHandles)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onAppear {
            if let message = model.recoveryMessage {
                let alert = NSAlert()
                alert.messageText = "无法恢复草稿"
                alert.informativeText = message
                alert.runModal()
            }
            reloadCatalog()
        }
    }

    /// 边缘拖动热区：左、右、下边缘及两个底角。顶部用于拖动窗口位置。
    private var resizeHandles: some View {
        ZStack {
            HStack(spacing: 0) {
                resizeStrip(edges: [.left])
                    .frame(width: 6)
                Spacer()
                resizeStrip(edges: [.right])
                    .frame(width: 6)
            }
            VStack(spacing: 0) {
                Spacer()
                resizeStrip(edges: [.bottom])
                    .frame(height: 6)
            }
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 0) {
                    resizeStrip(edges: [.left, .bottom])
                        .frame(width: 18, height: 18)
                    Spacer()
                    resizeStrip(edges: [.right, .bottom])
                        .frame(width: 18, height: 18)
                }
            }
        }
    }

    private func resizeStrip(edges: PanelResizeHandler.Edges) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in resizeHandler.resize(edges: edges) }
                    .onEnded { _ in resizeHandler.endResize() }
            )
    }

    private var header: some View {
        HStack {
            Text("NoteMenu")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            if model.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
                    .help("正在保存至备忘录…")
                    .accessibilityLabel("正在保存至备忘录")
            }
            Spacer()
            HStack(spacing: 8) {
                Button {
                    isPinned.toggle()
                    onPinChanged(isPinned)
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(isPinned
                            ? Color(red: 251 / 255, green: 211 / 255, blue: 46 / 255)
                            : Color.secondary)
                }
                .buttonStyle(.borderless)
                .modifier(FormatControlHover())
                .help(isPinned ? "取消置顶" : "置顶")
                Button {
                    showSavedNotice = false
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.borderless)
                .modifier(FormatControlHover())
                .help("关闭")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.barHeight)
        .overlay {
            if showSavedNotice {
                Text("已保存至系统备忘录")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 64)
                    .allowsHitTesting(false)
            }
        }
        .task(id: showSavedNotice) {
            guard showSavedNotice else { return }
            do { try await Task.sleep(nanoseconds: 1_200_000_000) }
            catch { return }
            showSavedNotice = false
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Menu {
                blockButton("一级标题", kind: .heading(1))
                blockButton("正文", kind: .body)
                blockButton("代码块", kind: .codeLine)
            } label: {
                Text("#").font(.system(size: 16, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .modifier(FormatControlHover())
            .help("段落样式")
            Menu {
                Button(action: model.toggleBold) { Label("加粗", systemImage: model.isActive(.bold) ? "checkmark" : "bold") }
                Button(action: model.toggleItalic) { Label("斜体", systemImage: model.isActive(.italic) ? "checkmark" : "italic") }
                Button(action: model.toggleUnderline) { Label("下划线", systemImage: model.isActive(.underline) ? "checkmark" : "underline") }
                Button(action: model.toggleStrike) { Label("删除线", systemImage: model.isActive(.strike) ? "checkmark" : "strikethrough") }
            } label: {
                Image(systemName: "textformat")
                    .foregroundStyle(Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .modifier(FormatControlHover())
            .help("字体样式")

            Button {
                model.toggleList(.unordered)
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(model.selectedBlock?.list?.kind == .unordered ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .modifier(FormatControlHover())
            .help("项目符号列表")

            Button {
                model.toggleList(.ordered)
            } label: {
                Image(systemName: "list.number")
                    .foregroundStyle(model.selectedBlock?.list?.kind == .ordered ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .modifier(FormatControlHover())
            .help("编号列表")

            Button(action: chooseImages) {
                Image(systemName: "photo")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.borderless)
            .modifier(FormatControlHover())
            .help("添加图片")
            .accessibilityLabel("添加图片")

            Spacer()

            Divider()
                .frame(height: 15)
                .padding(.vertical, 6)

            FolderFolderButton(
                name: targetFolder?.name ?? "默认",
                isSelected: targetFolder != nil,
                fullName: targetFolder.map { "保存目录：\($0.name)" } ?? "保存目录：默认文件夹"
            ) {
                showFolderMenu()
            }

            Button(action: { model.bridge.requestSave() }) {
                Image("SaveNote")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(model.isEmpty && !model.isComposing
                        ? Color(nsColor: .secondaryLabelColor)
                        : Color(red: 92 / 255, green: 62 / 255, blue: 16 / 255))
                    .frame(width: 40, height: 24)
                    .background(saveBackgroundColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.borderless)
            .disabled(model.isEmpty && !model.isComposing)
            .onHover { isSaveHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isSaveHovered)
            .accessibilityLabel("存至备忘录")
            .help(targetFolder.map { "存至备忘录：\($0.name) (⌘ + Enter)" } ?? "存至备忘录(⌘ + Enter)")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.barHeight)
        .disabled(model.isSaving)
    }

    /// 以 NSMenu popUp 方式弹出目录选择菜单。
    /// 不用 SwiftUI Menu：macOS 上 .borderlessButton 样式会桥接为 AppKit NSPopUpButton，
    /// label 的 SwiftUI 布局修饰器（固定宽度 frame）被忽略，宽度随名称自适应（离屏实测证实）。
    private func showFolderMenu() {
        let menu = NSMenu()
        var targets: [MenuActionTarget] = []
        switch catalogState {
        case .loading:
            menu.addItem(Self.makeItem("正在读取备忘录目录…", enabled: false, targets: &targets))
        case .failed(let message, let unauthorized):
            menu.addItem(Self.makeItem("读取目录失败，点按重试", targets: &targets) {
                self.retryCatalog(message: message, unauthorized: unauthorized)
            })
        case .loaded:
            for item in Self.buildFolderMenuItems(
                folders: folders,
                targetFolder: targetFolder,
                targets: &targets
            ) { folder in
                self.selectFolder(folder)
            } {
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(Self.makeItem("重新载入目录", targets: &targets) { self.reloadCatalog() })
        // popUp 阻塞至菜单关闭，targets 在此期间保持存活（NSMenuItem.target 是弱引用）。
        withExtendedLifetime(targets) {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    /// 废纸篓文件夹（保存到废纸篓没有意义），中英文系统名都排除。
    static let trashedFolderNames: Set<String> = ["Recently Deleted", "最近删除"]

    static func isTrashedFolder(_ folder: NotesFolder) -> Bool {
        trashedFolderNames.contains(folder.name)
    }

    /// 构建目录选择菜单项（internal 以便离线断言结构）。规则：
    /// 过滤废纸篓；多账户才显示组标题（11px 灰字禁用项）且组间分隔线；
    /// 有组标题时文件夹项统一缩进一级（目录数据无层级信息）。
    static func buildFolderMenuItems(
        folders: [NotesFolder],
        targetFolder: NotesFolder?,
        targets: inout [MenuActionTarget],
        select: @escaping (NotesFolder?) -> Void
    ) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        // 选中项是废纸篓时按未选择兜底
        let target = targetFolder.flatMap { isTrashedFolder($0) ? nil : $0 }
        let visible = folders.filter { !isTrashedFolder($0) }

        items.append(makeItem("默认文件夹", state: target == nil ? .on : .off, targets: &targets) {
            select(nil)
        })

        var order: [String] = []
        var grouped: [String: [NotesFolder]] = [:]
        for folder in visible {
            if grouped[folder.accountName] == nil { order.append(folder.accountName) }
            grouped[folder.accountName, default: []].append(folder)
        }
        let groups = order.map { (account: $0, folders: grouped[$0] ?? []) }
        let showHeaders = groups.count > 1

        for (index, group) in groups.enumerated() {
            if showHeaders {
                if index > 0 { items.append(.separator()) }
                let header = NSMenuItem()
                header.attributedTitle = NSAttributedString(
                    string: group.account,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]
                )
                header.isEnabled = false
                items.append(header)
            }
            for folder in group.folders {
                let item = makeItem(folder.name, state: target == folder ? .on : .off, targets: &targets) {
                    select(folder)
                }
                item.indentationLevel = showHeaders ? 1 : 0
                items.append(item)
            }
        }
        return items
    }

    private static func makeItem(
        _ title: String,
        state: NSControl.StateValue = .off,
        enabled: Bool = true,
        targets: inout [MenuActionTarget],
        action: (() -> Void)? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = enabled
        item.state = state
        if let action {
            let target = MenuActionTarget(action)
            targets.append(target)
            item.target = target
            item.action = #selector(MenuActionTarget.run(_:))
        }
        return item
    }

    private func selectFolder(_ folder: NotesFolder?) {
        // 废纸篓不可作为保存目标（兜底为默认文件夹）
        let folder = folder.flatMap { Self.isTrashedFolder($0) ? nil : $0 }
        FolderCatalog.target = folder
        targetFolder = folder
    }

    private func reloadCatalog() {
        catalogState = .loading
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try FolderCatalog.fetch() }
            DispatchQueue.main.async {
                switch result {
                case .success(let list):
                    folders = list
                    catalogState = .loaded
                    // 保存目标失效（不存在或落在废纸篓）时回落到默认文件夹。
                    if let target = targetFolder,
                       Self.isTrashedFolder(target) || !list.contains(where: { $0.id == target.id }) {
                        selectFolder(nil)
                    }
                case .failure(let error):
                    let scriptError = error as? NotesSaver.ScriptError
                    catalogState = .failed(message: error.localizedDescription,
                                           unauthorized: scriptError?.number == -1743)
                }
            }
        }
    }

    private func retryCatalog(message: String, unauthorized: Bool) {
        if unauthorized { showError(message: message, unauthorized: true) }
        reloadCatalog()
    }

    private func chooseImages() {
        guard let textView = model.bridge.textView, let window = textView.window,
              window.attachedSheet == nil else { return }
        // Commit an active input-method candidate before remembering the insertion point.
        if textView.hasMarkedText() { textView.unmarkText() }
        let selection = model.bridge.state.session.selection
        let picker = NSOpenPanel()
        picker.title = "添加图片"
        picker.prompt = "插入"
        picker.allowedContentTypes = [.image]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        picker.beginSheetModal(for: window) { response in
            guard response == .OK else {
                window.makeFirstResponder(textView)
                return
            }
            var images: [NSImage] = []
            for url in picker.urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url), let image = NSImage(data: data),
                      image.isValid else {
                    let alert = NSAlert()
                    alert.messageText = "无法读取图片"
                    alert.informativeText = "无法打开“\(url.lastPathComponent)”，请检查文件是否可用或选择其他图片。"
                    alert.beginSheetModal(for: window) { _ in window.makeFirstResponder(textView) }
                    return
                }
                images.append(image)
            }
            model.bridge.select(selection)
            model.bridge.insertImages(images)
            window.makeFirstResponder(textView)
        }
    }

    private var saveBackgroundColor: Color {
        if model.isEmpty && !model.isComposing { return Color(nsColor: .quaternaryLabelColor) }
        return isSaveHovered
            ? Color(red: 225 / 255, green: 177 / 255, blue: 28 / 255)
            : Color(red: 251 / 255, green: 211 / 255, blue: 46 / 255)
    }

    private func send() {
        guard !model.isSaving else { return }
        showSavedNotice = false
        model.saveAsync(using: saveAction ?? NotesSaver.save) { result in
            switch result {
            case .success:
                targetFolder = FolderCatalog.target
                showSavedNotice = true
                DispatchQueue.main.async { onSaved() }
            case .unauthorized(let message):
                showError(message: message, unauthorized: true)
            case .failed(let message):
                showError(message: message, unauthorized: false)
            }
        }
    }

    private func blockButton(_ title: String, kind: BlockKind) -> some View {
        Button { model.setBlock(kind) } label: {
            if model.selectedBlock == kind { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }

    /// 文件夹名称截断：最多 4 个中文字符宽（全角=1 单位、ASCII=0.5 单位），
    /// 超出部分尾部截断加「…」，保证长名称不撑开工具栏。
    static func truncatedFolderName(_ name: String, maxUnits: Double = 4) -> String {
        var units = 0.0
        var result = ""
        for ch in name {
            let unit = ch.isASCII ? 0.5 : 1.0
            if units + unit > maxUnits { return result + "…" }
            units += unit
            result.append(ch)
        }
        return name
    }

    private func showError(message: String, unauthorized: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        if unauthorized {
            alert.messageText = "尚未获得控制「备忘录」的权限"
            alert.informativeText = message + "\n\n请在系统设置中允许 NoteMenu 控制「备忘录」后重试。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.messageText = "保存到备忘录失败"
            alert.informativeText = message
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }
}

private struct FormatControlHover: ViewModifier {    var width: CGFloat? = 28
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .frame(width: width, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered && isEnabled
                        ? Color.primary.opacity(0.08)
                        : Color.clear)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

/// 文件夹选择控件：普通 Button + NSMenu popUp（见 showFolderMenu 注释）。
/// label 布局完全由 SwiftUI 控制，名称区固定 56pt 左对齐，控件总宽度对任意名称恒定。
struct FolderFolderButton: View {
    let name: String
    let isSelected: Bool
    let fullName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                Text(NoteEditorView.truncatedFolderName(name))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .frame(width: 56, alignment: .leading)
            }
            .padding(.leading, 6)
        }
        .buttonStyle(.borderless)
        .modifier(FormatControlHover(width: nil))
        .help(fullName)
        .accessibilityLabel("选择保存目录")
    }
}

/// NSMenuItem 闭包 action 的 target 桥（NSMenuItem.target 为弱引用，由调用方保活）。
final class MenuActionTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run(_ sender: Any?) { action() }
}
