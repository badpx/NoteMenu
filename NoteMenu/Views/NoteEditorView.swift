import SwiftUI

struct NoteEditorView: View {
    private static let barHeight: CGFloat = 36
    @StateObject private var model: NoteEditorModel
    @State private var isPinned: Bool
    @State private var isSaveHovered = false

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
        }
    }

    /// 边缘拖动热区：左、右、下边缘及两个底角。顶部吸附菜单栏，不支持调整。
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
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button {
                isPinned.toggle()
                onPinChanged(isPinned)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(isPinned ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help(isPinned ? "取消置顶" : "置顶")
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("关闭")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.barHeight)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Menu {
                blockButton("标题 1", kind: .heading(1))
                blockButton("标题 2", kind: .heading(2))
                blockButton("标题 3", kind: .heading(3))
                blockButton("正文", kind: .body)
                blockButton("代码块", kind: .codeLine)
            } label: {
                Text("#").font(.system(size: 16, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
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
            .frame(width: 30)
            .help("字体样式")

            Button {
                model.toggleList(.unordered)
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(model.selectedBlock?.list?.kind == .unordered ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("项目符号列表")

            Button {
                model.toggleList(.ordered)
            } label: {
                Image(systemName: "list.number")
                    .foregroundStyle(model.selectedBlock?.list?.kind == .ordered ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("编号列表")

            if model.attachmentCount > 0 {
                Label("\(model.attachmentCount)", systemImage: "photo")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .help("已收集的图片将在保存时作为附件添加到备忘录")
            }

            Spacer()

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
            .help("存至备忘录(⌘ + Enter)")
        }
        .padding(.horizontal, 12)
        .frame(height: Self.barHeight)
    }

    private var saveBackgroundColor: Color {
        if model.isEmpty && !model.isComposing { return Color(nsColor: .quaternaryLabelColor) }
        return isSaveHovered
            ? Color(red: 225 / 255, green: 177 / 255, blue: 28 / 255)
            : Color(red: 251 / 255, green: 211 / 255, blue: 46 / 255)
    }

    private func send() {
        guard let result = model.save(using: saveAction ?? NotesSaver.save) else { return }
        switch result {
        case .success:
            onSaved()
        case .unauthorized(let message):
            showError(message: message, unauthorized: true)
        case .failed(let message):
            showError(message: message, unauthorized: false)
        }
    }

    private func blockButton(_ title: String, kind: BlockKind) -> some View {
        Button { model.setBlock(kind) } label: {
            if model.selectedBlock == kind { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
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
