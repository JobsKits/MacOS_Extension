# 新建 iOS 模拟器脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#jobs-toc-heading-2)
- [二、来源与安全边界](#jobs-toc-heading-3)
- [三、隔离验证](#jobs-toc-heading-4)
- [四、构建后启用入口](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

此目录由 [**macOS**](https://www.apple.com/macos/) Finder 扩展宿主调用；核心业务全部位于 [`CreateIOSSimulator.zsh`](./CreateIOSSimulator.zsh)，复制单个脚本也能独立运行，不依赖原始 `JobsCommand@iOS` 目录或当前工作目录。

| 入口 / 行为 | 实际结果 |
| --- | --- |
| 无参数运行 | 自述确认 → 选择已安装 iOS 系统 → 选择兼容 iPhone / iPad → 回车创建并启动 |
| `--help` | 显示说明，不探测工具链或写日志 |
| `--check` | 只读检查当前 Xcode、simctl、模拟器界面与兼容清单，不创建设备 |
| 本机已有健康 fzf | 使用可搜索的选择列表，Esc 取消 |
| 本机没有可用 fzf | 自动使用编号列表，输入 q 或直接回车取消；不安装额外工具 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从本工程目录执行：

```shell
/bin/zsh ./Scripts/CreateIOSSimulator.zsh
```

只读检查：

```shell
/bin/zsh ./Scripts/CreateIOSSimulator.zsh --check
```

1、确认前只展示内置自述。无可交互终端时直接停止；只有 `--help` / `--check` 可用于非交互调用。

2、检查当前 [**Xcode**](https://developer.apple.com/xcode/) 的 `xcrun simctl`、系统 JavaScript for Automation，以及同一 Xcode 内的模拟器界面。支持传统 `Simulator.app` 与新版 [**Device Hub**](https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub)，通过 Bundle ID 和实际可执行文件核验，不跨 Xcode 混用应用。

3、读取 `simctl list ... --json`。仅显示可用且支持本机架构的 iOS Runtime，按展示名和标识去重；先选系统，再根据 `supportedDeviceTypes` 筛选兼容 iPhone / iPad。旧版 Xcode 缺少白名单时使用已有最小 / 最大版本信息，没有范围信息的设备留给创建命令最终校验。

4、自动命名为 `设备名@年月日 时:分:秒-进程编号`，并刷新所有既有设备名称；冲突时追加数字后缀。格式示例：`iPhone 18 Pro@2026.10.20 21:30:00-12345`。不同终端同时运行也不会只因同秒操作而使用同一默认名称。

5、展示设备、系统和新名称。直接回车创建；任意非空输入（包括空格）、EOF 或 Ctrl+C 取消。选择阶段不会新增设备。

6、调用 `simctl create`、`boot`，打开当前 Xcode 的模拟器界面，并等待 `bootstatus` 确认启动。Device Hub 打开后按打印的设备名或 UDID 选中，不依赖未核实的深层 URL 或启动参数。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、来源与安全边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务来源为 `JobsCommand@iOS/其他/【MacOS】📱双击初始化iOS模拟器.command/【MacOS】📱双击初始化iOS模拟器.command`。保留选择设备和 Runtime、Runtime 去重、自动命名、创建启动，以及不兼容组合回选；新增 iPad、结构化 JSON、兼容性预筛选、明确的退出码和只读体检。

原脚本的清场、Homebrew / fzf 安装升级不属于本入口的执行范围。脚本只新增设备，不关闭、删除、擦除或重置既有模拟器，不下载 Runtime，不更改 `xcode-select`、Shell 配置或网络代理。缺少组件时提示在 Xcode 中准备后重试。

创建命令只有明确返回组合不兼容才回到选择；其它失败或无法确认的返回值立即停止，避免自动重试产生重复设备。新设备创建后即使启动、界面打开或等待失败也保留设备并打印 UDID。多数只读命令限时 20–30 秒，启动完成等待上限 120 秒；超时只停止本次命令。

交互日志为 `$TMPDIR/CreateIOSSimulator.<进程编号>.log`，确认后才创建；终端业务输出同步记录为纯文本。每次私有 JSON 快照在退出时清理，`--help` / `--check` 不创建持久日志。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、隔离验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```shell
/bin/zsh -n ./Scripts/CreateIOSSimulator.zsh
/usr/bin/ruby ./Tests/CreateIOSSimulatorCommandTests.rb
```

测试执行真实 zsh / 系统 JSON 解析代码，将 `xcrun`、`open` 和 `fzf` 替换为私有假命令，覆盖去重、兼容筛选、损坏工具、编号 / fzf 取消、完整创建流程、参数引用、启动失败、Device Hub 新布局与超时。测试不会新增、启动或清理真实模拟器；真实 Finder 菜单、系统权限和 GUI 操作另按安装后的实际机器验收。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、构建后启用入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[`EnableFinderExtension.zsh`](./EnableFinderExtension.zsh) 由本工程 Xcode Build Phase 调用，注册并启用当前产物中的固定扩展；只按当前 appex 精确路径判断成功，失败保留待刷新标记与诊断日志。设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 会跳过注册与刷新，供总安装器接管或隔离构建使用；手动无构建上下文时拒绝执行。日志名为系统临时位置中的 `JobsIOSSimulatorCreatorBuildPhase.log`。

独立安装与构建后启用的命令替身回归：

```shell
/usr/bin/ruby ./Tests/InstallerRegistrationTests.rb
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
