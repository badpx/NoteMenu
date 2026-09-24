import SwiftUI
import UniformTypeIdentifiers

struct NoteEditorView: View {
    @Environment(\.displayScale) private var displayScale
    @StateObject private var model: NoteEditorModel
    @State private var isPinned: Bool
    @State private var isSaveHovered = false
    @FocusState private var saveFocused: Bool
    @State private var presentingMenuOrSheet = false
    @State private var showSavedNotice = false
    @State private var savedNoticeGeneration = 0
    @State private var folders: [NotesFolder] = []
    @State private var targetFolder: NotesFolder? = FolderCatalog.target
    @State private var catalogState: CatalogState = .loading

    private enum CatalogState {
        case loading, loaded
        case failed(message: String, unauthorized: Bool)
    }

    private let folderLoader: () throws -> [NotesFolder]
    private let onClose: () -> Void
    private let onPinChanged: (Bool) -> Void
    private let onSaved: () -> Void

    init(
        isPinned: Bool,
        onClose: @escaping () -> Void,
        onPinChanged: @escaping (Bool) -> Void,
        onSaved: @escaping () -> Void,
        model: NoteEditorModel = NoteEditorModel(),
        saveAction: ((NotesSaver.NoteContent) -> NotesSaver.SaveResult)? = nil,
        initialFolder: NotesFolder? = FolderCatalog.target,
        folderLoader: @escaping () throws -> [NotesFolder] = { try FolderCatalog.fetch() }
    ) {
        _isPinned = State(initialValue: isPinned)
        self.onClose = onClose
        self.onPinChanged = onPinChanged
        self.onSaved = onSaved
        self._model = StateObject(wrappedValue: model)
        self.saveAction = saveAction
        self.folderLoader = folderLoader
        self._targetFolder = State(initialValue: initialFolder)
    }

    private let saveAction: ((NotesSaver.NoteContent) -> NotesSaver.SaveResult)?

    var body: some View {
        VStack(spacing: 0) {
            header
            Color(nsColor: EditorAppearance.separator).frame(height: 1 / displayScale)
            RichTextEditor(model: model, onSend: send)
                .background(Color(nsColor: EditorAppearance.canvas))
                .overlay { EditorTipOverlay(tips: model.tips) }
            Color(nsColor: EditorAppearance.separator).frame(height: 1 / displayScale)
            toolbar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: EditorAppearance.chrome))
        .clipShape(RoundedRectangle(cornerRadius: EditorAppearance.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: EditorAppearance.cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: EditorAppearance.outline), lineWidth: 1 / displayScale)
                .allowsHitTesting(false)
        }
        .background(TipWindowObserver(tips: model.tips, bridge: model.bridge).frame(width: 0, height: 0))
        .onChange(of: model.isSaving) { _ in updateTipBlocking() }
        .onChange(of: showSavedNotice) { _ in updateTipBlocking() }
        .onChange(of: presentingMenuOrSheet) { _ in updateTipBlocking() }
        .onChange(of: saveFocused) { model.tips.saveFocus($0) }
        .onDisappear { model.tips.endSession() }
        .onReceive(model.tips.activityEvents) { showSavedNotice = false }
        .onAppear {
            if let message = model.recoveryMessage {
                let alert = NSAlert()
                alert.messageText = EditorLanguage.text("无法恢复草稿", "Unable to Restore Draft")
                alert.informativeText = message
                alert.runModal()
            }
            reloadCatalog()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            Text("NoteMenu")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(nsColor: EditorAppearance.title))
            if model.isSaving {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
                    .accessibilityHint(EditorLanguage.text("正在保存至备忘录…", "Saving to Notes…"))
                    .accessibilityLabel(EditorLanguage.text("正在保存至备忘录", "Saving to Notes"))
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
                            ? Color(nsColor: EditorAppearance.selectedForeground)
                            : Color(nsColor: EditorAppearance.secondary))
                }
                .buttonStyle(.borderless)
                .modifier(FormatControlHover())
                .accessibilityLabel(isPinned ? EditorLanguage.text("取消置顶", "Unpin") : EditorLanguage.text("置顶", "Keep on Top"))
                .accessibilityHint(EditorLanguage.text("点击窗口外时保持打开", "Keep the window open when clicking outside"))
                Button {
                    showSavedNotice = false
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color(nsColor: EditorAppearance.secondary))
                }
                .buttonStyle(.borderless)
                .modifier(FormatControlHover())
                .accessibilityLabel(EditorLanguage.text("关闭输入窗口", "Close Editor"))
                .accessibilityHint(EditorLanguage.text("草稿会保留", "Your draft will be kept"))
            }
        }
        .padding(.horizontal, EditorAppearance.horizontalInset)
        .frame(height: EditorAppearance.headerHeight)
        .overlay {
            if showSavedNotice {
                ViewThatFits(in: .horizontal) {
                    Text(EditorLanguage.text("已保存至系统备忘录", "Saved to Apple Notes")).fixedSize()
                    Text(EditorLanguage.text("已保存", "Saved")).fixedSize()
                }
                    .accessibilityLabel(EditorLanguage.text("已保存至系统备忘录", "Saved to Apple Notes"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .lineLimit(1)
                    .padding(.leading, 130)
                    .padding(.trailing, 84)
                    .allowsHitTesting(false)
            }
        }
        .task(id: savedNoticeGeneration) {
            guard showSavedNotice else { return }
            do { try await Task.sleep(nanoseconds: 2_000_000_000) }
            catch { return }
            showSavedNotice = false
        }
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            Button(action: showBlockMenu) {
                Text("#").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(nsColor: EditorAppearance.secondary))
                    .modifier(FormatControlHover())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(EditorLanguage.text("段落样式", "Paragraph Style"))
            .accessibilityHint(EditorLanguage.text("段落样式", "Paragraph Style"))
            Button(action: showInlineMenu) {
                Text(verbatim: "Aa")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(Color(nsColor: EditorAppearance.secondary))
                    .modifier(FormatControlHover())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(EditorLanguage.text("字体样式", "Text Style"))
            .accessibilityHint(EditorLanguage.text("字体样式", "Text Style"))

            Button {
                model.toggleList(.unordered)
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(model.selectedBlock?.list?.kind == .unordered ? Color(nsColor: EditorAppearance.selectedForeground) : Color(nsColor: EditorAppearance.secondary))
                    .modifier(FormatControlHover())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(EditorLanguage.text("项目符号列表", "Bulleted List"))

            Button {
                model.toggleList(.ordered)
            } label: {
                Image(systemName: "list.number")
                    .foregroundStyle(model.selectedBlock?.list?.kind == .ordered ? Color(nsColor: EditorAppearance.selectedForeground) : Color(nsColor: EditorAppearance.secondary))
                    .modifier(FormatControlHover())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(EditorLanguage.text("编号列表", "Numbered List"))

            Button(action: chooseImages) {
                Image(systemName: "photo")
                    .foregroundStyle(Color(nsColor: EditorAppearance.secondary))
                    .modifier(FormatControlHover())
            }
            .buttonStyle(.borderless)
            .accessibilityHint(EditorLanguage.text("添加图片", "Add Image"))
            .accessibilityLabel(EditorLanguage.text("添加图片", "Add Image"))

            Spacer(minLength: 4)

            Color(nsColor: EditorAppearance.separator)
                .frame(width: 1 / displayScale, height: 20)

            FolderFolderButton(
                name: targetFolder?.name ?? EditorLanguage.text("默认", "Default"),
                isSelected: targetFolder != nil,
                fullName: targetFolder.map { EditorLanguage.text("保存目录：\($0.name)", "Save folder: \($0.name)") } ?? EditorLanguage.text("保存目录：默认文件夹", "Save folder: Default")
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
                        ? Color(nsColor: EditorAppearance.disabledForeground)
                        : Color(nsColor: EditorAppearance.saveForeground))
                    .frame(width: 40, height: 28)
                    .background(saveBackgroundColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.borderless)
            .disabled(model.isEmpty && !model.isComposing)
            .focused($saveFocused)
            .onHover {
                isSaveHovered = $0
                model.tips.saveHover($0)
            }
            .overlay(alignment: .bottomTrailing) {
                SaveShortcutTip(tips: model.tips).offset(y: -34)
            }
            .animation(.easeOut(duration: 0.12), value: isSaveHovered)
            .accessibilityLabel(EditorLanguage.text("存至备忘录", "Save to Notes"))
            .accessibilityHint(model.isEmpty
                ? EditorLanguage.text("输入内容后可保存", "Add content to save a note")
                : EditorLanguage.text("Command 加 Return", "Command Return"))
        }
        .padding(.horizontal, EditorAppearance.horizontalInset)
        .frame(height: EditorAppearance.toolbarHeight)
        .disabled(model.isSaving)
    }

    /// SwiftUI Menu bridges to NSPopUpButton and ignores the label's hover and hit-area
    /// modifiers. Use a Button for the visible control, then present the native menu.
    private func showBlockMenu() {
        let menu = NSMenu()
        var targets: [MenuActionTarget] = []
        for (title, kind) in [
            (EditorLanguage.text("一级标题", "Heading"), BlockKind.heading(1)),
            (EditorLanguage.text("正文", "Body"), .body),
            (EditorLanguage.text("代码块", "Code Block"), .codeLine),
        ] {
            menu.addItem(Self.makeItem(title, state: model.selectedBlock == kind ? .on : .off, targets: &targets) {
                model.setBlock(kind)
            })
        }
        popUp(menu, keepingAlive: targets)
    }

    private func showInlineMenu() {
        let menu = NSMenu()
        var targets: [MenuActionTarget] = []
        menu.addItem(Self.makeItem(EditorLanguage.text("加粗", "Bold"), state: model.isActive(.bold) ? .on : .off, targets: &targets) { model.toggleBold() })
        menu.addItem(Self.makeItem(EditorLanguage.text("斜体", "Italic"), state: model.isActive(.italic) ? .on : .off, targets: &targets) { model.toggleItalic() })
        menu.addItem(Self.makeItem(EditorLanguage.text("下划线", "Underline"), state: model.isActive(.underline) ? .on : .off, targets: &targets) { model.toggleUnderline() })
        menu.addItem(Self.makeItem(EditorLanguage.text("删除线", "Strikethrough"), state: model.isActive(.strike) ? .on : .off, targets: &targets) { model.toggleStrike() })
        popUp(menu, keepingAlive: targets)
    }

    /// Use the same native menu presentation for the toolbar's format and folder buttons.
    private func showFolderMenu() {
        let menu = NSMenu()
        var targets: [MenuActionTarget] = []
        switch catalogState {
        case .loading:
            menu.addItem(Self.makeItem(EditorLanguage.text("正在读取备忘录目录…", "Loading Notes folders…"), enabled: false, targets: &targets))
        case .failed(let message, let unauthorized):
            menu.addItem(Self.makeItem(EditorLanguage.text("读取目录失败，点按重试", "Couldn’t Load Folders — Retry"), targets: &targets) {
                self.retryCatalog(message: message, unauthorized: unauthorized)
            })
        case .loaded:
            for item in Self.buildFolderMenuItems(
                folders: folders,
                targetFolder: targetFolder,
                targets: &targets,
                select: { folder in self.selectFolder(folder) }
            ) {
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(Self.makeItem(EditorLanguage.text("重新载入目录", "Reload Folders"), targets: &targets) { self.reloadCatalog() })
        popUp(menu, keepingAlive: targets)
    }

    private func popUp(_ menu: NSMenu, keepingAlive targets: [MenuActionTarget]) {
        presentingMenuOrSheet = true
        model.tips.setBlocked(true)
        defer { presentingMenuOrSheet = false; updateTipBlocking() }
        // popUp 阻塞至菜单关闭，targets 在此期间保持存活（NSMenuItem.target 是弱引用）。
        _ = withExtendedLifetime(targets) {
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

        items.append(makeItem(EditorLanguage.text("默认文件夹", "Default Folder"), state: target == nil ? .on : .off, targets: &targets) {
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
            let result = Result { try folderLoader() }
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
        presentingMenuOrSheet = true
        model.tips.setBlocked(true)
        let picker = NSOpenPanel()
        picker.title = EditorLanguage.text("添加图片", "Add Image")
        picker.prompt = EditorLanguage.text("插入", "Insert")
        picker.allowedContentTypes = [.image]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        picker.beginSheetModal(for: window) { response in
            defer { presentingMenuOrSheet = false; updateTipBlocking() }
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
                    alert.messageText = EditorLanguage.text("无法读取图片", "Unable to Read Image")
                    alert.informativeText = EditorLanguage.text("无法打开“\(url.lastPathComponent)”，请检查文件是否可用或选择其他图片。", "Couldn’t open “\(url.lastPathComponent)”. Check the file or choose another image.")
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
        if model.isEmpty && !model.isComposing { return Color(nsColor: EditorAppearance.disabledBackground) }
        return isSaveHovered
            ? Color(nsColor: EditorAppearance.saveHover)
            : Color(nsColor: EditorAppearance.save)
    }

    private func updateTipBlocking() {
        model.tips.setBlocked(model.isSaving || showSavedNotice || presentingMenuOrSheet)
    }

    private func send() {
        guard !model.isSaving, !model.isEmpty, !model.isComposing else { return }
        model.tips.activity()
        model.tips.setBlocked(true)
        showSavedNotice = false
        model.saveAsync(using: saveAction ?? NotesSaver.save) { result in
            defer { updateTipBlocking() }
            switch result {
            case .success:
                targetFolder = FolderCatalog.target
                showSavedNotice = true
                savedNoticeGeneration += 1
                DispatchQueue.main.async { onSaved() }
            case .unauthorized(let message):
                showError(message: message, unauthorized: true)
            case .failed(let message):
                showError(message: message, unauthorized: false)
            }
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
        model.tips.setBlocked(true)
        defer { updateTipBlocking() }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        if unauthorized {
            alert.messageText = EditorLanguage.text("尚未获得控制「备忘录」的权限", "Permission to Control Notes Required")
            alert.informativeText = message + EditorLanguage.text("\n\n请在系统设置中允许 NoteMenu 控制「备忘录」后重试。", "\n\nAllow NoteMenu to control Notes in System Settings, then try again.")
            alert.addButton(withTitle: EditorLanguage.text("打开系统设置", "Open System Settings"))
            alert.addButton(withTitle: EditorLanguage.text("取消", "Cancel"))
            let response = alert.runModal()
            if response == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        } else {
            alert.messageText = EditorLanguage.text("保存到备忘录失败", "Unable to Save to Notes")
            alert.informativeText = message
            alert.addButton(withTitle: EditorLanguage.text("好", "OK"))
            alert.runModal()
        }
    }
}

/// Apply inside a toolbar control's label so its hover background is also in the click target.
private struct FormatControlHover: ViewModifier {
    var width: CGFloat? = 28
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .frame(width: width, height: 28)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered && isEnabled ? Color(nsColor: EditorAppearance.hover) : Color.clear)
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
                    .foregroundStyle(Color(nsColor: EditorAppearance.secondary))
                Text(NoteEditorView.truncatedFolderName(name))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: EditorAppearance.secondary))
                    .lineLimit(1)
                    .frame(width: 56, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color(nsColor: EditorAppearance.secondary))
            }
            .padding(.horizontal, 6)
            .modifier(FormatControlHover(width: nil))
        }
        .buttonStyle(.borderless)
        .accessibilityHint(fullName)
        .accessibilityLabel(EditorLanguage.text("选择保存目录", "Choose Save Folder"))
    }
}

/// NSMenuItem 闭包 action 的 target 桥（NSMenuItem.target 为弱引用，由调用方保活）。
final class MenuActionTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run(_ sender: Any?) { action() }
}
