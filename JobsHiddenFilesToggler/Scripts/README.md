# `JobsHiddenFilesToggler / Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、编译后启用](#build-helper)
- [二、跳过开关、日志与失败](#skip-and-logs)
- [三、安装与验证入口](#entrypoints)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

> 本目录只承载 [**Xcode**](https://developer.apple.com/xcode) 编译后的扩展启用脚本。实际隐藏文件偏好切换在 [后台宿主源码](../JobsHiddenFilesToggler/) 内实现，不依赖外部业务脚本。

## 一、<span id="build-helper">编译后启用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

`EnableFinderExtension.zsh` 由工程的 `Enable Finder Extension` 编译阶段调用，利用 `TARGET_BUILD_DIR` 与 `WRAPPER_NAME` 定位当前 `JobsHiddenFilesToggler.app` 和其中的 `JobsHiddenFilesFinderSync.appex`。

脚本先输出内置自述，核验构建上下文，再停止当前用户的旧宿主、注册并启用固定 ID `com.jobs.hiddenfilestoggler.findersync`。只有状态查询确认当前产物路径已启用，才刷新当前用户 [**Finder**](https://support.apple.com/guide/mac-help/welcome/mac)。注册、启用或刷新失败时保留待刷新标记并记录诊断，不自动操作隐藏文件偏好。

脚本没有完整构建上下文时拒绝修改扩展，不支持把任意 App 路径作为参数传入。

## 二、<span id="skip-and-logs">跳过开关、日志与失败</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 配置 / 文件 | 行为 |
| --- | --- |
| `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` | 跳过编译后注册、启用与 Finder 刷新；独立和总管理器负责后续注册 |
| `JobsHiddenFilesTogglerBuildPhase.log` | 系统临时目录中的构建后启用日志 |
| `JobsHiddenFilesTogglerNeedsFinderRestart` | 系统临时目录中的初始化未完成标记 |

启用失败不阻断源码编译；构建成功与扩展已启用必须分别核对。后台宿主收到 `--initialize-finder-extension` 后只核验并初始化扩展，不切换显示偏好；外层安装器统一负责刷新 Finder。

即使设置跳过开关，Xcode 自身仍可能临时登记构建 App。隔离构建验证应按本次精确产物路径清理临时系统登记，不能据跳过脚本推断系统登记必然没有变化。

## 三、<span id="entrypoints">安装与验证入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

日常安装与卸载统一使用 [独立管理入口](../【MacOS】管理显示隐藏文件Finder扩展.command)，与功能 [README](../README.md) 平级。终端只唤起 GUI 后结束，在面板选定安装 / 更新或卸载并点击按钮执行，不要求终端二次确认。

在功能根目录运行隔离测试，不会真实注册或刷新：

```shell
/bin/zsh ./Tests/run.zsh
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
