# `JobsAndroidSimulatorRepairer`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能速览](#quick-look)
- [二、安装与卸载](#installation)
- [三、运行与诊断](#usage)
- [四、容量、备份与失败处理](#capacity)
- [五、验证与实机边界](#validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

为 [**macOS**](https://www.apple.com/macos/) 系统桌面空白右键提供 **Android 模拟器检测与修复**。独立 App + [**Finder Sync Extension**](https://developer.apple.com/documentation/findersync)，点击后交给可见 Terminal；只接受已启动的本机 [**Android Emulator**](https://developer.android.com/studio/run/emulator)。核心随 App 打包，不引用原双击脚本或其他扩展目录。

当前菜单安装由 [JobsDesktopTools](../JobsDesktopTools/README.md) 统一承载。本目录的管理入口只启停 `android-simulator-repair` 这一叶；需要同仓 `JobsDesktopTools/` 源码。聚合扩展按固定顺序排列三项新建、两项修复和动态文件显示开关，保留逐叶选择；普通目录背景仅显示文件开关。安装产物统一在 `../JobsDesktopTools/work/DerivedData/Build/Products/Debug/JobsDesktopTools.app`，安装／卸载日志统一为系统临时目录 `JobsDesktopToolsInstall.log`。本目录原工程、旧 Bundle ID、旧 URL 和隔离回归仍保留，后文源码标识用于兼容实现参考，不是当前安装器注册目标。

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

菜单安装与卸载统一使用 [图形管理入口](./【MacOS】管理Android模拟器检测修复Finder扩展.app)。直接打开面板，选择“安装 / 更新”或“卸载”并勾选当前范围内的功能；默认空选，点击操作按钮即确认。每项显示等待、正在安装 / 卸载、成功或失败；底部日志实时滚动，可选择复制或复制全部。运行中锁定选择和关闭入口，结束后保留结果与日志。首次打开或面板源码更新后会在后台编译，失败以桌面提示和启动日志说明。

原同名 `.command` 入口保留，终端只负责唤起独立 GUI，随后结束启动脚本；本次启动任务结束后自动关闭对应终端页，安装 / 卸载、进度与实时日志均由 GUI 后台处理。已有交互 Shell 中手工调用时保留原工作会话。内部实现为 `Scripts/ManageExtension.zsh`；完整仓内单功能入口使用总面板的受限范围。可独立复制的包须整体保留 `.command`、`.app`、Scripts、工程源码和资源。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

本入口转交 [JobsDesktopTools](../JobsDesktopTools/README.md)，只管理 `android-simulator-repair`，需要保留同仓聚合工程源码。旧宿主、扩展与 Xcode 工程仍供实现参考和隔离验证；常规菜单安装不再注册本目录的旧独立扩展。

需要 macOS 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 与 macOS SDK。安装成功后启用本入口对应功能并保留其它已装选择；卸载仅减去对应功能，仍有其它项时保留共享 App 和登记，最后一项才停用聚合扩展。源码、用户工程、SDK、模拟器、业务数据和既有业务配置保留；安装与卸载只管理菜单，不执行菜单业务。操作完成后刷新 Finder，请先结束 Finder 文件搬移。

安装 / 卸载日志为系统临时目录中的 `JobsDesktopToolsInstall.log`。

也可从 [总管理面板](../【MacOS】🧩管理Finder扩展.command) 选择一个或多个功能，在同一面板切换安装 / 更新或卸载。

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
