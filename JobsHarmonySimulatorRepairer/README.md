# `JobsHarmonySimulatorRepairer`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能与范围](#capabilities)
- [二、安装与卸载](#installation)
  - [【MacOS】安装Harmony模拟器检测修复Finder扩展.command](#jobs-toc-heading-4)
  - [【MacOS】卸载Harmony模拟器检测修复Finder扩展.command](#jobs-toc-heading-5)
- [三、直接使用](#usage)
- [四、备份、恢复与结果判断](#backup)
- [五、隔离验证](#verification)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

为 [**macOS**](https://www.apple.com/macos/) 系统桌面空白右键提供 **Harmony 模拟器检测与修复**。独立 App + [**Finder Sync Extension**](https://developer.apple.com/documentation/findersync)，通过可见 Terminal 使用 [**Huawei DevEco Emulator**](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line) 官方命令处理本机已有实例。核心随 App 打包，拷走本目录也可独立安装。

## 一、<span id="capabilities">功能与范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 操作 | 行为与确认 |
| --- | --- |
| 只读诊断 | 检测官方 CLI 能力、已下载 Release 镜像、唯一实例身份、`isRunning`、实例配置与 SDK / HDC 版本；不写本工具日志。异常返回非零。 |
| 启动选中实例 | 再次核对同名同路径的官方登记，回车启动；轮询 `isRunning=true` 才报告运行状态通过。 |
| 保留数据冷启动修复 | 输入精确 `YES`；运行中先执行 `-stop NAME` 并等到 `isRunning=false`，再执行 `-start NAME -bootMode coldboot`，轮询运行状态。适用于快照或启动异常；保留安装的应用、上传文件等既有数据。 |
| 修复失效 SDK 路径 | 输入 `YES`，要求全部模拟器关闭；完整备份单一实例后，将缺失 / 失效的 `config.ini` SDK 路径指向同一 DevEco / CLT 内已通过 HDC 版本检测的 SDK。保留其余配置。 |

不下载或升级工具、接受许可、删除应用、清锁、清空用户数据或调整容量；不修改系统代理、全局 SDK 或 Shell 配置。未知官方字段、重复名称、不可靠路径、符号链接、失败退出码均停止。选中后固定官方 UUID、产品类型、系统版本及目录 / 配置的文件身份，确认期间同名重建也不能沿用旧请求。真机不在 Emulator 本地实例清单中，不会进入动作目标。

菜单仅在系统桌面空白处显示；普通目录背景、文件、多选、工具栏或侧边栏不提供。需要创建实例时使用[新建 Harmony 模拟器](../JobsHarmonySimulatorCreator/README.md)。

## 二、<span id="installation">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

菜单构建需要 macOS 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 与可用签名环境；本地 Harmony 模拟器要求 Apple Silicon 原生终端及已有 DevEco 工具。冷启动修复额外要求 CLI 声明 `-bootMode` 能力，官方从 DevEco Studio 6.1.0 Release 支持。首次启动涉及官方许可或账号要求时，先在 DevEco Device Manager 完成；本工具不会自动同意。

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">[【MacOS】安装Harmony模拟器检测修复Finder扩展.command](./【MacOS】安装Harmony模拟器检测修复Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 独立构建并启用本功能，刷新 Finder。

- 阅读内置自述，直接回车安装；任意非空输入（含空格）跳过，Ctrl+C / 输入结束停止。
- 检查 Xcode，构建到 `./work/DerivedData/Build/Products/Debug/JobsHarmonySimulatorRepairer.app`，核对 Bundle ID 与签名。
- 注册和启用该 App 内扩展并刷新 Finder；产物为实际加载位置，安装后保留。
- 安装日志为系统临时目录的 `JobsHarmonySimulatorRepairerInstall.log`。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">[【MacOS】卸载Harmony模拟器检测修复Finder扩展.command](./【MacOS】卸载Harmony模拟器检测修复Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 精确停用并注销本功能，移除身份核对后的已登记 App。

- 阅读自述，预览路径后输入 `YES` 才卸载并刷新 Finder。
- 只处理 `com.jobs.harmonysimulatorrepairer` 及其 `.findersync` 扩展，保留源码、SDK、镜像、实例、备份和业务日志。
- 日志位于系统临时目录，与卸载脚本同名、扩展名为 `.log`。

也可通过[总安装面板](../README.md)勾选本功能，标识为 `harmony-simulator-repair`。首次从右键派发需要允许本 App 控制 Terminal。

## 三、<span id="usage">直接使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下命令在本 README 所在目录运行。

```shell
/bin/zsh ./Scripts/RepairHarmonySimulator.zsh
```

只读检查全部或指定实例：

```shell
/bin/zsh ./Scripts/RepairHarmonySimulator.zsh \
  --check \
  --name JobsHarmony_Test
```

`--repair` 为默认交互模式；`--help` / `-h` 只显示帮助。多实例时按编号选择，回车默认第一项；动作菜单回车 / `q` 结束。SDK 修复和冷启动均需精确 `YES`，没有自动确认开关。

工具发现优先显式 `HARMONY_EMULATOR_BIN`，其次 `DEVECO_STUDIO_HOME` / `TOOL_HOME`，默认搜索常见 DevEco 安装、`~/Library/Application Support/JobsHarmonySimulator/clt-*/emulator/Emulator` 和 PATH。候选必须通过官方能力检查；显式坏路径或多个健康候选停止，避免误用 Android emulator 或切换 SDK。

交互日志位于系统临时目录的 `JobsHarmonySimulatorRepairer.XXXXXX/RepairHarmonySimulator.log`；宿主诊断为 `/tmp/JobsHarmonySimulatorRepairer.log`。`--check` 不创建本工具日志、备份或临时配置。

## 四、<span id="backup">备份、恢复与结果判断</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

SDK 修复只处理官方清单中路径尾部与名称一致的普通实例目录，配置须含唯一匹配 `name=`。重复 SDK 键、链接目录 / 内容、仍在运行或无法读取进程表时拒绝写入；保守要求所有 Harmony / Android 模拟器退出。预留完整备份容量加 1 GB 余量，备份保存到实例父目录的 `.<名称>.jobs-repair-backup.XXXXXX/instance/`，逐文件比较后再次核对身份、停机状态、原配置摘要，才原子替换失效 SDK 键。备份不自动删除。SDK 路径拒绝控制字符及非规范链接路径；发布前再次检查身份、停机与原配置摘要，外部变更则保留原文件、备份及候选配置。

恢复时先正常关闭对应模拟器并保留当前现场，再将备份 `instance/config.ini` 恢复到原实例；本功能只改这一份配置，不修改 userdata。若发现其他内容也已被外部操作改变，应先核对完整备份，避免覆盖后续用户数据。

冷启动不使用 `reset`，停止失败或状态未变为 false 时绝不继续启动；启动失败、实例路径变化、JSON 未知或状态轮询超时返回非零。`isRunning=true` 只证明官方报告实例运行，系统开机完成、HDC 连接和应用运行仍须窗口核对，不能据此断言所有模拟器问题均已修复。官方要求账号登录的版本可能不能通过 CLI 启动，应在 Device Manager 手动处理。

官方依据：[实例字段、停止与 coldboot 语义](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-emulator-command-line.md)。

## 五、<span id="verification">隔离验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
ruby ./Tests/RepairHarmonySimulatorTests.rb
ruby ./Tests/InstallerRegistrationTests.rb
```

测试使用假官方 CLI、临时实例和系统命令替身，覆盖只读、状态未知、冷启动顺序、停止失败、取消、SDK 完整备份及链接保护。共享请求、菜单范围、私有载体与宿主去重测试位于 `Tests/`；不注册扩展、不操作用户模拟器。源码回归与签名构建不替代 Finder 菜单、真实 DevEco 输出、许可和真实冷启动验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
