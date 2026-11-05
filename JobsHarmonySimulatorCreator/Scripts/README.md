# Harmony 模拟器扩展脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、业务入口与命令](#run)
- [二、隔离验证](#tests)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录携带独立的官方 Emulator CLI 创建流程和 Finder 注册辅助脚本；运行时不读取 README，也不依赖其它仓库脚本。平台、安装入口及风险见[功能 README](../README.md)。

| 文件 | 职责 |
| --- | --- |
| [CreateHarmonySimulator.zsh](./CreateHarmonySimulator.zsh) | 发现兼容工具、缺失时从 SDL 安装并校验 Mac ARM64 CLT，检查创建能力，缺镜像时调用官方 CLI 下载选中的 Release 镜像，保护名称、创建并查询验证后按需启动。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | Xcode 构建后注册当前 App / appex 并检查准确启用路径；可用跳过标志交给安装器统一注册，不创建模拟器。 |


**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，默认 `build`。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。默认不清理；UI 仅在应用程序安装模式显示清理选项，退出该组合就清空。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## 一、<span id="run">业务入口与命令</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
/bin/zsh ./CreateHarmonySimulator.zsh --help
/bin/zsh ./CreateHarmonySimulator.zsh --check
/bin/zsh ./CreateHarmonySimulator.zsh --prepare
/bin/zsh ./CreateHarmonySimulator.zsh --create
/bin/zsh ./CreateHarmonySimulator.zsh \
  --name JobsHarmony_phone \
  --no-start
```

`--check` 不要求交互，只调用 `-help`、`-imageList -downloaded true` 与 `-list -details`；不创建日志目录，不创建、启动或下载。正常入口先打印内置自述并等待回车，健康 fzf 优先、编号回退；设备类型和镜像均可回车选首项，名称默认唯一，创建前再次确认并重查现有名称。重复名称按大小写不敏感规则拒绝；默认名称仅使用英文字母、数字和下划线。独立 CLT 创建完成后，为缺少 SDK 字段的新实例补同包 `sdkPath`，使 HDC 可用；不会改已有实例。业务日志在系统临时目录的 `JobsHarmonySimulator.*/CreateHarmonySimulator.log`。

华为官方下载中心获取模拟器配套工具需要登录；免登录替代源使用 [SDL 镜像](https://libsdl.org/harmonyos-devtools/)。Mac ARM64 固定 CLT 6.1.1.280，校验大小、固定 SHA-256、ZIP 路径和工具能力后新增独立目录。摘要来自 SDL 快照，系统镜像由官方 CLI 按所选项另行下载。完整说明见[功能 README](../README.md)。`HARMONY_CLT_ARCHIVE` 可复用同版本本地 ZIP，仍需校验。

`HARMONY_EMULATOR_BIN` 指定工具文件；`DEVECO_STUDIO_HOME` 或 `TOOL_HOME` 指定 DevEco / CLT 根目录。显式错误路径直接停止，保留现有设备。没有已下载 Release 镜像时查询官方可下载清单，回车默认选最新稳定版手机镜像；展示随附协议原文并由本人回车同意后执行 `-license accept`，再执行 `-install ... -force`。仅镜像安装省略重复确认，创建与启动不传 `-force`；工具包、官方在线清单和镜像获取失败默认自动持续重试，间隔从 2 秒递增到最多 30 秒，无次数或总时长上限；不重复已经完成的版本选择与许可确认，保留下载进度与逐次日志，Ctrl+C 可终止。明确本地权限、磁盘、版本或许可错误停止。安装器退出零仍须验证本地选中镜像，未出现时继续自动获取，就绪后才继续创建。启动保留 stdin 处理官方额外交互。调用方式以[官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)及本机 `-help` 为准。

`JOBS_SDK_RETRY_DELAY` / `JOBS_SDK_RETRY_MAX_DELAY` 可配置重试初始间隔 / 最大间隔，默认 2 / 30 秒；不设置总次数或总时长上限。当前操作日志保留终端原始详情，相邻的 `.attempts.log` 追加各次获取结果。Ctrl+C / TERM / HUP 停止本轮获取子进程与后续重试，已安装 SDK 和设备保留。

## 二、<span id="tests">隔离验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在工程目录执行：

```shell
ruby ./Tests/CreateHarmonySimulatorTests.rb
ruby ./Tests/InstallerRegistrationTests.rb
ruby ../Tests/HarmonySimulatorInstallerIntegrationTests.rb
ruby ../Tests/DesktopFinderMenuTests.rb
```

CLI 测试使用临时假 Emulator 与真实 zsh / JXA，覆盖 ARM / Rosetta、路径优先级、能力双检、镜像和实例 JSON、选择、大小写冲突、确认期间竞争、创建后复检、失败退出码与官方许可 stdin；不会联网或操作真实设备；安装回归仅在临时 HOME 中解压小型假工具包。安装测试将系统命令替换为私有夹具。桌面测试直接编译菜单源码，以假 Finder 控制器验证真实桌面、普通目录、选中项、过期菜单与固定 URL。

原生 URL / 私有载体回归可使用系统临时目录编译：

```shell
native_test_dir="$(mktemp -d)"
xcrun swiftc \
  ./JobsHarmonySimulatorShared/HarmonySimulatorMenuContext/HarmonySimulatorMenuContext.swift \
  ./JobsHarmonySimulatorShared/HarmonySimulatorRequest/HarmonySimulatorRequest.swift \
  ./JobsHarmonySimulatorCreator/HarmonySimulatorModel/HarmonySimulatorModel.swift \
  ./JobsHarmonySimulatorCreator/HarmonySimulatorTerminalLauncher/HarmonySimulatorTerminalLauncher.swift \
  ./Tests/HarmonySimulatorTransportTests.swift \
  -o "$native_test_dir/TransportTests"
"$native_test_dir/TransportTests"
xcrun swiftc \
  ./JobsHarmonySimulatorShared/HarmonySimulatorRequest/HarmonySimulatorRequest.swift \
  ./JobsHarmonySimulatorCreator/AppDelegate.swift \
  ./Tests/HarmonySimulatorAppDelegateTests.swift \
  -o "$native_test_dir/AppDelegateTests"
"$native_test_dir/AppDelegateTests"
```

这些测试不会运行真实宿主、Terminal 自动化或启用扩展。Debug 构建若另行使用 Xcode，应设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 并采用私有临时 DerivedData；Xcode 仍可能自动登记 App / appex，验证后须仅注销本次精确 App 路径，并对账原注册记录，不能将此构建当作安装。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
