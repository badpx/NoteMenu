# 控件状态修订

本页覆盖早期设计说明中的按钮状态约定，中英文、深浅色一致。

| 状态 | 格式 / Pin / Close / 目录按钮 |
|---|---|
| 默认 | 透明背景，普通前景色 |
| Hover | 淡黄色圆角背景；深色模式使用深琥珀色 |
| 列表或 Pin 选中 | 仅图标前景使用强调色，背景仍透明 |
| 选中并 Hover | 强调色前景 + Hover 背景 |

格式入口固定显示 **Aa**，不再使用会随语言变形的系统 `textformat` 图标。目录选择器保留图标、名称、箭头与两侧内边距，取消常驻背景。保存按钮继续使用原有黄色／灰色填充与加深 Hover，不受此规则影响。

最新设计稿右侧窗口同时示意两种独立状态：**Aa 处于 Hover，项目符列表处于选中**。

- [中文浅色](main-window-v3.png)
- [中文深色](main-window-dark-v2.png)
- [英文浅色](main-window-light-en-v2.png)
- [英文深色](main-window-dark-en-v2.png)

图像由内置 image_gen 根据原设计稿进行局部编辑，[完整修订提示词](control-states-v2-prompt.txt)已保留。
