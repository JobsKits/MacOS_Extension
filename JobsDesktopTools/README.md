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


**主题与语言：** 面板右上角可选择“黑夜 / 白天 / 跟随系统”和“简体中文 / 繁体中文 / 英文 / 跟随系统”，默认均为“跟随系统”。窄窗无法与标题同排时，工具组移至标题下一行并保持右对齐。选择后即时更新并保存，下次打开自动恢复；总面板、随包面板及联合 App 内置面板共用当前用户设置。切换保留勾选、安装 / 卸载任务、进度与日志；界面功能名称、状态和对话框按所选语言显示，后台工具原始日志保留原文。系统主题变化随原生外观更新，跟随系统语言在系统区域通知或窗口重新激活时重新读取。

**安装 / 卸载位置：** 面板提供“使用「应用程序」文件夹安装 / 卸载”复选框，默认不勾选。不勾选时沿用本地 `work` 内的构建产物；勾选时将所选功能统一安装到 `/Applications/Jobs自定义右键菜单.app`，面板同时显示这个联合 App 的名字。完整宿主及其扩展收在联合 App 内，不再为本轮所选功能生成其它顶层 App。安装到应用程序后，清理仓库构建输出或移走源码不影响已安装功能；构建目录模式仍须保留正在使用的 App。两种方式都保留各功能自身的工具链依赖。

**安装后清理：** 仅在“安装 / 更新”且勾选应用程序路线时，显示默认不勾选的“安装成功后清除此轮构建产物”。明确勾选后，只有当前模块部署、登记和提交全部成功才清理本轮对应的 DerivedData；构建目录路线及卸载模式隐藏并清空该选项。失败安装保留构建产物，清理失败会提示并保留已安装功能；不会整目录清理所有 `work`、其它模块或源码。

卸载按同一复选框选定的位置执行，所选位置没有 App 时保留另一位置及其功能配置；共享宿主仍有未卸载菜单时保留 App，最后一项移除后注销并删除该功能模块；联合 App 的最后一个模块移除后才删除外层 `Jobs自定义右键菜单.app`。切换位置安装会把登记切到新位置，构建目录中的另一份产物保留；所选功能的旧版顶层自有 App 在成功提交后收拢至联合 App，未知 App 不覆盖或删除。完整说明见[App 部署支持库](./Scripts/【MacOS】AppDeployment.zsh/README.md)。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

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

创建、修复的工具链、许可证、备份和危险确认均沿用原核心；具体能力见 [iOS 新建](../JobsIOSSimulatorCreator/README.md)、[Android 新建](../JobsAndroidSimulatorCreator/README.md)、[Harmony 新建](../JobsHarmonySimulatorCreator/README.md)、[Android 修复](../JobsAndroidSimulatorRepairer/README.md)、[Harmony 修复](../JobsHarmonySimulatorRepairer/README.md)及[文件显示](../JobsHiddenFilesToggler/README.md)。Android / Harmony 的 SDK 工具、在线清单和镜像下载遇到网络失败或单次超时会自动持续重试，2～30 秒退避，直到成功或 Ctrl+C 主动结束；真实进度和逐次日志保留，明确权限、磁盘、版本及许可错误报告并停止下游。iOS 新建仅使用已经安装的 Runtime，两个修复入口不下载工具。安装、卸载和扩展登记不会执行这些业务。

## 二、<span id="install">安装、卸载与兼容入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

菜单安装与卸载统一使用 [图形管理入口](./【MacOS】管理桌面工具Finder扩展.app)。直接打开面板，选择“安装 / 更新”或“卸载”并勾选当前范围内的功能；默认空选，点击操作按钮即确认。每项显示等待、正在安装 / 卸载、成功或失败；底部日志实时滚动，可选择复制或复制全部。运行中锁定选择和关闭入口，结束后保留结果与日志。首次打开或面板源码更新后会在后台编译，失败以桌面提示和启动日志说明。

原同名 `.command` 入口保留，终端只负责唤起独立 GUI，随后结束启动脚本；本次启动任务结束后自动关闭对应终端页，安装 / 卸载、进度与实时日志均由 GUI 后台处理。已有交互 Shell 中手工调用时保留原工作会话。内部实现为 `Scripts/ManageExtension.zsh`；完整仓内单功能入口使用总面板的受限范围。可独立复制的包须整体保留 `.command`、`.app`、Scripts、工程源码和资源。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

每项失败后，点击红色带下划线的“失败，见日志”，会新建 Terminal 会话并用 `cat` 显示本次完整会话日志；现有任务继续，已有终端保留。“日志文件”按钮仍用于在 Finder 中定位原始日志。

要求 [**macOS**](https://www.apple.com/macos/) 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 与 macOS SDK。上级[总管理面板](../【MacOS】🧩管理Finder扩展.command)保留六项独立选项，选择后只构建、注册本聚合工程一次；内部 `../Scripts/ManageFinderExtensions.zsh` 顶部的“维护索引”说明面板、叶 ID、工程、菜单、宿主、资源及配置之间的对应关系。

本目录只保留 [桌面工具管理入口](./【MacOS】管理桌面工具Finder扩展.command)，省略 `--features` 时面板显示六项且默认空选，后台编排处理全部六项，指定时仅处理所列叶子。六个功能目录各有一个管理入口，只影响各自一叶；这些入口需要同仓 `JobsDesktopTools/`，缺失时明确停止，不启用旧的重复菜单。

管理入口直接显示面板，选择操作与功能后点击按钮执行；状态和日志保留在面板中。`--action` 可预设操作，`--features` 限定逗号分隔的功能 ID；内部 `Scripts/ManageExtension.zsh` 承接面板已确认的 `--action ... --non-interactive`；其 `--skip-finder-restart` 将 Finder 刷新交给外层，保留登记及身份核验。公开启动器不接受非交互执行开关。

只安装、卸载指定一项的可复制命令如下；不传 `--non-interactive` 时打开面板，并把 `--features` 限定为可见范围，仍需勾选并点击操作按钮：

```shell
/bin/zsh ./【MacOS】管理桌面工具Finder扩展.command \
  --action install \
  --features ios-simulator-create

/bin/zsh ./【MacOS】管理桌面工具Finder扩展.command \
  --action uninstall \
  --features ios-simulator-create
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
