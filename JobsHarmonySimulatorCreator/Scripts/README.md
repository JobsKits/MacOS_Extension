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

本目录携带独立的官方 Emulator CLI 创建流程和 Finder 注册辅助脚本；运行时不读取 README，也不依赖其它仓库脚本。平台、安装入口及风险见[功能 README](../README.md)。

| 文件 | 职责 |
| --- | --- |
| [CreateHarmonySimulator.zsh](./CreateHarmonySimulator.zsh) | 发现兼容工具、缺失时从 SDL 安装并校验 Mac ARM64 CLT，检查创建能力，缺镜像时调用官方 CLI 下载选中的 Release 镜像，保护名称、创建并查询验证后按需启动。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | Xcode 构建后注册当前 App / appex 并检查准确启用路径；可用跳过标志交给安装器统一注册，不创建模拟器。 |

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

`HARMONY_EMULATOR_BIN` 指定工具文件；`DEVECO_STUDIO_HOME` 或 `TOOL_HOME` 指定 DevEco / CLT 根目录。显式错误路径直接停止，保留现有设备。没有已下载 Release 镜像时查询官方可下载清单，回车默认选最新稳定版手机镜像；展示随附协议原文并由本人回车同意后执行 `-license accept`，再执行 `-install ... -force`。仅镜像安装省略重复确认，创建与启动不传 `-force`；安装后必须在本地清单验证所选类型与版本，失败即停止，不循环复检。启动保留 stdin 处理官方额外交互。调用方式以[官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)及本机 `-help` 为准。

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
