# 内置阅读字体

阅读外观提供默认/原书、宋体、楷体以及已导入的自定义字体。切换选项不会删除自定义字体副本；原始 TTF/OTF 和书籍文件均不改动。固定版式 EPUB 与 PDF 保留原页，不强行替换文档字体。

| UI 选项 | 原字体及来源 | 发布身份 |
|---|---|---|
| 宋体 | [思源宋体 Source Han Serif SC Regular](https://github.com/adobe-fonts/source-han-serif) | 2.003；Git blob `cb41635674be23029e98469f729eded6ebc54611` |
| 楷体 | [霞鹜文楷 LXGW WenKai Regular](https://github.com/lxgw/LxgwWenKai/releases/tag/v1.522) | v1.522；发布附件 SHA-256 见下 |

两份二进制均保持上游原样，未裁剪字形、改名或转换格式。它们是宋体/楷体风格的开源字体，不是 Windows 的 SimSun/SimKai 字体文件。

- `SourceHanSerifSC-Regular.otf`：24,543,332 bytes；SHA-256 `78aa7a328fd974df2d688c8a9fd74a33d8334dfa84ab24d9d11efb2ffc464117`。
- `LXGWWenKai-Regular.ttf`：25,575,676 bytes；SHA-256 `39ad71264b588165b469e35e6afb162a378dacd1f95348160240ba9038ac3009`。
- 两者原字体合计约 47.8 MiB；随应用安装，运行时不下载或另存内置字体副本。

## 许可随包分发

两者采用 SIL Open Font License 1.1，完整上游版权与许可文本随字体保存在 `entry/src/main/resources/rawfile/fonts/SourceHanSerif-OFL.txt` 和 `LXGWWenKai-OFL.txt`。依据：[Adobe 原许可](https://raw.githubusercontent.com/adobe-fonts/source-han-serif/release/LICENSE.txt)、[LXGW v1.522 原许可](https://raw.githubusercontent.com/lxgw/LxgwWenKai/v1.522/OFL.txt)。

`scripts/check-reading-fonts.cjs` 核验二进制身份、sfnt 字形表、中文基本阅读字形、许可文件、旧设置迁移及选择失败回滚。Canvas 和原生文字通过 `text.FontCollection.getGlobalInstance().loadFontSync` 同步注册，确保首轮测量已使用真实字形；内置字体每进程注册一次，自定义字体按不可变 family 注册去重。EPUB 使用严格白名单的离线字体资源接口，并在新字体加载完成后重新计算分页。

模拟器 API 22 已人工核对 TXT / EPUB 的宋体、楷体截图，以及 TXT 选择宋体后强制重启仍使用宋体。Canvas 自定义字体能力面向 API 20 及以上；旧 API 的兼容构建不等同于旧系统具有这项绘制能力。证据在 `docs/qa/shaosong-builtin-*.png`、`txt-builtin-*.png`。
