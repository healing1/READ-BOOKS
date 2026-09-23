# READ BOOKS · HarmonyOS 原生阅读器 0.2.1

当前范围见 [`docs/DESIGN.md`](../docs/DESIGN.md) 的日期更新；旧版 M1–M3 清单不代表当前功能状态。

## 如何构建运行

本机工具链、SDK、模拟器与签名材料放在 `C:\Users\27586\DevTools\HarmonyOS`。目前使用 CLT 26.0.0.821 编译，目标系统 HarmonyOS 6.1.1(24)，兼容下限 API12；不是要求设备升级到 API26。

在仓库根执行：

```powershell
.\scripts\build.ps1 -Action Build
.\scripts\build.ps1 -Action Test
.\scripts\build.ps1 -Action Check
.\scripts\test-device.ps1 -Device '127.0.0.1:5555' -AllowUnavailablePdfKit
```

原生测试显式指定获准使用的设备，模拟器测试不等同于真机验收。2026-09-23 的 0.2.1 已通过 15 个本地 check、26 项单元测试及模拟器翻页 / 外观回归，并保留数据覆盖个人 MatePad，确认版本和启动正常。只有无 PDF Kit 的模拟器才允许 `-AllowUnavailablePdfKit`；完整格式验收不能带此选项。个人设备不安装测试模块或测试书。

启动检查使用 `scripts/verify-startup.cjs`：先加载 `harmony-env.ps1` 并显式设置 `HDC_DEVICE` 为本次获准操作的设备，解锁并打开阅读器后执行。它只切换三个入口，不清空数据、不导入素材、不改变外观和屏幕方向。

IDE 可打开此目录；本地签名由忽略的 `signing.local.json` 注入，证书密码不得提交。产物位于 `entry/build/default/outputs/default/entry-default-signed.hap`。

首次启动为空书库，不内置《西游记》或其他示例书；更新采用覆盖安装，不清空现有书库、阅读记录和设置。

## 已实现

- 主页 / 书库 / 我的，840vp 宽屏主侧栏、2–6 列封面、列表与搜索、排序、导入、管理已读状态、目标和真实阅读统计。
- TXT 流式解码、索引与章节分页；无 DRM EPUB 2/3 的原书 CSS、图片、内嵌字体、固定版式、应用目录及正文目录锚点；原生 PDF 页码、书签、搜索、缩放、单双页与适合页面。
- 后台分页与缓存、同时支持点按 / 滑动翻页、进度锚点、目录与书签、暖纸 / 夜间 / 跟随外观主题、字号行距、单页 / 双页、安全区和前后台计时。
- 内置宋体（思源宋体）、楷体（霞鹜文楷）、自定义字体与背景。字体来源和随包许可见 [FONTS.md](../docs/FONTS.md)。
- EPUB 当前 / 前章 / 后章三槽预排版，50 项 / 16 MiB 正文滚动预读和有界资源缓存；跨章拖动时即可看到准备好的下一页。运动时在屏幕边缘裁切，静止时保留正文边距；松手收尾为 160–320 ms 自适应位移，减少逐帧布局读取及后台竞争。向系统申请设备支持的高刷新档位，不承诺持续满帧。
- API23+ 的原生 HdsNavigation / HdsTabs 配置沉浸材质、系统温控与滚动渐变模糊；旧系统保留浮动底栏、API20 按压光感和弹簧过渡。减少动态效果会关闭应用沉浸材质及自定义动效。
- EPUB 支持 cover-image、EPUB2 meta、guide 封面页、XHTML/SVG 中的本地图片引用与文件名兜底；图片先解码、缩小，再保存本地封面。TXT 可使用文字封面或自选 PNG/JPEG，其他格式也支持更换封面。
- PDF 导入时在后台生成首页缩略图，旧 PDF 缺失封面时串行修复；旧 EPUB 未保留原始压缩包时，在图书选项重新选择 EPUB 原文件恢复封面，不改正文、书签或进度。

## 边界与待验收

- 已移除整书 100 MiB、展开副本 300 MiB 的固定上限；仍检查安全整数、ZIP 路径 / 条目、章节和资源读取边界，实际容量受设备存储与内存限制。
- EPUB 保留本地出版资源，但不执行书内脚本、不加载远程资源、不绕过 DRM；复杂出版样式的兼容性仍需逐书验证，不宣称支持全部交互媒体。
- PDF 不接受加密文档；6.0.2 x86 平板镜像缺少 PDF Kit。09-09 真机格式用例通过，但实际 PDF 预览与双页视觉尚未完整验收。
- API23+ 沉浸材质已经接线并通过编译，但当前运行的 API22 模拟器无法验收它。6.1.1 镜像下载尚未完成；普通 Slider/Toggle 的 API26 全局材质不能冒充为鸿蒙 6.1 已提供的能力。
- 09-19 原生测试 59 项通过，其中 3 项仅验证 PDF Kit 不可用时的行为，不能算作 PDF 实际渲染验收。TXT 自选封面与 EPUB 内嵌封面已在 API22 模拟器显示确认；完整 PDF 视觉验收仍待具备 PDF Kit 的运行环境。
- 原生测试使用独立的 `qa_readbooks` 数据库和文件目录，不清理正常书库。显式调用的格式/封面视觉用例会向模拟器正常书库添加少量 QA 图书；所有视觉 runner 均拒绝非模拟器设备。
- 源码中的小型 QA 格式样本仅属于 `ohosTest`，不进入正式 HAP。用户提供的小说、签名材料、设备截图 / 界面树和构建产物只留在本机；`docs/qa` 引用的历史截图不是仓库附件。

## 模拟器启动

`..\scripts\matepad-emulator.ps1 -Action Start` 直接调用模拟器，以保留数据的 coldboot 启动。实例根目录必须传入 `...\emulator\instances`，不是单个实例目录。09-11 排查到大于 10 MiB 的 kernel.log 轮转失败反复刷屏，备份旧日志后恢复约 44 秒启动；脚本会在启动前备份超过 8 MiB 的日志，并拒绝并开第二个实例。不会 reset 数据、删除镜像或重启 Windows。

## 工程结构

见 `docs/DESIGN.md` §7；模块依赖方向：pages → components → theme；pages → reader/data → model。
