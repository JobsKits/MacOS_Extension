# 鸿蒙模拟器扩展脚本

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
| [CreateHarmonySimulator.zsh](./CreateHarmonySimulator.zsh) | 发现官方工具、检查 Mac ARM 和创建能力，选择本地 Release 镜像，保护名称、创建并查询验证后按需启动。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | Xcode 构建后注册当前 App / appex 并检查准确启用路径；可用跳过标志交给安装器统一注册，不创建模拟器。 |

## 一、<span id="run">业务入口与命令</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
/bin/zsh ./CreateHarmonySimulator.zsh --help
/bin/zsh ./CreateHarmonySimulator.zsh --check
/bin/zsh ./CreateHarmonySimulator.zsh --create
/bin/zsh ./CreateHarmonySimulator.zsh \
  --name JobsHarmony-phone \
  --no-start
```

`--check` 不要求交互，只调用 `-help`、`-imageList -downloaded true` 与 `-list -details`；不创建日志目录，不创建、启动或下载。正常入口先打印内置自述并等待回车，健康 fzf 优先、编号回退；设备类型和镜像均可回车选首项，名称默认唯一，创建前再次确认并重查现有名称。重复名称按大小写不敏感规则拒绝。业务日志在系统临时目录的 `JobsHarmonySimulator.*/CreateHarmonySimulator.log`。

`HARMONY_EMULATOR_BIN` 指定工具文件；`DEVECO_STUDIO_HOME` 或 `TOOL_HOME` 指定 DevEco / CLT 根目录。显式错误路径直接停止，保留现有设备。没有已下载 Release 镜像时引导用户在 DevEco Device Manager 下载后重新运行，本入口不执行 `-install`。启动保留官方许可 stdin，不传 `-force`、不自动回答。调用方式以[官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)及本机 `-help` 为准。

## 二、<span id="tests">隔离验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在工程目录执行：

```shell
ruby ./Tests/CreateHarmonySimulatorTests.rb
ruby ./Tests/InstallerRegistrationTests.rb
ruby ../Tests/HarmonySimulatorInstallerIntegrationTests.rb
ruby ../Tests/DesktopFinderMenuTests.rb
```

CLI 测试使用临时假 Emulator 与真实 zsh / JXA，覆盖 ARM / Rosetta、路径优先级、能力双检、镜像和实例 JSON、选择、大小写冲突、确认期间竞争、创建后复检、失败退出码与官方许可 stdin；不会联网、安装工具或操作真实设备。安装测试将系统命令替换为私有夹具。桌面测试直接编译菜单源码，以假 Finder 控制器验证真实桌面、普通目录、选中项、过期菜单与固定 URL。

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
