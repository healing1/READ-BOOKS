# READ BOOKS · 设计大纲

> 鸿蒙阅读器 · Apple 设计语言 · V1 适配 TXT
>
> **本文件是项目的最高设计基准**：技术栈、设计系统、架构与里程碑一经确定，后续一切设计与编码一律以本文件为准。要变更，先改本文件、再改代码。

---

## 1. 技术栈（核心决策，先行确定）

### 1.1 总选型：**ArkTS + ArkUI 鸿蒙原生**

| 层 | 选型 | 说明 |
|---|---|---|
| 目标平台 | **HarmonyOS NEXT（API 12+，即 5.0 及以上）**，Stage 模型 | 纯血鸿蒙形态，华为应用市场主流上架形态 |
| 语言 | **ArkTS** | 官方语言，TypeScript 超集，类型安全 |
| UI 框架 | **ArkUI 声明式范式**（@Component / @Builder / Canvas） | 排版引擎需要精确的文本测量与自绘能力 |
| 状态管理 | **状态管理 V2**（@ObservedV2 / @Trace / @Local / @Param / PersistenceV2） | V1 已进维护模式，新项目直接用 V2 |
| 阅读渲染 | **ArkUI Canvas 自绘 + @ohos.measure 文本测量**（自研排版引擎） | TXT 逐行分页必须精确测行，Text 组件做不到 |
| 后台分页 | **@ohos.taskpool**（Worker 线程） | 大文件分页不阻塞 UI 线程 |
| 文件 I/O | **@ohos.file.fs** 流式分块读取 | 100MB+ 小说不整读进内存 |
| 文本编码 | **util.TextDecoder**（UTF-8 / GBK / GB18030 / UTF-16LE/BE） | 中文 TXT 常见 GBK，必须自动检测 |
| 持久化 | **relationalStore（SQLite）** 存书架/进度/书签；**PersistenceV2** 存阅读设置 | 结构化数据与轻量偏好各归其位 |
| 文件导入 | **@ohos.file.picker · DocumentViewPicker** | 系统文件选择器选书 |
| 字体 | **resources/font/ 自定义字体注册**（DM Sans、JetBrains Mono） | Apple 风格字面质感；中文回退系统字体 |
| 毛玻璃/材质 | **backgroundBlurStyle / backgroundEffect** | iOS 式材质层（HUD、导航条） |
| 动效 | **animateTo + curves.springMotion / easeOut** | 弹性与克制的动效曲线 |
| IDE / 构建 | **DevEco Studio 5.0+ / hvigor** | 官方工具链 |
| 测试 | **hypium**（单元 + UI 测试） | 官方框架 |

### 1.2 为什么不是跨端框架

| 方案 | 结论 | 原因 |
|---|---|---|
| **ArkTS + ArkUI（选定）** | ✅ | 阅读器核心是重排版引擎：需要原生 measure/Canvas 精细控制 + 多线程分页 + 后续 EPUB/PDF 的 zlib、native .so 深度解析，全是原生能力。HarmonyOS NEXT 上架也要求纯鸿蒙应用形态 |
| Flutter（含三方鸿蒙适配） | ❌ | 在 NEXT 上是移植层；文本排版细节仍需绕过框架定制 |
| uni-app / RN | ❌ | 性能与排版控制力不足，且依赖三方维护的鸿蒙运行时 |
| Web 壳（ArkWeb） | ❌ | 大文件分页性能、离线体验、翻页手势细腻度都不达标 |

> 结论：**本项目定位纯鸿蒙原生阅读器，一律 ArkTS + ArkUI。** 若未来需要多端，届时以独立产品评估，不在本仓库范围。

### 1.3 前置条件（开发环境）

| 项 | 状态 | 备注 |
|---|---|---|
| DevEco Studio 5.0+ | ⚠️ **本机未安装** | 编码先行；进入构建/调试阶段前需安装（含 HarmonyOS NEXT SDK，API 12+） |
| 真机 / 模拟器 | 待定 | DevEco 自带模拟器可跑 V1 验证 |
| Node.js | ✅ 已装 | hvigor 依赖 |
| Git + GitHub 远程 | ✅ 就绪 | healing1/READ-BOOKS |

---

## 2. 产品定位与范围

**一句话**：极简、克制、Apple 质感的鸿蒙本地阅读器。*"Content first, whitespace is design, restraint is style."*（沿用设计套件纲领）

**格式路线**：TXT（V1，本文范围）→ EPUB（V2）→ PDF（V3）。

### 2.1 V1 功能清单

**做**：

- TXT 导入（系统文件选择器，复制入应用沙箱）
- 编码自动检测（UTF-8 / GBK / GB18030 / UTF-16）
- 书架：封面卡片网格、最近阅读排序、长按管理（删除）
- 阅读：左右翻页（滑动 + 点按翻页区）、页码/进度
- 章节目录（自动识别，正则切分）
- 进度记忆（以字符偏移为锚，字体改变不丢位置）
- 书签
- 阅读设置：字号 / 行距 / 翻页模式 / 阅读主题（跟随系统 · 纸白 · 纯白 · 夜间）
- 深色模式全局适配

**不做（V1 明确排除）**：EPUB/PDF、云同步、TTS、笔记批注、书源/网络书城、AI 功能。

---

## 3. 设计系统（Apple 风格 → 鸿蒙落地）

设计源：design/apple-kit/（Pinguo Design System，基于 Apple HIG 的结构化设计套件）。所有 token 以其 colors_and_type.css / css.json 为准，本节完成到鸿蒙 resources/color.json + theme/ 的映射。

### 3.1 原则

1. **内容优先**：界面为正文让路；留白本身就是设计。
2. **克制用色**：先黑白灰，再蓝。单屏主色相 ≤ 2。
3. **边界优先于阴影**：静止态用 1px 边界定义卡片，悬浮层才允许明显阴影。
4. **物理感的触控**：最小触控 44×44vp，操作是有分量的。

### 3.2 色彩 Token（semantic，仅消费语义层）

| Token | Light | Dark | 用途 |
|---|---|---|---|
| primary | #007AFF | #0A84FF | 主操作、强调（Apple System Blue） |
| background | #F2F2F7 | #000000 | 页面底色 |
| surface | #FFFFFF | #1C1C1E | 卡片/列表 |
| surfaceElevated | #FFFFFF | #2C2C2E | HUD、弹层 |
| labelPrimary | #000000 | #F5F5F7 | 主文字 |
| labelSecondary | #6E6E73 | #8E8E93 | 次文字 |
| labelTertiary | #8E8E93 | #AEAEB2 | 弱文字、占位 |
| separator | #E5E5EA | #3A3A3C | 分隔线、描边 |
| destructive | #FF3B30 | #FF453A | 删除等危险操作 |
| success | #34C759 | #30D158 | 成功态 |

**阅读主题**（仅作用于阅读器画布，四选一）：

| 主题 | 背景 | 正文 | 备注 |
|---|---|---|---|
| 跟随系统 | = Light #FFFFFF / Dark #000000 | 对应 label | 默认 |
| 纸白 | #F7F2E7 | #3A3A3C | 米黄护眼 |
| 纯白 | #FFFFFF | #000000 | 高对比 |
| 夜间 | #000000 | #AEAEB2 | 纯黑省电 |

落地方式：resources/base/element/color.json + resources/dark/element/color.json 双份，组件一律 $r('app.color.xxx')，不写死色值。

### 3.3 字体排印

| 层级 | 规格（fp / weight / 行高） | 用途 |
|---|---|---|
| LargeTitle | 34 / 700 / 1.15 | 页面大标题（书架页"书架"，Apple 大标题范式） |
| Title | 22 / 700 | 二级页标题 |
| Headline | 17 / 600 | 卡片标题、按钮 |
| Body | 16 / 400 / 1.55 | 正文、列表 |
| Subhead | 14 / 400 | 辅助说明 |
| Footnote | 13 / 400 | 页码、时间戳 |
| Caption | 12 / 400 | 标签、eyebrow（大写 + 加宽字距） |
| ReadingBody | **17–26 可调** / 400 / **1.4–2.0 可调（默认 1.55）** | 阅读正文 |
| Mono | 14 / 400 | 进度百分比、字数等数据场景（JetBrains Mono） |

字体族：

- **DM Sans**（拉丁界面字，套件指定）：ttf 放 resources/font/，fontFamily('DM Sans') 注册使用；**中文字符自动回退 HarmonyOS Sans**（系统字），不引入中文自带上字体（体积不可接受）。
- **JetBrains Mono**：数字/数据场景。
- 阅读正文：默认系统黑体系；V2 起提供衬线（宋体系）切换。
- 套件未指定衬线族，**不臆造**，留待 V2。

### 3.4 间距 / 圆角 / 阴影 / 边框

- **间距**（vp）：4 · 8 · 12 · 16 · 24 · 32 · 48 · 64（套件 10 级中的移动端子集）。
- **圆角**：S=8（输入、小标签）· M=12 · L=20（卡片，≈套件 1.2rem 全局值）· XL=28（Sheet 顶部）· **按钮全胶囊**。
- **阴影**：静止态无阴影或 0 1px 2px rgba(0,0,0,.04)；悬浮层 0 24px 64px -12px rgba(0,0,0,.12)；其余一律克制。
- **边框**：1px separator，结构性而非装饰性。

### 3.5 组件规范（V1 组件库）

映射套件 6 组件 + 阅读器特有组件，全部放 components/：

| 组件 | 来源 | 规格要点 |
|---|---|---|
| CapsuleButton | kit/Button | 胶囊；primary 填充 / secondary 文字+chevron / text；尺寸 40 / 48 / 56；每屏一个主 CTA |
| BookCard | kit/Card 派生 | L=20 圆角、1px 边界、无阴影；书名 Headline、作者/进度 Subhead、进度条 2px |
| Input | kit/Input | 12 圆角、聚焦 ring（2px primary）、无重装饰 |
| NavHeader | kit/Navigation 派生 | 毛玻璃材质条（backgroundBlurStyle）、返回 chevron + 居中标题（Headline） |
| LargeTitleScroll | Apple 大标题范式 | 滚动时收缩为 NavHeader 居中标题（animateTo 250ms） |
| EmptyState | 自研 | 居中插画位 + 一句 Subhead + CapsuleButton"导入图书" |
| HudBar | 阅读器特有 | 顶部/底部毛玻璃条（MaterialThin），底部含 ProgressSlider |
| ProgressSlider | 阅读器特有 | 拖动实时预览页码，松手跳转 |
| Sheet | 阅读器特有 | XL=28 顶部圆角、springMotion 弹出（目录、设置、删除确认） |

### 3.6 图标

- 源：design/apple-kit/assets/icons/（Lucide 描边风，接近 SF Symbols 细线气质）。
- 落地：SVG 直接放 resources/base/media/，Image($r('app.media.ic_xxx')) 渲染；描边色走 labelPrimary 语义。
- 阅读器 HUD 图标统一 24vp、2px 描边。

### 3.7 动效

| 场景 | 规格 |
|---|---|
| 翻页（滑动） | 跟手位移，松手 easeOut 250ms 回弹/落位 |
| 翻页（点按） | easeOut 250ms 平移切换 |
| HUD 呼出/隐藏 | 淡入 + 上下滑入 200ms |
| Sheet | curves.springMotion |
| 大标题收缩 | 250ms easeOut |

克制原则：动效服务层级变化，不做装饰性动画。

### 3.8 触控与无障碍

- 最小触控目标 44×44vp；翻页热区：左右各 25% 屏宽，中央 50% 呼出 HUD。
- 全部控件配 accessibilityText；文字层级用系统字号缩放。

---

## 4. 信息架构与页面设计（V1）

### 4.1 页面地图

```
书架 Bookshelf（首页，LargeTitle）
 ├→ 导入（DocumentViewPicker，系统 UI）
 └→ 阅读器 Reader（全屏沉浸）
      ├→ 目录 Sheet（章节列表）
      ├→ 阅读设置 Sheet（字号/行距/主题/翻页模式）
      └→ 删除确认 Sheet（书架长按）
```

仅两页 + 三个 Sheet。**没有 TabBar**（单功能 App 不需要；Apple 同类 App 阅读态亦无底栏）。

### 4.2 书架页

- 顶部 LargeTitle "书架" + 右上 +（Capsule 图标按钮）导入。
- 内容：BookCard 网格（2 列，折叠屏/平板 3–4 列）；按 lastReadAt 倒序。
- 空态：EmptyState → "还没有图书 / 从文件导入你的第一本 TXT / [导入图书]"。
- 长按卡片 → 删除确认 Sheet（destructive 红字按钮 + 取消）。

### 4.3 阅读器页（核心页面）

- 全屏沉浸：setWindowLayoutFullScreen(true)，内容避开安全区。
- 画布：Canvas 绘制当前页（ReadingBody 规格由设置驱动）。
- 交互热区：左 25% 上一页 · 右 25% 下一页 · 中央 50% 切换 HUD。
- **HUD 顶栏**（毛玻璃）：返回 chevron · 书名（Headline）· 更多（···）。
- **HUD 底栏**（毛玻璃）：目录图标 · ProgressSlider + 页码 12 / 348（Mono）· 设置图标。
- HUD 呼出时正文保持静止，HUD 层浮于其上（Apple Books 同款行为）；翻页自动隐藏 HUD。

### 4.4 目录 / 设置 Sheet

- 目录：章节列表（当前章高亮 primary），点击跳转；JetBrains Mono 章节序号。
- 设置：字号 stepper（A- / A+）、行距 stepper、阅读主题四选一（色块胶囊组）、翻页模式（滑动/点按/两者）。

### 4.5 导入流程

DocumentViewPicker(.txt) → 复制入沙箱 books/ → 编码检测 → 首次解析（章节+粗分页）→ 书架出现新卡片（封面：书名 + 品牌色系封面色板，TXT 无内嵌封面）→ 询问"立即阅读？"。

---

## 5. TXT 阅读引擎设计（V1 技术核心）

### 5.1 管线

```
导入 → 编码检测 → 归一化文本(入库) → 章节切分 → 分页排版 → Canvas 渲染
                                                 ↑ 设置变更触发重排
```

### 5.2 编码检测（EncodingDetector）

1. BOM 判定：UTF-8 BOM / UTF-16LE / UTF-16BE。
2. 无 BOM：前 64KB 尝试**严格 UTF-8** 解码，成功 → UTF-8。
3. 失败 → **GB18030**（GBK 超集，中文 TXT 兜底）。
4. 解码后统一为 UTF-8 字符串存库；原始文件保留可再导入。

### 5.3 章节切分（ChapterDetector）

行首正则（大小写不敏感，含中英文）：

```
^(第[0-9零一二三四五六七八九十百千万两]+[章回节卷集部篇]|序章|楔子|引子|尾声|后记|Chapter\s+\d+)[^\n]{0,30}$
```

- 命中行 → 章节标题；无任何命中 → 每 50,000 字符切"虚拟章"。
- 章节数据：(bookId, idx, title, startOffset, endOffset)，一次解析入库。

### 5.4 分页排版（Paginator，性能关键）

- **输入**：章节数组 + 视口尺寸（含 padding）+ 排版参数（字号/行距/字体）。
- **字符宽度缓存**：按当前字体字号一次性建立 char → width 表（Canvas measureText 批量）。
- **贪心组行**：逐字符累加宽度，超视口宽即断行；段首缩进 2em；段间距 0.5em。
- **组页**：行高 = fontSize × lineHeight；满页即翻页 → 产出 Page { chapterIdx, startOffset, endOffset, lines[] }。
- **TaskPool 后台分页**：分页任务（纯计算）丢 Worker；当前页 ±10 页 LRU 缓存；跳章时全章快速重分。
- **重排**：字号/行距等影响排版的参数变化 → 全书标记脏 → 后台逐章重分，当前页先分（改完立刻可见）。

### 5.5 渲染（ReaderCanvas）

- Canvas 逐行 drawText；页眉（章节名 Footnote）、页脚（页码 Mono）。
- 翻页动画：两页 Canvas 叠加位移（跟手 + easeOut 落位）。

### 5.6 进度锚点（关键决策）

- 进度一律记**字符偏移量 charOffset**，**不记页码**——字号/行距改变后页码全变，字符偏移永远有效。
- 入库时机：翻页落位、退出阅读器、每 30 秒心跳。

---

## 6. 数据模型与存储

### 6.1 SQLite（relationalStore，库名 readbooks.db）

```sql
books(id INTEGER PK, title TEXT, author TEXT, format TEXT,
      size_bytes INTEGER, encoding TEXT, char_count INTEGER,
      cover_color TEXT, file_path TEXT,
      created_at INTEGER, last_read_at INTEGER,
      progress_char_offset INTEGER DEFAULT 0, deleted INTEGER DEFAULT 0)

chapters(book_id INTEGER, idx INTEGER, title TEXT,
         start_offset INTEGER, end_offset INTEGER)  -- PK(book_id, idx)

bookmarks(id INTEGER PK, book_id INTEGER, char_offset INTEGER,
          excerpt TEXT, created_at INTEGER)
```

### 6.2 阅读设置（PersistenceV2，自动持久化）

```ts
@ObservedV2
class ReadingSettings {
  @Trace fontSize: number = 18      // 17-26
  @Trace lineHeight: number = 1.55  // 1.4-2.0
  @Trace theme: 'system' | 'paper' | 'white' | 'night' = 'system'
  @Trace pageMode: 'slide' | 'tap' | 'both' = 'both'
}
```

---

## 7. 工程结构

```
read-books/                        # DevEco Studio 工程（M1 创建于仓库根）
├─ AppScope/
├─ entry/src/main/
│  ├─ ets/
│  │  ├─ entryability/EntryAbility.ets
│  │  ├─ pages/
│  │  │  ├─ Bookshelf.ets         # 书架（首页）
│  │  │  └─ Reader.ets            # 阅读器
│  │  ├─ components/              # §3.5 组件库
│  │  │  ├─ CapsuleButton.ets  NavHeader.ets  LargeTitleScroll.ets
│  │  │  ├─ BookCard.ets      EmptyState.ets  HudBar.ets
│  │  │  └─ ProgressSlider.ets  Sheet.ets
│  │  ├─ reader/                  # §5 引擎（纯逻辑，可单测）
│  │  │  ├─ EncodingDetector.ets  ChapterDetector.ets
│  │  │  ├─ Paginator.ets         PageCache.ets
│  │  │  └─ ReaderEngine.ets      # 门面：解析→分页→渲染调度
│  │  ├─ model/                   # Book / Chapter / Bookmark 实体
│  │  ├─ data/                    # Db / BookRepo / ChapterRepo / BookmarkRepo
│  │  ├─ theme/                   # tokens.ets（间距/圆角/字阶）+ ThemeManager
│  │  └─ utils/
│  └─ resources/
│     ├─ base/element/color.json  # Light 语义色
│     ├─ dark/element/color.json  # Dark 语义色
│     ├─ font/                    # DMSans / JetBrainsMono ttf
│     └─ base/media/              # 图标（kit SVG 迁入）
└─ hvigor/                        # hvigor 构建配置
```

依赖方向（单向）：pages → components → theme；pages → reader / data → model。reader/ 与 data/ 不 import ArkUI 组件（保证可测试、可移植）。

---

## 8. 里程碑（V1）

| 里程碑 | 内容 | 验收 |
|---|---|---|
| **M1 骨架** | DevEco 工程创建、主题 token、色板 dark/light、字体注册、书架页静态布局 | 空书架 + EmptyState 在模拟器可跑 |
| **M2 导入与书架** | DocumentViewPicker、编码检测、章节切分入库、书架 CRUD | 导入 10MB GBK 小说 < 5s，书架正确展示 |
| **M3 阅读引擎** | Paginator、TaskPool 分页、Canvas 渲染、翻页手势、进度锚点 | 流畅翻页无掉帧；改字号进度不丢 |
| **M4 打磨** | 目录/设置 Sheet、书签、HUD 毛玻璃、动效、深色全量适配 | 全流程走查 + 真机验证 |

每个里程碑 = 一个版本（commit + push，按既定推送策略执行）。

---

## 9. 后续版本技术预案（不在 V1 范围）

- **V2 EPUB**：@ohos.zlib 解包 → @ohos.xml 解析 OPF/NCX/NAV → XHTML 白名单清洗 → 复用 §5 排版引擎（段落携带样式）→ 封面图入书架。
- **V3 PDF**：首选 pdfium 移植为 native .so（NAPI）逐页渲染位图；备选连续滚动模式规避重排。
- **V4+**：WebDAV 云同步、TTS、笔记导出。

---

## 10. 设计资源索引

| 路径 | 用途 |
|---|---|
| design/apple-kit/README.md | 设计系统纲领（色彩/字体/间距/圆角/阴影哲学） |
| design/apple-kit/colors_and_type.css · css.json | Token 唯一来源（映射进 §3.2-3.4） |
| design/apple-kit/components/*.json | 6 组件结构化规范（映射进 §3.5） |
| design/apple-kit/preview/*.html | 组件视觉预览 |
| design/apple-kit/ui_kits/website/index.html | 完整交互参考（参考层，非实现基准） |
| design/apple-kit/assets/icons/ | Lucide SVG 图标库 |
| Apple.zip | 原始压缩包（保留存档） |

---

*文档版本：v1.0 · 状态：设计定稿（M1 之前）*
