# 主窗口设计实现

实现依据：浅色 V2、深色 V1 及对应英文设计稿。布局和点值以设计说明为准；生成稿的细小像素差异不作为硬性规格。

- 标题栏 40pt、底栏 48pt、圆角 14pt，统一 16pt 水平内边距；保留原有窗口大小与位置恢复，首次打开默认 380 × 410pt。
- 标题字号 14pt Semibold。实际 AppIcon 在 20pt 图像框中按比例显示，透明边界内的可见图形约 16pt。
- 编辑区首行起点为左侧 16pt、顶部 20pt；正文和提示 14pt，正文行间距 5pt，代码 13pt。
- Aa 使用固定文字标签，避免系统 textformat 图标随语言显示为“格式”。
- 普通控件及目录选择器默认无背景，只有 Hover 才显示淡黄色（深色为深琥珀）背景。列表与 Pin 的选中态仅前景着强调色；保存按钮维持原有填色。
- 五个格式控件使用 28pt 热区和 4pt 间隔；保存按钮 40 × 28pt；目录控件两侧 6pt 内边距，并添加展开箭头。
- `EditorAppearance` 定义深浅动态色，SwiftUI 工具栏与 AppKit 正文、列表标记、代码背景共用。浅色辅助文字微调为 #70726E，以达到对比度检查目标。
- `EditorLanguage` 根据 App 首选语言切换中英文，覆盖主窗口、格式菜单、图片选择、目标目录菜单、菜单栏菜单和常用错误提示。目录名称与笔记内容不翻译；系统返回的错误详情沿用其原文。
- 保存、置顶、拖动、缩放、IME、图片、自动保存草稿等仍使用原有实现。保存成功后保留窗口并可继续输入；没有新增主题或语言切换控件。

## 验证方式

1. `bash scripts/test-editor.sh`：编辑器回归，新增语言选择、主要文字色对比度、主题切换保持文档与选区测试。
2. `xcodebuild -project NoteMenu.xcodeproj -scheme NoteMenu -configuration Debug -derivedDataPath build/debug-icon-composer build`。
3. `bash scripts/capture-design-preview.sh`：使用生产 `NoteEditorView`、`RichTextEditor` 和实际图标生成中英文、深浅色、空白／编辑中共八张截图，并额外检查 360pt 最小宽度。产物位于 `build/design-preview`。

截图使用隔离草稿和注入的目录数据，不访问 Apple Notes，也不改真实笔记或用户设置。预览图仅显示窗口内容，实际浮窗外阴影由 macOS 绘制。
