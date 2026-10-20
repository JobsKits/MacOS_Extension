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
| 无参数运行 | 自述确认 → 选择完整 iPhone / iPad 型号 → 选择已安装 iOS 系统 → 回车创建并启动 |
| `--help` | 显示说明，不探测工具链或写日志 |
| `--check` | 只读检查当前 Xcode、simctl、模拟器界面、完整机型数量与可用系统，不创建设备 |
| 本机已有健康 fzf | 使用可搜索的选择列表，Esc 取消 |
| 本机没有可用 fzf | 自动使用编号列表，输入 q 或直接回车取消；不安装额外工具 |

机型来源与独立初始化脚本相同，均为当前 Xcode 的 `simctl list devicetypes`；两个入口使用逐字节相同的 JSON 解析和创建核心，保留完整 iPhone / iPad。先选机型，再选 Runtime，最后由 `simctl create` 判断组合是否支持。`supportedDeviceTypes`、最小 / 最大系统版本及 `productFamily` 不用于提前隐藏型号。

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

3、读取 `simctl list ... --json`。从完整设备类型清单按名称取得 iPhone / iPad，按标识去重并保留原顺序，先选择机型；再选择可用且支持本机架构的 iOS Runtime，系统按展示名和标识去重。机型和系统独立列出，不把最新 Runtime 的支持范围误当成 Xcode 的全部型号；正常流程两张列表各选一次，创建时由 `simctl create` 最终校验。

4、自动命名为 `设备名@年月日 时:分:秒-进程编号`，并刷新所有既有设备名称；冲突时追加数字后缀。格式示例：`iPhone 18 Pro@2026.10.20 21:30:00-12345`。不同终端同时运行也不会只因同秒操作而使用同一默认名称。

5、展示设备、系统和新名称。直接回车创建；任意非空输入（包括空格）、EOF 或 Ctrl+C 取消。选择阶段不会新增设备。

6、调用 `simctl create`、`boot`，打开当前 Xcode 的模拟器界面，并等待 `bootstatus` 确认启动。Device Hub 打开后按打印的设备名或 UDID 选中，不依赖未核实的深层 URL 或启动参数。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、来源与安全边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务规范源为 `JobsCommand@iOS/其他/【MacOS】📱双击初始化iOS模拟器.command/【MacOS】📱双击初始化iOS模拟器.command`。两侧 `# >>> Jobs iOS simulator core >>>` 到对应结束标记之间的状态与函数逐字节一致：完整 iPhone / iPad、Runtime 去重、自动命名、创建启动、不兼容组合的明确重选、退出码和只读体检均在该核心内。自述和 `main` 等入口编排位于标记外。维护核心时先改独立规范源，再完整同步此标记块到右键脚本；一致性测试拒绝两侧不同的实现。

两侧都携带完整核心，不依赖外部公共库或另一仓库的运行时路径。独立入口在创建前保留原有清场、Homebrew / fzf 自检；右键入口不执行这些前置动作。独立入口的 `--help` / `--check` 提前进入只读分支，绕过清场和依赖安装。

以本机 2026-10-20 的只读快照为例：iOS 27.1 的 `supportedDeviceTypes` 只有 iPhone Duo，iOS 27.0 有 62 种设备；完整 `devicetypes` 按名称取得 45 种 iPhone 和 43 种 iPad。先按 27.1 筛选只会显示 Duo，完整型号优先的流程仍可选择传统 iPhone 再搭配 27.0。清单因机器和组件而异，显示型号不代表它能与每个系统组合。`--check` 只验证两份独立清单可读，不创建探测设备或宣称所有组合兼容。

目标机器需取得更新后的源码并重新运行安装器，才能把新脚本打包进宿主 App；修改工程中的脚本不会自动更新已安装的旧 App 资源。

原脚本的清场、Homebrew / fzf 安装升级不属于本入口的执行范围。脚本只新增设备，不关闭、删除、擦除或重置既有模拟器，不下载 Runtime，不更改 `xcode-select`、Shell 配置或网络代理。缺少组件时提示在 Xcode 中准备后重试。

创建命令明确返回 `Incompatible device` 时显示原始错误，只有精确输入 `r` / `R` 才回到选择；直接回车、其它输入或 EOF 均停止并返回失败。泛化的 `Unable to create a device for device type` 不能证明组合不兼容，与其它失败或无法确认的返回值一样立即停止。连续回车不会自动弹出第二轮列表或再次执行创建。新设备创建后即使启动、界面打开或等待失败也保留设备并打印 UDID。多数只读命令限时 20–30 秒，启动完成等待上限 120 秒；超时只停止本次命令。

交互日志为 `$TMPDIR/CreateIOSSimulator.<进程编号>.log`，确认后才创建；终端业务输出同步记录为纯文本。每次私有 JSON 快照在退出时清理，`--help` / `--check` 不创建持久日志。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、隔离验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```shell
/bin/zsh -n ./Scripts/CreateIOSSimulator.zsh
/usr/bin/ruby ./Tests/CreateIOSSimulatorCommandTests.rb
```

对独立规范源运行同一套隔离回归（源文件路径由环境变量显式指定）：

```shell
JOBS_SIMULATOR_TEST_SCRIPT='../../../JobsCommand@iOS/其他/【MacOS】📱双击初始化iOS模拟器.command/【MacOS】📱双击初始化iOS模拟器.command' \
  /usr/bin/ruby ./Tests/CreateIOSSimulatorCommandTests.rb
```

默认一致性检查定位同一 `JobsGenesis` 下的独立脚本；源码放在其它位置时用 `JOBS_SIMULATOR_SOURCE` 指定。仅复制本工程而缺少规范源时，该项明确跳过，其余隔离回归仍可独立执行；业务运行不依赖此路径。

测试执行真实 zsh / 系统 JSON 解析代码，将 `xcrun`、`open` 和 `fzf` 替换为私有假命令，覆盖完整机型、Duo 单项 Runtime 名单下选择传统型号与旧系统、元数据差异、去重、损坏工具、编号 / fzf 取消、完整创建流程、参数引用、启动失败、Device Hub 新布局与超时；同时验证正常流程只选择一轮、创建失败后连续回车不重弹，以及精确 `r` / `R` 重选。测试不会新增、启动或清理真实模拟器；真实 Finder 菜单、系统权限和 GUI 操作另按安装后的实际机器验收。

宿主去重测试单独编译真实 AppDelegate 与测试文件内的假 Model，不与生产 `IOSSimulatorModel.swift` 一起编译；它只在内存中模拟 URL 回调，不打开 Terminal 或注册扩展。从本工程目录执行：

```shell
simulator_test_dir="$(mktemp -d "${TMPDIR:-/tmp}/JobsIOSSimulatorAppDelegateTests.XXXXXX")"
swiftc \
  ./JobsIOSSimulatorCreator/AppDelegate.swift \
  ./JobsIOSSimulatorShared/IOSSimulatorRequest/IOSSimulatorRequest.swift \
  ./Tests/IOSSimulatorAppDelegateTests.swift \
  -o "$simulator_test_dir/IOSSimulatorAppDelegateTests"
"$simulator_test_dir/IOSSimulatorAppDelegateTests"
```

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、构建后启用入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[`EnableFinderExtension.zsh`](./EnableFinderExtension.zsh) 由本工程 Xcode Build Phase 调用，注册并启用当前产物中的固定扩展；只按当前 appex 精确路径判断成功，失败保留待刷新标记与诊断日志。设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 会跳过注册与刷新，供总安装器接管或隔离构建使用；手动无构建上下文时拒绝执行。日志名为系统临时位置中的 `JobsIOSSimulatorCreatorBuildPhase.log`。

独立安装与构建后启用的命令替身回归：

```shell
/usr/bin/ruby ./Tests/InstallerRegistrationTests.rb
```

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
