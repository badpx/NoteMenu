# NoteMenu

一个常驻 macOS 菜单栏的快速笔记录入工具：点击菜单栏图标弹出录入窗口，写完后一键保存到系统「备忘录」。

A lightweight macOS menu bar app for quickly jotting down notes and saving them to Apple Notes with one click.

## 功能

- **菜单栏常驻**：点击状态栏图标展开/收起录入浮窗，无 Dock 图标打扰
- **快捷呼起**：按全局快捷键 ⌃⌘N（Control + Command + N）展开/收起录入窗口，已有草稿会保留；也可点击右键菜单顶部的“新建笔记”打开并聚焦录入窗口
- **打开备忘录**：按全局快捷键 ⌃⌘O（Control + Command + O），或在菜单栏图标右键菜单中选择“打开备忘录”，即可启动或切换到系统备忘录
- **富文本录入**：支持三级标题、加粗、斜体、下划线、删除线、代码行，以及八级项目符号和编号列表；支持规范限定的 Markdown 输入快捷语法
- **图片附件**：可直接粘贴或拖入图片，保存时作为备忘录附件
- **一键保存**：保存成功后自动清空录入窗口，保留首段格式，标题由系统备忘录派生
- **草稿恢复**：文字、空段落格式和原始图片自动保存，兼容导入旧 RTFD 草稿
- **置顶模式**：置顶后浮窗不随点击外部收起，方便对照其他窗口整理内容
- **开机自启**：右键菜单栏图标可开关登录时自动启动（基于 SMAppService）

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

- SwiftUI + AppKit：`NSStatusItem` + `NSPanel` 浮窗承载 SwiftUI 界面；编辑器使用语义文档模型、统一编辑命令和原生 `NSTextView` / TextKit 投影
- 写入备忘录：通过 AppleScript（`make new note` / `make new attachment`）实现，正文直接从模型导出为规范白名单 HTML，图片按顺序追加为附件
- 草稿：应用支持目录下的 `NoteMenu/draft-v1.json` 原子保存模型、输入格式和图片；旧 `draft.rtfd` 迁移源会保留，清空时移为备份以免旧稿恢复
- 沙盒：开启 App Sandbox，通过 `com.apple.security.temporary-exception.apple-events` 获得控制备忘录的权限
- 图标：彩色应用图标原图保存在 `assets/notemenu-app-icon.png`，各尺寸资源位于 `NoteMenu/Resources/Assets.xcassets/AppIcon.appiconset`；菜单栏图标原图保存在 `assets/notemenu-status-icon.png`，采用白色便笺与透明文字、笔形镂空，生成 18pt 的 1x/2x 资源，以 template 模式适应深浅色背景

## 编辑器测试

```bash
bash scripts/test-editor.sh
bash scripts/build-editor-harness.sh
open build/NoteMenuEditorHarness.app
```

测试宿主复用正式编辑器，草稿和发送生成的 `export.html` 位于 `/private/tmp/NoteMenuEditorHarness`，不会写入系统备忘录。自动化测试需要可访问 AppKit 和剪贴板的 macOS 用户会话。

格式定义见 [EditorSpec](docs/EditorSpec.md)，架构见 [EditorDesign](docs/EditorDesign.md)，自测证据与待验项目见 [EditorAcceptanceResults](docs/EditorAcceptanceResults.md)。

## License

MIT
