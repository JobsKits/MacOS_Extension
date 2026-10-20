# `【MacOS】卸载用VSCode打开Finder扩展.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与确认](#jobs-toc-heading-2)
- [二、影响与日志](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

卸载 `../JobsVSCodeOpener.xcodeproj` 对应的 Finder 右键菜单“用 VSCode 打开项目”，保留工程源码与 [**Visual Studio Code**](https://code.visualstudio.com) 本身。完整工程说明见[项目 README](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与确认 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、双击同目录的 `./【MacOS】卸载用VSCode打开Finder扩展.command`，或在终端中执行。

2、先阅读内置自述并按回车，脚本核对系统工具并展示真实注册路径及待删除的自有 App。

3、必须输入 `YES` 才会停用、注销扩展、删除核验通过的 App 并重启 Finder。其它输入取消；非交互输入直接退出。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、影响与日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 固定扩展 ID 为 `com.jobs.JobsVSCodeOpener.FinderSyncExtension`，App ID 为 `com.jobs.JobsVSCodeOpener`。
- 只删除系统已登记路径中，名称为 `JobsVSCodeOpener.app` 且 Info.plist Bundle ID 匹配的真实 App 目录；符号链接不会进入删除范围。
- 工程源码、IDE、其它扩展与未登记的构建缓存保留。没有系统级安装或代理修改，不使用 `sudo`。
- 日志为系统临时目录中的 `【MacOS】卸载用VSCode打开Finder扩展.log`。
- 重新用 [**Xcode**](https://developer.apple.com/xcode) 运行工程或使用父目录统一安装器，可以重新安装。尚未实际执行卸载；脚本交付时仅做语法与安全分支验证。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
