# READ BOOKS · entry（鸿蒙 TXT 阅读器 MVP）

设计基准：仓库根 [`docs/DESIGN.md`](../docs/DESIGN.md)。本工程为其 M1–M3 核心实现。

## 如何构建运行

1. 安装 **DevEco Studio 5.0+**（含 HarmonyOS NEXT SDK，API 12+）
2. 用 DevEco Studio **打开 `read-books/` 目录**（工程根，含 build-profile.json5）
3. 首次打开让 IDE 自动安装 hvigor 依赖；File → Project Structure → Signing Configs 勾选 Automatic Signature
4. 选择模拟器或真机，Run `entry`

首次启动自动内置《西游记（节选）》示例书（公有领域），无需自备 TXT 即可体验。

## MVP 范围（对照设计大纲）

- ✅ M1 骨架：工程配置、语义色 token（light/dark）、主题系统、字体排印规格
- ✅ M2 导入与书架：DocumentViewPicker 导入、编码检测（BOM/UTF-8/GB18030/UTF-16）、章节正则切分、书架网格、长按删除
- ✅ M3 阅读引擎（简化版）：贪心组行分页 + 字符宽度缓存 + 章级 LRU 页缓存、Canvas 自绘渲染、点按/滑动翻页、字符偏移进度锚点、目录 Sheet、阅读设置 Sheet（字号/行距/主题/翻页模式）、HUD 毛玻璃栏

## 已知简化（后续里程碑补齐）

| 简化项 | 设计目标 | 计划 |
|---|---|---|
| 分页在 UI 线程按章惰性执行 | TaskPool 后台预分页 | M3 完善 |
| 进度条为全书百分比 | 逐页页码需全书分页 | 随 TaskPool |
| 无翻页动画 | 跟手位移 + easeOut 落位 | M4 动效 |
| 非全屏沉浸布局 | setWindowLayoutFullScreen + 安全区 | M4 |
| 图标用文字字形（＋ / ‹ / Aa / 目录） | kit SVG 图标管线 + 着色 | M4 |
| 书签表已建、UI 未做 | 书签面板 | M4 |
| 界面字体为系统字 | DM Sans / JetBrains Mono ttf 注册 | M1 完善项 |
| 英文按字符断行 | 词边界换行 | M3+ |
| App 图标为渐变占位色块 | 正式图标 | M4 |

## 工程结构

见 `docs/DESIGN.md` §7；模块依赖方向：pages → components → theme；pages → reader/data → model。
