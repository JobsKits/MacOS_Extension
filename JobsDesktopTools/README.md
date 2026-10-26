# JobsDesktopTools 固定顺序桌面菜单

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、顺序与范围](#menus)
- [二、安装、卸载与兼容入口](#install)
- [三、配置与失败恢复](#configuration)
- [四、源码与验证](#maintenance)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

一个 [**Finder Sync**](https://developer.apple.com/documentation/findersync) 扩展统一生成六项菜单，确保三个“新建模拟器”连续排列。功能仍可在上级安装面板逐叶选择；只选一项也能运行，不依赖其它旧宿主 App。已安装 App 内含五份完整业务脚本和隐藏文件偏好服务，运行时不读取源码仓库。

## 一、<span id="menus">顺序与范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 顺序 | 菜单 | 保留的功能 ID | 业务入口 |
| --- | --- | --- | --- |
| 1 | 🍎 新建 iOS 模拟器 | `ios-simulator-create` | `CreateIOSSimulator.zsh --create` |
| 2 | 📱 新建 Android 模拟器 | `android-simulator-create` | `CreateAndroidSimulator.zsh --create` |
| 3 | 🌈 新建 Harmony 模拟器 | `harmony-simulator-create` | `CreateHarmonySimulator.zsh --create` |
| 4 | 🩺 Android 模拟器检测与修复 | `android-simulator-repair` | `RepairAndroidSimulator.zsh --repair` |
| 5 | 🧰 Harmony 模拟器检测与修复 | `harmony-simulator-repair` | `RepairHarmonySimulator.zsh --repair` |
| 6 | 👁️ 显示文件 / 🙈 隐藏文件 | `hidden-files-toggle` | 当前用户 Finder 偏好服务 |

前五项仅在系统桌面空白处显示。最后一项同时保留普通文件夹背景入口；文件、多选、工具栏与侧边栏不加入这些菜单。关闭部分功能后，剩余项保持相对顺序；系统和本仓以外扩展的相对插入位置由 Finder 管理。

隐藏文件菜单显示下一步动作：当前隐藏时显示“👁️ 显示文件”，当前显示时显示“🙈 隐藏文件”。每次打开重新读取 `com.apple.finder/AppleShowAllFiles`；异常类型或同步失败保留“⚠️ 隐藏文件状态不可用”并置灰。扩展只申请该偏好域的只读权限，实际写入和刷新由非沙盒宿主处理。请求明确传递显示或隐藏目标，外部状态变化后不会把同一菜单动作反向切换。

创建、修复的工具链、许可证、备份和危险确认均沿用原核心；具体能力见 [iOS 新建](../JobsIOSSimulatorCreator/README.md)、[Android 新建](../JobsAndroidSimulatorCreator/README.md)、[Harmony 新建](../JobsHarmonySimulatorCreator/README.md)、[Android 修复](../JobsAndroidSimulatorRepairer/README.md)、[Harmony 修复](../JobsHarmonySimulatorRepairer/README.md)及[文件显示](../JobsHiddenFilesToggler/README.md)。安装、卸载和扩展登记不会执行这些业务。

## 二、<span id="install">安装、卸载与兼容入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

要求 [**macOS**](https://www.apple.com/macos/) 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 与 macOS SDK。上级[总安装面板](../【MacOS】🧩安装Finder扩展.command)保留六项独立选项，选择后只构建、注册本聚合工程一次；根安装脚本顶部的“维护索引”说明面板、叶 ID、工程、菜单、宿主、资源及配置之间的对应关系。

本目录[安装入口](./【MacOS】安装桌面工具Finder扩展.command)安装全部六项，[卸载入口](./【MacOS】卸载桌面工具Finder扩展.command)移除全部六项。六个旧功能目录的安装／卸载脚本保留原文件名，转交管理器且只影响各自一叶；这些兼容源码入口需要同仓的 `JobsDesktopTools/`，缺失时明确停止，不再静默启用旧的重复菜单。

所有入口先显示内置说明，直接回车执行、任意非空输入跳过，`Ctrl+C` 或输入结束停止。上级已确认的安装器可传 `--non-interactive`；`--skip-finder-restart` 或 `JOBS_SKIP_FINDER_RESTART=1` 将 Finder 刷新交给外层。兼容的 `--install` / `--uninstall` 也表示明确执行。

只安装、卸载指定一项的可复制命令如下；不传 `--non-interactive` 时仍会显示说明并确认：

```shell
/bin/zsh ./Scripts/ManageDesktopTools.zsh install ios-simulator-create
/bin/zsh ./Scripts/ManageDesktopTools.zsh uninstall ios-simulator-create
```

安装合并当前选择；只在首次迁移时带入 PlugInKit 明确启用的旧六项。后续安装不重新打开已关闭的旧功能。卸载只移除选定叶子，仍有其它项时保留聚合 App 和扩展；最后一项关闭后停用并注销扩展，保留源码、App 产物和所有业务数据。卸载隐藏开关不会改变当前显示状态。

## 三、<span id="configuration">配置与失败恢复</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 对象 | 位置 / 标识 |
| --- | --- |
| 宿主 / 扩展 ID | `com.jobs.desktoptools` / `com.jobs.desktoptools.findersync` |
| 固定请求 | `jobsdesktoptools://perform/<功能ID>`；隐藏项另带唯一 `show=1` 或 `show=0` |
| 功能配置 | `~/Library/Application Support/JobsDesktopTools/EnabledFeatures.txt` |
| 迁移标记 | 同目录 `MigrationVersion.txt` |
| 产物 | `work/DerivedData/Build/Products/Debug/JobsDesktopTools.app` |
| 扩展 | App 内 `Contents/PlugIns/JobsDesktopToolsFinderSync.appex` |
| 安装 / 卸载日志 | 系统临时目录 `JobsDesktopToolsInstall.log` |
| 事务备份 | 系统临时目录 `JobsDesktopToolsTransaction.*/`，实际路径打印在日志中 |

配置按真实账户 Home 寻址，避免 Finder 沙盒容器重定向。缺失、空值、损坏、未知 ID、重复项、不可读文件和符号链接均不会默认全开。菜单点击和宿主派发再次校验当前功能开关，外部 URL 不能携带任意路径或命令。

管理器使用专用互斥锁。安装先备份现有 App 和配置，再构建、核对身份与深度签名、验证新扩展精确路径已启用，之后原子发布配置并停用旧六个扩展。失败或中断恢复本事务发布的配置、迁移标记和原启用状态；检测到外部改动时保留外部内容及事务备份，不覆盖未知改动。锁异常残留时，先检查是否仍有管理操作，再处理日志中指出的 `.manager-lock`，不要并行启动第二次安装。

## 四、<span id="maintenance">源码与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

`Shared/DesktopMenuAction/` 是菜单固定顺序唯一来源；`JobsDesktopToolsFinderSync/FinderSync.swift` 负责资格、动态标题和点击；`DesktopActionExecutor` 负责宿主派发。`Resource/` 与 `Core/` 的原功能副本来源、目标路径及 SHA-256 记录在 [SourceManifest.json](./SourceManifest.json)，更新核心时同步副本并逐字节核对。脚本与旧启动器保持原样，不为聚合改动其业务语义。

以下验证只使用临时程序、文件和系统边界替身，不运行安装器、不注册扩展、不刷新 Finder、不切换隐藏文件或操作模拟器：

```shell
ruby ./Tests/MenuTests.rb
ruby ./Tests/InstallerTests.rb
```

菜单回归覆盖全部 64 种叶子组合、固定顺序、动态隐藏状态、读失败禁用、普通目录背景、失效上下文及固定请求。安装回归覆盖首次迁移、部分卸载、最后一项关闭、配置／标记失败回滚、外部并发修改保护、临时路径及资源字节一致。旧目录安装测试继续验证原构建 helper 和真实兼容入口转发；真实 Finder 加载与模拟器业务验收单独记录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
