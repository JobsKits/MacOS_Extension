# 卸载 Flutter 版本管理 Finder 扩展

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、确认与边界](#jobs-toc-heading-2)
- [二、日志与恢复](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[独立卸载入口](./【MacOS】卸载Flutter版本管理Finder扩展.command) 停用并注销本工程 Finder 扩展，核验宿主 Bundle ID 后才删除已登记的 App 构建产物。保留工程源码、项目 `.fvmrc`、[**fvm**](https://fvm.app)、[**fzf**](https://formulae.brew.sh/formula/fzf) 及 [**Flutter**](https://flutter.dev/) SDK 缓存。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、确认与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

运行后先阅读内置自述并按回车，脚本列出 `com.jobs.JobsFlutterVersionMgr.FinderSyncExtension` 的注册路径及准备删除的 App。只有输入完整大写 `YES` 才继续；其它输入取消，非交互输入拒绝执行。

卸载只处理真实目录且 `CFBundleIdentifier` 为 `com.jobs.JobsFlutterVersionMgr` 的 `JobsFlutterVersionMgr.app`。完成后重启 Finder 刷新菜单。删除前必须先保存 Finder 中正在进行的文件工作。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、日志与恢复 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

日志位于系统临时目录的 `【MacOS】卸载Flutter版本管理Finder扩展.log`。注销失败或二次 Bundle ID 核验失败时停止，不扩大删除范围。需要恢复功能时，重新运行 [独立安装入口](../【MacOS】安装Flutter版本管理Finder扩展.command/README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
