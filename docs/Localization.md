# NotesMate 本地化

## 产品标识

- 产品名、应用包、进程名称：`NotesMate` / `NotesMate.app`。
- Debug 和 Release 的 Bundle ID：`com.badpxx.notesmate`。
- 标题栏、菜单栏辅助说明、欢迎语、退出菜单、权限说明统一使用 NotesMate。
- 草稿目录为应用沙盒内的 `Application Support/NotesMate`。不迁移旧 NoteMenu 的测试数据或偏好设置。
- Xcode 项目和 target 仍名为 NoteMenu，Swift Package 测试模块仍名为 NoteMenuEditor；共享 Scheme 已改名为 NotesMate。这些工程标识不展示给产品用户。

## 语言匹配

`NoteMenu/Editor/EditorLanguage.swift` 统一读取 macOS 的首选语言，包含系统的单独 App 语言设置。调整系统或 App 语言后重新启动应用。

| 语言 | 资源目录 |
| --- | --- |
| 简体中文 | zh-Hans |
| 繁体中文 | zh-Hant |
| 英语 | en |
| 日语 | ja |
| 韩语 | ko |
| 德语 | de |
| 法语 | fr |
| 西班牙语 | es |
| 葡萄牙语 | pt |
| 意大利语 | it |
| 菲律宾语 | fil |
| 印度尼西亚语 | id |
| 马来西亚语 | ms |
| 泰语 | th |
| 越南语 | vi |

匹配规则：

- 只匹配首选语言；不支持时直接使用英语，不继续尝试后面的语言。
- 区域变体使用相同语言资源，例如 `fr-CA` → `fr`、`pt-BR` / `pt-PT` → `pt`。
- 中文显式脚本优先：`zh-Hans` 使用简体，`zh-Hant` 使用繁体；未指定脚本时，TW / HK / MO 使用繁体，其余使用简体。
- `tl` 作为菲律宾语别名，`in` 作为印度尼西亚语旧代码别名。
- 缺失文案回退到英语；开发中尚未登记的新键最终显示英语键名。
- 用户输入的笔记内容、文件名、备忘录目录名不翻译。macOS 提供的对话框及底层系统错误由系统本地化。

## 资源与文案

`NoteMenu/Localization/<语言>.lproj/` 内包含：

- `Localizable.strings`：菜单、格式操作、小贴士、占位提示、保存状态、可访问性说明、应用自身错误信息。
- `InfoPlist.strings`：应用名称与自动化权限说明。

使用固定英语文案作为键，通过 `EditorLanguage.text` 读取。含动态内容的消息使用 `{0}`、`{1}` 占位符和 `EditorLanguage.format`；禁止先拼接或插值再查找翻译。替换只执行一次，用户提供的文件名含 `%`、引号或占位符时保持原样。

格式按钮在所有语言下均显示 `Aa`。顶部小贴士保持 300pt 最大宽度、40pt 最小高度；较长译文自然换行并增加浮层高度，不截断，也不改变正文布局。显示时长及触发策略保持不变。功能提示中的已知快捷键由 `EditorTipText` 显示为与保存提示共用的键帽；组合键不可跨行拆分，普通提示中的同名文字保持原样。

## 验证

- `bash scripts/test-editor.sh`：编辑器回归、15 份资源完整性、占位符一致性、中文脚本 / 地区 / 语言别名、英语回退以及小贴士布局。
- `bash scripts/capture-design-preview.sh ja light 360 --tips --verify-tips`：使用正式 SwiftUI / AppKit 组件生成预览，并验证正文不重排、选区不变、提示正文点击穿透、关闭按钮可点击。
- 预览工具接受语言代码、`light` / `dark`、窗口宽度；示例内容为测试笔记，不作为产品翻译。
- `xcodebuild -project NoteMenu.xcodeproj -scheme NotesMate -configuration Debug -derivedDataPath build/debug-icon-composer build`：验收产物为 `build/debug-icon-composer/Build/Products/Debug/NotesMate.app`。

新增语言时同步更新 `EditorLanguage.supported`、项目的 `knownRegions`、Info.plist 的 `CFBundleLocalizations`，并补齐两份资源。文案翻译仍建议在正式发布前由母语使用者校对。
