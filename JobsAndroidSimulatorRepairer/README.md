# `JobsAndroidSimulatorRepairer`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能速览](#quick-look)
- [二、安装与卸载](#installation)
  - [【MacOS】安装Android模拟器检测修复Finder扩展.command](#jobs-toc-heading-4)
  - [【MacOS】卸载Android模拟器检测修复Finder扩展.command](#jobs-toc-heading-5)
- [三、运行与诊断](#usage)
- [四、容量、备份与失败处理](#capacity)
- [五、验证与实机边界](#validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

为 [**macOS**](https://www.apple.com/macos/) 系统桌面空白右键提供 **Android 模拟器检测与修复**。独立 App + [**Finder Sync Extension**](https://developer.apple.com/documentation/findersync)，点击后交给可见 Terminal；只接受已启动的本机 [**Android Emulator**](https://developer.android.com/studio/run/emulator)。核心随 App 打包，不引用原双击脚本或其他扩展目录。

当前菜单安装由 [JobsDesktopTools](../JobsDesktopTools/README.md) 统一承载。本目录的原名安装／卸载入口只启停 `android-simulator-repair` 这一叶；需要同仓 `JobsDesktopTools/` 源码。聚合扩展按固定顺序排列三项新建、两项修复和动态文件显示开关，保留逐叶选择；普通目录背景仅显示文件开关。安装产物统一在 `../JobsDesktopTools/work/DerivedData/Build/Products/Debug/JobsDesktopTools.app`，安装／卸载日志统一为系统临时目录 `JobsDesktopToolsInstall.log`。本目录原工程、旧 Bundle ID、旧 URL 和隔离回归仍保留，后文源码标识用于兼容实现参考，不是当前安装器注册目标。

## 一、<span id="quick-look">功能速览</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 操作 | 结果与确认 |
| --- | --- |
| 只读诊断 | 检查模拟器身份、安装位置及 `/data`；低于 800 MB、安装位置非自动或查询失败返回异常，不写本工具日志。 |
| 恢复安装位置 | 选择动作后，回车跳过、非空执行 `pm set-install-location 0`，回读确认。 |
| 编译缓存重置 | 输入 `YES` 才执行 `cmd package compile --reset -a`；不保证释放空间，完成后复测。 |
| 卸载指定第三方包 | 输入精确包名、核对第三方包清单、再输入 `YES`；**删除对应应用及其数据**。不批量卸载内置应用。 |
| 增加 AVD 容量配置 | 只增大、不缩容；输入容量和 `YES`，停机并完整备份，改配置后另行确认冷启动，核验实际容量与剩余空间。 |

真机、离线设备、普通文件夹背景及选中项均不进入本功能。没有在线模拟器时先启动已有 AVD；本包不安装 SDK、下载镜像或创建新设备。需要创建时使用[独立新建包](../JobsAndroidSimulatorCreator/README.md)。

## 二、<span id="installation">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

需要 macOS 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 及可用的本机签名环境。仅安装菜单不会操作模拟器。

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">[【MacOS】安装Android模拟器检测修复Finder扩展.command](./【MacOS】安装Android模拟器检测修复Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 从本目录构建并启用本功能，刷新 Finder。

- 阅读终端自述，**直接回车安装；任意非空输入（包括空格）跳过**，Ctrl+C 或输入结束停止。
- 检查 Xcode，构建相邻 JobsDesktopTools 并核对聚合 Bundle ID 与签名，仅启用本叶。
- 统一扩展启用并发布选择成功后停用旧重复菜单；其它已选叶和所有设备数据保留。
- 安装与卸载日志为系统临时目录中的 `JobsDesktopToolsInstall.log`。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">[【MacOS】卸载Android模拟器检测修复Finder扩展.command](./【MacOS】卸载Android模拟器检测修复Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 只关闭本叶菜单，最后一叶关闭时停用聚合扩展；保留共享 App 和业务数据。

- 阅读管理器自述后，直接回车只关闭本功能；任意非空输入、Ctrl+C 或输入结束停止。
- 只移除本叶开关；聚合包的其它功能、源码、SDK、镜像、实例、备份和业务日志保留。
- 安装与卸载日志统一为系统临时目录 `JobsDesktopToolsInstall.log`。

也可通过[总安装面板](../README.md)选择本功能，功能标识 `android-simulator-repair`。安装后仅在系统桌面空白处显示；首次派发需要允许本 App 控制 Terminal。

## 三、<span id="usage">运行与诊断</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下命令在本 README 所在目录执行。直接运行脚本与右键使用相同核心：

```shell
/bin/zsh ./Scripts/RepairAndroidSimulator.zsh
```

只读检查全部在线模拟器，或指定一个目标：

```shell
/bin/zsh ./Scripts/RepairAndroidSimulator.zsh \
  --check \
  --serial emulator-5554
```

`--repair` 为默认交互模式；`--help` / `-h` 显示帮助；不提供 `--yes` 绕过确认。多台模拟器时先选目标，每次写操作再次校验序列号和 AVD 名称。参数错误返回 `2`，诊断异常或未完成修复返回非零。

工具按显式 `ANDROID_ADB_BIN` / `ANDROID_EMULATOR_BIN`、SDK 环境变量及常见 SDK 安装位置发现并检查；显式坏工具路径停止。AVD 根按 `ANDROID_AVD_HOME`、`ANDROID_USER_HOME/avd`、当前用户 Android 默认目录解析，支持描述符的 `path` / `path.rel`，越界、符号链接和身份不一致拒绝写入。具体发现顺序以[核心源码](./Scripts/RepairAndroidSimulator.zsh)为准。

修复日志为系统临时目录的 `JobsAndroidSimulatorRepairer-*.log`；宿主诊断 `JobsAndroidSimulatorRepairer.log`，构建后启用日志 `JobsAndroidSimulatorRepairerBuildPhase.log`。日志与结果在 Terminal 可见；只读检查不创建本工具日志。

## 四、<span id="capacity">容量、备份与失败处理</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

容量操作要求现有配置唯一、目标大于配置和实际 `/data` 总量，最大 1 TB。若使用 `-data` / `-datadir`、`disk.dataPartition.path` / `initPath`、外置数据镜像、链接、未知进程参数或无法确认 AVD 存储位置，则停止自动扩容；只读与轻量修复仍可使用。

停机成功并确认锁释放后，在所选 AVD 根创建 `.<AVD名>.repair-backup.XXXXXX/`，内含 `avd/` 完整副本与原 `<AVD名>.ini`。复制后逐字节比较；磁盘空间须能容纳备份、目标容量及 1 GB 余量，失败不改配置。备份不会自动删除。

**修改配置不等于已有用户分区已经增大。** 冷启动可能让 Emulator 调整 userdata / qcow2；不使用 `-wipe-data`。启动后必须确认实际总量增长且可用空间达到阈值才报告扩容通过。跳过启动或实际容量未增长都保留“待验证 / 未完成”，不报告修好。

需要恢复时先正常停止对应模拟器，保留当前失败现场，再将完整备份的 `avd/` 和描述符人工恢复至原位置；不要只恢复 `config.ini` 后假定数据也已还原。没有自动恢复或自动删除锁功能。

官方依据：[工具环境变量](https://developer.android.com/tools/variables?hl=en)、[ADB 目标选择](https://developer.android.com/tools/adb?hl=en)、[模拟器控制台](https://developer.android.com/studio/run/emulator-console?hl=en)、[冷启动与数据文件参数](https://developer.android.com/studio/run/emulator-commandline?hl=en)。

## 五、<span id="validation">验证与实机边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本功能目录运行隔离业务及安装入口回归：

```shell
ruby ./Tests/RepairAndroidSimulatorTests.rb
ruby ./Tests/InstallerRegistrationTests.rb
```

总安装映射回归从仓库根运行 `ruby ./Tests/AndroidSimulatorRepairInstallerIntegrationTests.rb`。共享请求、桌面范围和宿主测试见 `./Tests/`；使用假 ADB、临时 AVD，不执行真实卸载或容量调整。

2026-10-23 验证：业务 25 组 / 182 断言、独立安装 66、总映射 34、<u>[**Swift**](https://www.swift.org/)</u> 传输 66、宿主 26、新桌面菜单 14 断言通过；邻接桌面与模拟器创建映射回归通过。Debug 双 target 构建、深度签名、内置核心逐字节对账通过；临时系统登记已精确清理，结果与系统安装分开记录。**尚未真实安装本功能、验收 Finder 菜单或修改现有 AVD**，不以构建通过代替真实设备扩容验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
