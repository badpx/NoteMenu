# NoteMenu

一个常驻 macOS 菜单栏的快速笔记录入工具：点击菜单栏图标弹出录入窗口，写完后一键保存到系统「备忘录」。

A lightweight macOS menu bar app for quickly jotting down notes and saving them to Apple Notes with one click.

## 功能

- **菜单栏常驻**：点击状态栏图标展开/收起录入浮窗，无 Dock 图标打扰
- **富文本录入**：支持加粗、斜体、下划线，以及项目符号、编号列表
- **图片附件**：可直接粘贴或拖入图片，保存时作为备忘录附件
- **一键保存**：保存到系统备忘录后自动清空录入窗口，首行自动作为笔记标题
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

- SwiftUI + AppKit：`NSStatusItem` + `NSPanel` 浮窗承载 SwiftUI 界面，编辑器为 `NSTextView` 封装
- 写入备忘录：备忘录无公开 API，通过 AppleScript（`make new note` / `make new attachment`）实现，正文使用自写的白名单 HTML 导出（`h1/b/i/u/ul/ol/li`）
- 沙盒：开启 App Sandbox，通过 `com.apple.security.temporary-exception.apple-events` 获得控制备忘录的权限

## License

MIT
