# `JobsRunAuthorizer` 单文件授予执行权限

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装与卸载](#installation)
- [二、操作与风险边界](#usage)
- [三、工程结构与配置](#layout)
- [四、验证与排查](#verification)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**选中任意一个普通文件 → 右键“➕ 授予执行权限（chmod +x）” → Terminal 核对路径并回车 → 仅执行 `chmod +x`。** 由 Jobs 维护；状态：维护中。

| Finder 目标 | 菜单行为 |
| --- | --- |
| 单个普通文件，包括脚本、二进制、README、文本和图片 | “➕ 授予执行权限（chmod +x）”与“➖ 移除执行权限（chmod -x）”在各自安装后均可点击，不依赖后缀或文件头。 |
| 已有部分或全部执行位 | 仍可点击，按 `chmod +x` 幂等处理；已有部分执行位不会阻止补齐其它允许的位。 |
| 文件夹、应用包、工程包 | 不显示。 |
| 符号链接、多选、目录或桌面空白处 | 不显示。 |
| 打开菜单后目标不存在或变成目录 | 点击与宿主再次复核普通文件边界；失效时停止。 |
| Terminal 等待确认期间目标被替换 | 执行前复检设备号与 inode，身份变化时停止。 |

授权只改变该文件的执行权限，保持当前 `umask` 对 `chmod +x` 的实际限制；不递归、不运行文件、不提权、不修改文件内容或隔离属性。终端在确认前展示目标，直接回车继续；任意非空输入（包括空格）、`Ctrl+C` 或 EOF 取消。确认后授权失败会保留真实退出码和日志。

Finder 菜单、URL 请求、宿主和终端脚本使用相同的单普通文件边界；文件格式与是否已含执行位均不影响资格。两项菜单须分别安装，均不会自动运行目标文件。

本工程是 [MacOS@Extension](../README.md) 中的普通源码目录，包含独立工程、Scheme、Bundle ID、统一管理入口，没有独立 Git 或子模块配置。整个文件夹可单独复制后安装；业务脚本随 App 打包，不依赖原脚本仍在磁盘上。


**主题与语言：** 面板右上角可选择“黑夜 / 白天 / 跟随系统”和“简体中文 / 繁体中文 / 英文 / 跟随系统”，默认均为“跟随系统”。主题和语言下拉入口紧凑显示，当前文字居中；窄窗无法与标题同排时，工具组移至标题下一行并保持右对齐。选择后即时更新并保存，下次打开自动恢复；总面板、随包面板及联合 App 内置面板共用当前用户设置。切换保留勾选、安装 / 卸载任务、进度与日志；界面功能名称、状态和对话框按所选语言显示，后台工具原始日志保留原文。系统主题变化随原生外观更新，跟随系统语言在系统区域通知或窗口重新激活时重新读取。

**安装 / 卸载位置：** 面板提供“使用「应用程序」中的联合 App 安装 / 卸载”复选框，首次打开默认勾选，可手动取消。不勾选时沿用本地 `work` 内的构建产物；勾选时将所选功能统一安装到 `/Applications/Jobs自定义右键菜单.app`，面板同时显示这个联合 App 的名字。完整宿主及其扩展收在联合 App 内，不再为本轮所选功能生成其它顶层 App。安装到应用程序后，清理仓库构建输出或移走源码不影响已安装功能；构建目录模式仍须保留正在使用的 App。两种方式都保留各功能自身的工具链依赖。

**安装后清理：** 仅在“安装 / 更新”且勾选应用程序路线时，显示“安装成功后清除此轮构建产物”；首次打开默认勾选，可手动取消。保持勾选时，只有当前模块部署、登记和提交全部成功才清理本轮对应的 DerivedData；卸载模式隐藏但保留当前选择，返回安装时恢复；构建目录路线隐藏并清空该选项。失败安装保留构建产物，清理失败会提示并保留已安装功能；不会整目录清理所有 `work`、其它模块或源码。

卸载按同一复选框选定的位置执行，所选位置没有 App 时保留另一位置及其功能配置；共享宿主仍有未卸载菜单时保留 App，最后一项移除后注销并删除该功能模块；联合 App 的最后一个模块移除后才删除外层 `Jobs自定义右键菜单.app`。切换位置安装会把登记切到新位置，构建目录中的另一份产物保留；所选功能的旧版顶层自有 App 在成功提交后收拢至联合 App，未知 App 不覆盖或删除。完整说明见[App 部署支持库](./Scripts/【MacOS】AppDeployment.zsh/README.md)。


**独立清理与停止：** 安装位置与安装后自动清理两个复选框紧邻排列，窄窗按需换行；红色“🧹 清除构建产物”按钮位于底部主操作按钮右侧，安装 / 更新和卸载两种模式保持一致。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。“安装成功后清除此轮构建产物”复选框仅在应用程序安装模式出现，首次打开默认勾选，可手动取消。构建目录路线隐藏并清空自动清理复选框，独立清理按钮保持显示但禁用，避免清除正在使用的产物。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## 一、<span id="installation">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

菜单安装与卸载统一使用 [图形管理入口](./【MacOS】管理运行授权Finder扩展.app)。直接打开面板，选择“安装 / 更新”或“卸载”并勾选当前范围内的功能；默认空选，点击操作按钮即确认。每项显示等待、正在安装 / 卸载、成功或失败；底部日志实时滚动，可选择复制或复制全部。运行中锁定选择和关闭入口，结束后保留结果与日志。首次打开或面板源码更新后会在后台编译，失败以桌面提示和启动日志说明。

原同名 `.command` 入口保留，终端只负责唤起独立 GUI，随后结束启动脚本；本次启动任务结束后自动关闭对应终端页，安装 / 卸载、进度与实时日志均由 GUI 后台处理。已有交互 Shell 中手工调用时保留原工作会话。内部实现为 `Scripts/ManageExtension.zsh`；完整仓内单功能入口使用总面板的受限范围。可独立复制的包须整体保留 `.command`、`.app`、Scripts、工程源码和资源。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

每项失败后，点击红色带下划线的“失败，见日志”，会新建 Terminal 会话并用 `cat` 显示本次完整会话日志；现有任务继续，已有终端保留。“日志文件”按钮仍用于在 Finder 中定位原始日志。

双击[管理入口（安装模式）](./【MacOS】管理运行授权Finder扩展.command)，在面板选择安装 / 更新并勾选功能，点击操作按钮后后台执行。入口检查完整 [**Xcode**](https://developer.apple.com/xcode/) 和 macOS SDK，构建当前工程并验证 Bundle ID 与签名，注销同 ID 的旧扩展路径和旧宿主 URL 登记，再注册当前产物、初始化后台宿主并刷新 Finder。安装过程中不会给任何文件授权，也不会下载依赖或修改 `xcode-select`。

独立构建产物位于 `./work/DerivedData/Build/Products/Debug/JobsRunAuthorizer.app`，系统从此路径启动扩展，安装后请保留。总安装入口使用总仓 `work/`，两种入口安装同一个功能时会精确注销旧登记；旧 App 文件保留。安装日志为系统临时目录中的 `JobsRunAuthorizerInstall.log`。

双击[管理入口（卸载模式）](./【MacOS】管理运行授权Finder扩展.command)，在面板选择卸载并勾选功能，点击操作按钮后后台执行并刷新 Finder。入口只禁用固定扩展，注销其记录，并删除名称、Bundle ID、非符号链接目录均核验通过的已登记 App；源码、原脚本和所有曾授权文件保留。卸载不撤销已经增加的执行权限。日志为系统临时目录中的 管理入口同名 `.log`（以面板底部日志为准）。

依赖为 macOS 12.0+、完整 Xcode、系统 Finder Sync、Terminal 和系统 zsh；业务不依赖 Homebrew、Python、Node 或 Ruby。Ruby 仅用于隔离回归。首次点击时按系统提示允许宿主自动化控制 Terminal；菜单未出现时在系统设置的 Finder 扩展中检查 `JobsRunAuthorizer`。

## 二、<span id="usage">操作与风险边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 在 Finder 中只选中任意一个普通文件，打开右键菜单选择“➕ 授予执行权限（chmod +x）”。桌面上的单个普通文件也可以；桌面空白处没有入口。

- Terminal 展示目标路径及影响范围；核对后回车增加执行权限。目标文件在等待期间被替换时，设备号与 inode 校验会阻止继续授权。

- 终端显示修改前后权限和日志位置。已有执行位仍可重复操作；只有拥有文件权限的当前用户能够成功修改，失败不会尝试 `sudo`。

增加执行权限不会验证文件可信性，也不会替用户运行目标。需要减去执行位时安装并使用[移除执行权限](../JobsRunAuthorizationRevoker/README.md)；该入口精确执行 `chmod -x`，同样受当前 `umask` 过滤，不猜测或恢复授权前的完整权限快照，两项菜单分别安装与卸载。

独立终端调用（在本工程目录）：

```shell
/bin/zsh ./Scripts/AuthorizeRun.zsh \
  --file "/目标目录/脚本.command"
```

只读检查无需交互，不修改权限或创建日志：

```shell
/bin/zsh ./Scripts/AuthorizeRun.zsh \
  --check \
  --file "/目标目录/脚本.command"
```

参数、确认策略及日志说明见 [Scripts 说明](./Scripts/README.md)。

## 三、<span id="layout">工程结构与配置</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
./
├── JobsRunAuthorizer.xcodeproj/       # 宿主、Finder 扩展、共享 Scheme
├── JobsRunAuthorizer/                # main / AppDelegate / Model / Terminal 派发
├── JobsRunAuthorizerFinderSync/      # 单文件菜单及点击时复检
├── JobsRunAuthorizationShared/       # 单文件校验、URL 请求与系统工厂
├── Scripts/                         # 权限业务及构建后注册
├── Tests/                           # 临时文件与系统命令替身回归
└── 【MacOS】管理运行授权Finder扩展.command
```

| 项目项 | 当前值 / 依据（2026-10-22） |
| --- | --- |
| 工程 / Scheme | `JobsRunAuthorizer.xcodeproj` / `JobsRunAuthorizer`。 |
| 宿主 Bundle ID | `com.jobs.JobsRunAuthorizer`。 |
| 扩展产品 / Bundle ID | `JobsRunAuthorizerFinderSync.appex` / `com.jobs.JobsRunAuthorizer.FinderSyncExtension`。 |
| Swift / 最低系统 | 工程 `SWIFT_VERSION = 5.0` / `MACOSX_DEPLOYMENT_TARGET = 12.0`，实际编译器随所选 Xcode。 |
| 安装单元 | 2 个 target：后台宿主与其内嵌 Finder 扩展，依据 `project.pbxproj`。 |
| 业务 Swift 文件 | 8 个：宿主 4、Finder 1、共享 3；按手写业务文件计，排除脚本、配置、测试与产物。 |
| 第三方直接依赖 | 0；依据工程 Frameworks 与无第三方包配置，无依赖锁文件。 |
| 窗口 / 网络 / 数据库 | 无业务窗口、服务接口、数据库或额外端权限；宿主使用 `LSUIElement` 后台派发。 |

Finder 使用 `jobsrunauthorizer://authorize?path=...` 把单文件请求交给宿主。宿主在冷启动阶段注册 URL 接收器，校验路径后把打包的 `AuthorizeRun.zsh` 复制到本次私有临时载体，由 Terminal 执行；派发完成后退出，不等待授权结束。临时启动载体清理与业务日志保留分别处理。

```mermaid
flowchart LR
    Finder[FinderSync.swift] --> Shared[共享校验与 RunAuthorizationRequest.swift]
    Shared --> Host[main.swift / AppDelegate.swift]
    Host --> Model[RunAuthorizationModel.swift]
    Model --> Launcher[RunAuthorizationLauncher.swift]
    Launcher --> Terminal[系统 Terminal]
    Terminal --> Script[AuthorizeRun.zsh]
```

```mermaid
flowchart TD
    Selection[FinderSync.swift：选中项] --> Valid{恰好一个普通文件？}
    Valid -->|否| Hidden[不显示菜单]
    Valid -->|是| Menu[显示授予执行权限]
    Menu --> Click[点击复检与宿主校验]
    Click --> Confirm[AuthorizeRun.zsh：展示路径并等待确认]
    Confirm -->|非空 / EOF / Ctrl+C| Stop[取消]
    Confirm -->|回车| Identity[复检文件类型与身份]
    Identity --> Change[chmod +x 仅当前文件]
    Change --> Result[输出权限与日志，目标文件不执行]
```

Xcode 的 `Enable Finder Extension` Build Phase 调用 `./Scripts/EnableFinderExtension.zsh` 注册当前产物，只采信当前精确扩展路径的启用状态；成功后刷新 Finder，失败留下 `JobsRunAuthorizerNeedsFinderRestart` 标记供宿主重试。外层安装器与隔离构建通过 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过此脚本的注册及 Finder 刷新。Xcode 自己仍可能执行 `RegisterWithLaunchServices`，设置 `REGISTER_APP_WITH_LAUNCH_SERVICES=NO` 也不能保证不登记；隔离构建后须检查并按本次精确临时产物路径注销。直接在 Xcode 中构建默认会执行本项目的注册和 Finder 刷新。

## 四、<span id="verification">验证与排查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

脚本静态检查与隔离回归覆盖单文件边界、权限变化、原 `umask`、取消和非交互输入、特殊字符路径、目标替换，以及注册路径匹配；隔离测试不注册真实扩展、刷新 Finder 或操作真实业务文件。实际构建、系统签名、真实菜单和 Terminal 自动化分别验收，静态通过不代表已安装到当前电脑。

隔离回归验证任意单文件菜单、幂等执行、精确 `chmod +x` 与 `umask` 行为，以及中文和特殊字符路径的 URL / 私有载体传输。菜单测试不打开真实 Terminal，不注册或启用真实扩展；已安装 Finder 与 Terminal 自动化仍需安装后单独验收。

配套注册回归还覆盖 `TMPDIR` 有无末尾斜杠时的安装 / 卸载日志路径、精确扩展路径启用及失败状态。工程两 target 的 Info.plist、entitlements、Debug 构建、深度签名与打包资源字节一致属于独立检查；隔离构建产生的自动登记须按临时产物的精确路径清理。

在本工程目录运行 Ruby 回归：

```shell
ruby ./Tests/RunAuthorizationCommandTests.rb
ruby ./Tests/RunAuthorizationMenuTests.rb
ruby ./Tests/InstallerRegistrationTests.rb
```

原生路径传递测试使用临时产物，不运行 Terminal：

```shell
JOBS_TEST_OUTPUT_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/JobsRunAuthorizerTests.XXXXXXXX")"
/usr/bin/xcrun swiftc \
  -framework AppKit \
  -framework FinderSync \
  ./JobsRunAuthorizationShared/JobsAuthorizationFactories.swift \
  ./JobsRunAuthorizationShared/RunAuthorizationValidator/RunAuthorizationValidator.swift \
  ./JobsRunAuthorizationShared/RunAuthorizationRequest/RunAuthorizationRequest.swift \
  ./JobsRunAuthorizer/RunAuthorizationLauncher/RunAuthorizationLauncher.swift \
  ./Tests/RunAuthorizationTransportTests.swift \
  -o "${JOBS_TEST_OUTPUT_DIR}/RunAuthorizationTransportTests"
"${JOBS_TEST_OUTPUT_DIR}/RunAuthorizationTransportTests"
```

| 现象 | 排查 |
| --- | --- |
| 没有菜单 | 只选一个普通文件；确认不是文件夹、文件包或符号链接，并检查扩展开关。 |
| 菜单已显示，点击后无 Terminal | 查看系统临时目录中的 `JobsRunAuthorizer.log`，核对宿主请求和派发阶段及 Terminal 自动化权限。 |
| 授权失败 | 终端查看原始 `chmod` 错误与权限变化；目标可能已移动、替换或不允许当前用户修改。 |
| 旧副本仍响应 | 重新运行安装入口，核对日志中旧扩展及宿主 URL 的精确注销路径。 |
| 卸载后文件仍可执行 | 卸载只移除菜单，不撤销已经授权的执行位。 |

宿主固定日志 `JobsRunAuthorizer.log`、构建后注册日志 `JobsRunAuthorizerBuildPhase.log` 均位于系统临时目录。每次业务操作单独保留私有日志，具体路径以 Terminal 输出为准。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
