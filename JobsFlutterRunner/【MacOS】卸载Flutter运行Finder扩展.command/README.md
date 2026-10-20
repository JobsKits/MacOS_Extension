# 卸载 Flutter 运行 Finder 扩展

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、操作与范围](#jobs-toc-heading-2)
- [二、日志与恢复](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

双击同目录 `【MacOS】卸载Flutter运行Finder扩展.command`，禁用并注销[运行 Flutter 项目](../README.md)菜单，移除经固定 App 名与 Bundle ID 核验的已登记宿主。保留项目源码、Flutter SDK 与后台运行会话。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、操作与范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

先阅读自述并回车，脚本只读查询本扩展真实注册路径；核对后输入精确 `YES` 才执行卸载，其它输入取消。取消前不修改 App 或注册；非交互输入退出。

确认后仅停用 `com.jobs.JobsFlutterRunner.FinderSyncExtension`，停止对应宿主和 Finder 扩展进程，注销已列出的扩展，并删除二次核验通过的 `JobsFlutterRunner.app`，最后重启 Finder。不会删除工程源码、Flutter SDK、模拟器或会话日志。

后台 Flutter 已由 launchd 独立托管，卸载 Finder 扩展不停止它。需要停止时，卸载前重新右键同一项目并选择同一设备，在终端输入 `s`；相关生命周期见[工程说明](../README.md#lifecycle)。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、日志与恢复 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

系统临时目录保存与脚本同名的 `.log`，运行时打印精确位置。注销或 App 核验失败会停止并保留诊断，不扩大删除范围。之后可重新运行[独立安装入口](../【MacOS】安装Flutter运行Finder扩展.command/README.md)恢复菜单。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
