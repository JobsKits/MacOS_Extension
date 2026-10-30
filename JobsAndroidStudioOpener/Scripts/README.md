# `JobsAndroidStudioOpener 构建脚本`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、真实入口与结果](#jobs-toc-heading-2)
- [二、环境与副作用](#jobs-toc-heading-3)
- [三、日志与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录只负责 Xcode 构建后启用当前工程的 Finder 扩展，用户安装 / 卸载入口及业务行为见 [功能说明](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、真实入口与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[EnableFinderExtension.zsh](./EnableFinderExtension.zsh) 由 Xcode Build Phase 调用，使用 TARGET_BUILD_DIR / WRAPPER_NAME 定位当前 App 的内嵌 appex；对应扩展 ID 为 `com.jobs.JobsAndroidStudioOpener.FinderSyncExtension`。依次处理旧宿主、注册与启用当前产物、状态检查及 Finder 刷新。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、环境与副作用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要完整 macOS / Xcode 构建上下文、系统 zsh、PlugInKit、open 等工具。`JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 由外层安装器或隔离构建设置时跳过此阶段注册；不等于禁止 Xcode 自身的其它系统登记。手动无上下文时只允许检查提示，不应伪造路径运行。

脚本可停止本功能宿主并重启 Finder，真实安装使用上级入口；不安装 Android/Flutter 工具，不操作目标工程源码。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

日志为系统临时目录中的 `JobsAndroidStudioOpenerBuildPhase.log`；启用失败时按脚本的刷新标记与用户系统设置排查。静态说明不等于扩展已成功签名、加载或菜单已在 Finder 验收；本文未运行注册或 Finder 重启。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
