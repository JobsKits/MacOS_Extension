# 卸载 Git 拉取 Finder 扩展

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

[独立卸载入口](./【MacOS】卸载Git拉取Finder扩展.command) 停用并注销“拉取 Git 到最新”右键菜单，核验宿主 Bundle ID 后删除已登记 App 构建产物。保留工程源码、目标 [**Git**](https://git-scm.com/) 仓库和拉取运行日志。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、确认与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击同目录 `.command`，先阅读内置自述并按回车。脚本列出 `com.jobs.JobsGitPuller.FinderSyncExtension` 的注册路径及准备删除的 App，完整输入大写 `YES` 才执行卸载；其它输入取消，非交互输入停止，`Ctrl+C` 随时取消。

删除前再次核对 `JobsGitPuller.app` 为真实目录且 `CFBundleIdentifier` 为 `com.jobs.JobsGitPuller`。注销失败或核验变化时停止。完成后重启 Finder 刷新菜单，操作前保存 Finder 中正在进行的文件工作。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、日志与恢复 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

日志位于系统临时目录，文件名为 `【MacOS】卸载Git拉取Finder扩展.log`。需要恢复功能时，运行 [独立安装入口](../【MacOS】安装Git拉取Finder扩展.command/README.md)。完整功能见 [工程说明](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
