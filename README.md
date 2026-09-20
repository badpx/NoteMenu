# NoteMenu

一个常驻 macOS 菜单栏的快速笔记录入工具：点击菜单栏图标弹出录入窗口，写完后一键保存到系统「备忘录」。

A lightweight macOS menu bar app for quickly jotting down notes and saving them to Apple Notes with one click.

## 功能

- **菜单栏常驻**：点击状态栏图标展开/收起录入浮窗，无 Dock 图标打扰
- **富文本录入**：加粗、斜体、下划线、删除线、行内代码，标题（H1/H2/H3）与代码块段落样式，项目符号/编号列表（Tab/Shift+Tab 三级嵌套）
- **Markdown 自动转换**：输入标志即时转格式，标记即转即消——`# `/`## `/`### ` 标题，`- `/`* `/`1. ` 列表，` ``` ` 代码块，`**粗体**`/`__粗体__`、`*斜体*`/`_斜体_`、`~~删除线~~`、`` `行内代码` ``
- **图片附件**：可直接粘贴或拖入图片，保存时作为备忘录附件（系统通道限制，集中在笔记末尾）
- **一键保存**：⌘↩ 或点击发送，保存到系统备忘录后自动清空录入窗口，首行自动作为笔记标题
- **撤销/重做**：⌘Z / ⇧⌘Z 全链路支持（含自动转换与格式操作）
- **草稿保留**：未保存的内容在浮窗收起或退出后自动保留，下次打开恢复
- **置顶模式**：置顶后浮窗不随点击外部收起，方便对照其他窗口整理内容
- **开机自启**：右键菜单栏图标可开关登录时自动启动（基于 SMAppService）

## 快捷键

| 键 | 作用 |
|---|---|
| ⌘B / ⌘I / ⌘U / ⇧⌘X | 加粗 / 斜体 / 下划线 / 删除线 |
| ⌘↩ | 保存到备忘录 |
| ⌘Z / ⇧⌘Z | 撤销 / 重做 |
| Tab / Shift+Tab | 列表项层级升降（最外层 Shift+Tab 退出列表） |
| Enter | 列表项空行先提升一层、再按退出列表；标题/代码块回车回正文 |
| Backspace（段落首） | 标题/代码块降级为正文；列表项提升/退出 |

编辑器行为规范详见 `docs/EditorSpec.md`。

## 系统要求

- macOS 13 或更高版本
- 首次保存笔记时，需要在系统弹窗中允许 NoteMenu 控制「备忘录」（可在 系统设置 → 隐私与安全性 → 自动化 中管理）

## 构建

需要 Xcode 16 或更高版本：

```bash
xcodebuild -project NoteMenu.xcodeproj -scheme NoteMenu -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/NoteMenu.app
```

或直接用 Xcode 打开 `NoteMenu.xcodeproj` 运行。

## 技术说明

- SwiftUI + AppKit：`NSStatusItem` + `NSPanel` 浮窗承载 SwiftUI 界面
- 编辑器：`Editor/` 模块架构——`EditorDocument` 段落模型为格式单一真值（含空段落），`EditorCore` 为唯一格式写入口，`KeyEventRouter` 实现键盘交互矩阵，`MarkdownTriggers`/`ListLayout` 为纯函数，`MarkerRenderer` 基于 NSLayoutManager 行片段矩形自绘列表标记，`PasteSanitizer`/`UndoSupport` 各司其职；`EditorTextView` 仅作薄壳
- 写入备忘录：备忘录无公开 API，通过 AppleScript（`make new note` / `make new attachment`）实现，正文使用自写的白名单 HTML 导出（`h1/h2/b/i/u/strike/tt/pre/ul/ol/li/div`）
- 沙盒：开启 App Sandbox，通过 `com.apple.security.temporary-exception.apple-events` 获得控制备忘录的权限

## License

MIT
