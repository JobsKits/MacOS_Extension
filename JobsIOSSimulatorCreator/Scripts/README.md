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
| 无参数运行 | 自述确认 → 完整机型中可搭配系统的型号优先 → 匹配系统 → 回车创建并启动 |
| `--help` | 显示说明，不探测工具链或写日志 |
| `--check` | 只读检查当前 Xcode、simctl、模拟器界面、完整机型、可搭配 / 无可搭配机型数量、每个可用系统支持的机型数及回车首选组合，不创建设备 |
| 本机已有健康 fzf | 使用可搜索的选择列表，回车确认高亮项；系统面板 `←` 返回型号，Esc / Ctrl+C 取消；仅对子进程移除外部默认选项 |
| 本机没有可用 fzf | 交互入口明确报错并停止，提示独立入口的依赖自检或人工修复，不继续编号选择，也不安装额外工具；`--help` / `--check` 仍可只读运行 |

机型来源与独立初始化脚本相同，均为当前 Xcode 的 `simctl list devicetypes`；两个入口使用逐字节相同的 JSON 解析和创建核心，保留完整 iPhone / iPad。兼容性只调整机型推荐顺序，不隐藏传统型号；本机没有任何已装系统可搭配的型号带“（本机无可搭配系统）”标注，选择前即可识别。选定机型后只列匹配该型号的 Runtime 并打印“已装 N 个 / 匹配 M 个”，确认支持的最新版本排首位，未被明确列出的系统带“（未确认支持）”标注，最终确认前提示风险，最后由 `simctl create` 校验。

Runtime 有效非空 `supportedDeviceTypes` 名单明确包含 / 排除时优先采用该结论；字段缺失、空数组或不完整且未匹配时，再用机型有效的最小 / 最大版本排除越界项。范围内的未知候选保留，排在已确认支持的系统之后。默认组合来自本机数据，不按固定型号或版本硬编码。

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

3、读取 `simctl list ... --json`。从完整设备类型清单按名称取得 iPhone / iPad，按标识去重；存在确认支持的已装系统的机型优先，其次是兼容信息未知的机型，最后是暂时没有可搭配系统的机型，组内保留原顺序，本机无可搭配系统的型号带“（本机无可搭配系统）”标注。选定型号后匹配本机可用且支持当前架构的 Runtime，并打印“本机已装 N 个 iOS 系统，其中 M 个匹配该型号”；按展示名和标识去重，确认支持组优先，组内按版本从新到旧，未确认支持的系统带“（未确认支持）”标注。型号与系统列表回车均采用首项；没有可搭配系统时明确提示并停止，输入 `r` / `R` 可回到机型选择，不尝试已知不兼容组合。

4、自动命名为 `设备名@年月日 时:分:秒-进程编号`，并刷新所有既有设备名称；冲突时追加数字后缀。格式示例：`iPhone 18 Pro@2026.10.20 21:30:00-12345`。不同终端同时运行也不会只因同秒操作而使用同一默认名称。

5、展示设备、系统和新名称。直接回车创建；任意非空输入（包括空格）、EOF 或 Ctrl+C 取消。选择阶段不会新增设备。

6、调用 `simctl create`、`boot`，打开当前 Xcode 的模拟器界面，并等待 `bootstatus` 确认启动。Device Hub 打开后按打印的设备名或 UDID 选中，不依赖未核实的深层 URL 或启动参数。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、来源与安全边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务规范源为 `JobsCommand@iOS/其他/【MacOS】📱双击初始化iOS模拟器.command/【MacOS】📱双击初始化iOS模拟器.command`。两侧 `# >>> Jobs iOS simulator core >>>` 到对应结束标记之间的状态与函数逐字节一致：完整 iPhone / iPad、Runtime 去重、自动命名、创建启动、不兼容组合的明确重选、退出码和只读体检均在该核心内。自述和 `main` 等入口编排位于标记外。维护核心时先改独立规范源，再完整同步此标记块到右键脚本；一致性测试拒绝两侧不同的实现。

两侧都携带完整核心，不依赖外部公共库或另一仓库的运行时路径。独立入口在创建前保留原有清场、Homebrew / fzf 自检；右键入口不执行这些前置动作。独立入口的 `--help` / `--check` 提前进入只读分支，绕过清场和依赖安装。

以本机 2026-10-21 的只读快照为例：iOS 27.1 的 `supportedDeviceTypes` 只有 iPhone Duo，iOS 27.0 有 62 种设备；完整 `devicetypes` 按名称取得 45 种 iPhone 和 43 种 iPad。交互仍保留全部 88 个型号，其中 63 个已有可搭配系统，25 个（iPhone 8 / 7 / 6s、iPad Air 2 等老型号）带“（本机无可搭配系统）”标注；默认 iPhone 18 Pro 的系统首项为 27.0，并提示“本机已装 2 个 iOS 系统，其中 1 个匹配该型号”；若只装了支持 Duo 的系统，则将 Duo 排到机型首项，传统机型仍保留供查看。`--check` 展示本机机型匹配数量、每个系统支持的机型数及回车首选组合，不创建探测设备，也不宣称未知组合一定兼容。

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

测试执行真实 zsh / 系统 JSON 解析代码，将 `xcrun`、`open` 和 `fzf` 替换为私有假命令，覆盖完整机型稳定推荐、fzf 首选兼容组合、Duo 单 Runtime 推荐、白名单与兼容字段 / 版本范围、机型和系统标注、确认前风险提示、无系统时精确 `r` 重选、数量汇总、去重、创建启动、参数引用、失败及超时。选择器额外验证 `←` 返回型号、无匹配时返回、返回后取消、空选、未知行、依赖缺失 / 损坏及异常状态传播；正常流程只选择一轮，创建失败不会自动重弹。测试不会新增、启动或清理真实模拟器；真实 Finder 菜单、系统权限和 GUI 操作另按安装后的实际机器验收。

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
