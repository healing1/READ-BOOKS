# READ BOOKS

HarmonyOS 原生阅读器 · Apple 设计语言 · TXT / EPUB / PDF · **0.2.1**。

## 下载

- [GitHub Releases](https://github.com/healing1/READ-BOOKS/releases) — 下载未签名 HAP，签名后安装

## Docs

- [设计与验收记录](docs/DESIGN.md) — 新日期的范围覆盖历史里程碑
- [构建与运行](read-books/README.md) — 目标 HarmonyOS 6.1.1，最低兼容 API 12

## Status

- 三个入口：主页、书库、我的；宽屏主侧栏、2–6 列书库、横屏双页、阅读记录与目标。
- TXT 流式导入；无 DRM EPUB 保留原书图片、CSS、正文目录链接和固定版式；未加密 PDF 使用原生 PDF Kit，组件可用性取决于运行环境。不再设置 100 MiB 整书上限，仍受存储、内存及格式安全检查约束。
- API23+ 原生 HDS 沉浸导航（实际材质待兼容运行环境验收）；旧系统保留浮动导航、按压光感和减少动态效果设置。
- EPUB 内嵌封面、三种格式自选封面、旧书修复入口；PDF 首页缩略图已实现，仍需 PDF Kit 运行验证。
- 阅读支持宋体、楷体、自定义字体和背景，以及暖纸 / 夜间主题；EPUB 三槽相邻章预排版、50 项有界预读、跟手翻页和自适应松手动画。
- 2026-09-23：0.2.1 已通过模拟器回归并保留数据覆盖个人 MatePad；实际真机帧率不以模拟器结果代替。
- 正式包不内置示例书。个人书籍、设备截图及签名材料不随源码提交；安装包见 Releases。
