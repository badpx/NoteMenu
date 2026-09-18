import SwiftUI

struct NoteEditorView: View {
    @StateObject private var model = NoteEditorModel()
    @State private var isPinned: Bool

    private let onClose: () -> Void
    private let onPinChanged: (Bool) -> Void
    private let onSaved: () -> Void

    init(
        isPinned: Bool,
        onClose: @escaping () -> Void,
        onPinChanged: @escaping (Bool) -> Void,
        onSaved: @escaping () -> Void
    ) {
        _isPinned = State(initialValue: isPinned)
        self.onClose = onClose
        self.onPinChanged = onPinChanged
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            RichTextEditor(model: model)
            Divider()
            toolbar
        }
        .frame(width: 340, height: 400)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .padding(.vertical, 10)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Menu {
                Button("加粗") { model.toggleBold() }
                Button("斜体") { model.toggleItalic() }
                Button("下划线") { model.toggleUnderline() }
            } label: {
                Image(systemName: "textformat")
                    .foregroundStyle(Color.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 30)
            .help("字体样式")

            Button {
                model.toggleList(.disc)
            } label: {
                Image(systemName: "list.bullet")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("项目符号列表")

            Button {
                model.toggleList(.decimal)
            } label: {
                Image(systemName: "list.number")
                    .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.borderless)
            .help("编号列表")

            if !model.images.isEmpty {
                Label("\(model.images.count)", systemImage: "photo")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
                    .help("已收集的图片将在保存时作为附件添加到备忘录")
            }

            Spacer()

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(nsColor: .systemGray))
            }
            .buttonStyle(.borderless)
            .disabled(model.isEmpty)
            .help("保存到备忘录")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func send() {
        guard let content = model.exportContent() else { return }
        switch NotesSaver.save(content) {
        case .success:
            model.clear()
            onSaved()
        case .unauthorized(let message):
            showError(message: message, unauthorized: true)
        case .failed(let message):
            showError(message: message, unauthorized: false)
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
