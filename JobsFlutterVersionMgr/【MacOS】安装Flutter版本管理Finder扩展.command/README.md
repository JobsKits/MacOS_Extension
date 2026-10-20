# 安装 Flutter 版本管理 Finder 扩展

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与影响](#jobs-toc-heading-2)
- [二、日志与排查](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[独立安装入口](./【MacOS】安装Flutter版本管理Finder扩展.command) 只构建并启用本工程的“安装/切换 Flutter SDK（FVM）”菜单。需要完整 [**Xcode**](https://developer.apple.com/xcode) 与 macOS SDK。不会在安装扩展时下载 [**fvm**](https://fvm.app)、[**fzf**](https://formulae.brew.sh/formula/fzf) 或 [**Flutter**](https://flutter.dev/) SDK。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与影响 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击同目录 `.command` 或从 Terminal 执行。第一屏显示源码、产物、影响和日志位置；直接回车跳过，输入任意字符后回车才执行，`Ctrl+C` 取消。非交互输入拒绝执行。

确认后检查 Xcode 和 macOS SDK，在 `../work/DerivedData` 构建；构建阶段通过 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过自动注册。成功后注册固定 Bundle ID `com.jobs.JobsFlutterVersionMgr.FinderSyncExtension`，打开宿主并重启 Finder。保留构建产物路径，不随意移动已登记 App。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、日志与排查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

日志位于系统临时目录的 `JobsFlutterVersionMgrInstall.log`。构建失败先检查 Xcode 选择、首次启动和签名设置；脚本不会自动更改开发者目录或安装 Xcode。

菜单未出现时打开宿主的扩展设置并勾选，首次执行项目动作时允许 App 控制 Terminal。完整功能和目录说明见 [工程 README](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
