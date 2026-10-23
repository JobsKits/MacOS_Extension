# 桌面右键新建 Harmony 模拟器

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、平台与官方命令](#requirements)
  - [SDL 免登录替代下载源](#jobs-toc-heading-3)
- [二、运行、环境与保护边界](#usage)
- [三、安装单元与目录](#layout)
- [四、日志与排查](#logs)
- [五、验证与未执行边界](#validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

Jobs 维护的独立 [**Finder**](https://support.apple.com/guide/mac-help/welcome/mac) 扩展，仅在系统桌面空白菜单提供“新建 Harmony 模拟器”。点击后在 Terminal 补齐缺失工具和系统镜像，默认回车选择最新 Release 手机镜像，经确认调用华为官方 `Emulator -create` 创建唯一实例、复查详情并按需启动。源码与安装框架已实现，真实 DevEco 创建仍需相应机器验收。

| 入口 / 条件 | 实际行为 |
| --- | --- |
| 系统桌面空白右键 | 固定请求交给独立 Terminal，执行自包含创建脚本，不要求项目。 |
| 普通目录背景、任何选中项菜单 | 隐藏本入口；点击旧菜单时重新核对桌面上下文。 |
| [独立安装](./【MacOS】安装鸿蒙模拟器Finder扩展.command) | 阅读自述，回车安装，任意非空输入跳过；只构建并启用本扩展。 |
| [独立卸载](./【MacOS】卸载鸿蒙模拟器Finder扩展.command) | 核对已登记路径并输入 `YES`，只移除本功能 App / appex，保留模拟器与镜像。 |
| 缺少兼容工具 | 首屏回车确认后，从 SDL 免登录镜像补齐 Mac ARM64 工具依赖，校验并复检；不升级健康工具。 |
| 缺少 Release 系统镜像 | 自动读取官方可下载清单，回车选最新稳定版手机镜像；展示许可并由本人同意后下载，核验就绪再继续。 |

## 一、<span id="requirements">平台与官方命令</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

Harmony 模拟器使用 [**HarmonyOS**](https://developer.huawei.com/consumer/cn/harmonyos/) 的 DevEco 工具链，与 Android AVD 不互通。本套入口支持 Mac ARM / Windows x86_64（x64）；本目录只处理 Apple Silicon macOS，Windows 实现见[平行工程](../../WindowsOS@Extension/JobsHarmonySimulatorCreator/README.md)。Intel Mac 会停止；Rosetta 终端提示改用原生 Terminal。

扩展构建要求 macOS 12.0+、完整 [**Xcode**](https://developer.apple.com/xcode/) 和 macOS SDK。创建要求 DevEco Studio / Command Line Tools 中具备 `-create` 与 `-imageList` 的官方 Emulator，官方从 DevEco Studio 6.1.0 Beta1 开始提供这两项能力。脚本先运行 `-help` 双检，Android 的同名工具会被拒绝。macOS 27 尚未做真实 DevEco SDK 验收。

实际命令如下，名称及镜像版本均以独立参数传入：

```shell
Emulator -help
Emulator -imageList -downloaded true
Emulator -imageList -downloaded false
# 展示随工具的协议原文，并经本人回车同意后：
Emulator -license accept
Emulator -install -deviceType phone -osVersion 'HarmonyOS 6.1.1(24)' -force
Emulator -list -details
Emulator -create JobsHarmony_phone \
  -deviceType phone \
  -osVersion 'HarmonyOS 6.0.1(21)'
Emulator -start JobsHarmony_phone
```

版本文字仅示例，运行时从本机官方查询结果选择，不写死可用版本。实例与镜像目录沿用 DevEco 当前默认配置；不调用 `-config`。命令契约和首次启动许可说明见[华为官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)。需要开发者登录的镜像应在 Device Manager 中启动。

### <span id="jobs-toc-heading-3" data-jobs-toc="v2">SDL 免登录替代下载源</span><!-- jobs-toc:heading-end -->

华为官方下载中心下载模拟器配套工具（DevEco Studio / Command Line Tools）需要登录华为账号，依据[华为《账号服务与权限》](https://developer.huawei.com/consumer/cn/doc/app/hdc-services-and-benefits-0000002723168012)。如果希望免登录下载，**本入口使用 SDL 镜像作为替代下载源**。SDL（Simple DirectMedia Layer）项目托管这份工具包，并在[自己的构建流程](https://discourse.libsdl.org/t/sdl-ci-add-harmonyos-openharmony-builds-to-github-actions/69513)中使用；这是第三方镜像，不是另一种“SDL 版Harmony 模拟器”。

- macOS Apple Silicon：[CLT 6.1.1.280 / Mac ARM64](https://libsdl.org/harmonyos-devtools/commandline-tools-mac-arm64-6.1.1.280.zip)，2,025,336,267 字节（约 2.03 GB）。
- Windows x64 桌面右键入口使用对应 [Windows 包](https://libsdl.org/harmonyos-devtools/commandline-tools-windows-x64-6.1.1.280.zip)，实现与安装方法见[Windows 平行工程](../../WindowsOS@Extension/JobsHarmonySimulatorCreator/README.md)。
- 首屏回车授权后，缺少兼容工具时自动补齐；已有健康工具直接复用。工具安装到 `~/Library/Application Support/JobsHarmonySimulator/clt-6.1.1.280-<唯一后缀>/`，下次自动发现，不覆盖 DevEco 或旧版本。
- 安装前校验固定大小、SHA-256 和 ZIP 路径，解压后检查 `Emulator -help`，通过才发布独立目录。摘要固定于本次验证的 **SDL 镜像快照**，不是华为官方公布的摘要。失败清理本次暂存，保留原有工具、设备和镜像。
- 工具包包含 Emulator 和 SDK，**不包含可启动的 Release 系统镜像**。脚本在缺镜像时通过官方 `-imageList -downloaded false` 读取清单，再用 `-install` 下载选中的稳定版镜像；工具镜像免登录不代表官方服务的所有地区或账号限制都不存在。

已下载同一 ZIP 时可用 `HARMONY_CLT_ARCHIVE=/绝对路径/commandline-tools-mac-arm64-6.1.1.280.zip`，脚本仍执行相同校验，文件不会删除；无需再下载。`--check` / `--help` 始终不下载、不安装。

## 二、<span id="usage">运行、环境与保护边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行：

```shell
/bin/zsh ./Scripts/CreateHarmonySimulator.zsh --help
/bin/zsh ./Scripts/CreateHarmonySimulator.zsh --check
/bin/zsh ./Scripts/CreateHarmonySimulator.zsh --prepare
/bin/zsh ./Scripts/CreateHarmonySimulator.zsh --create
/bin/zsh ./Scripts/CreateHarmonySimulator.zsh \
  --name JobsHarmony_phone \
  --no-start
```

`--check` 可在非交互环境执行，只查询工具帮助、已下载镜像与现有实例；不创建日志目录、不创建、启动或下载。`--prepare` 补齐缺失工具与选中的 Release 系统镜像并复检，不创建设备。

正常入口一路回车采用默认项：确认用途 → 自动补齐缺失工具 → 缺镜像时读取官方清单并默认选择最新稳定版手机 → 确认下载 → 阅读许可原文并回车同意 → 官方下载并复检 → 使用唯一默认名称 → 确认创建 → 启动。已有健康工具与本地镜像直接复用；刚下载的镜像自动用于创建，无须再选一次。工具查询最多等待 60 秒；下载失败或返回成功但本地镜像未就绪时保留诊断并停止，不再进入反复回车复检的循环。

许可原文来自所选 Emulator 同目录 `agreement/` 中的 SDK 与 Software Service 两份协议。每次任务在首次下载或启动前展示一次，只有用户在明确标注“本人同意”的提示下回车，才执行 `-license accept`；任意非空输入取消。仅对已确认的新镜像安装传 `-force` 省去重复安装提示，创建与启动不传此参数。官方额外账号、地区或网络限制按实际错误报告，不更改地区或全局代理。

显式工具路径有误或需改选时仍可进入工具准备向导：1 从 SDL 安装，2 指定已安装路径，3 打开华为官方备选入口。选择器健康 fzf 优先，否则编号选择；回车采用首项，手机优先、系统版本按数字降序。`q`、Esc 或 `Ctrl+C` 取消。默认名称采用 `JobsHarmony_phone_YYYYMMDD_HHMMSS`，设备类型与重名后缀均使用下划线。官方 Emulator 不接受连字符 `-`；本入口将自定义名称限制为英文字母开头、最多 64 字符，只含英文字母、数字、空格、下划线或加号，且不能以空格结尾。显式名称与已有实例按大小写不敏感规则检测冲突，确认创建前再查询一次，不覆盖或删除现有设备。

工具定位支持：

| 环境变量 | 范围 |
| --- | --- |
| `HARMONY_EMULATOR_BIN` | 官方 `Emulator` 可执行文件完整路径，优先级最高。 |
| `DEVECO_STUDIO_HOME` | DevEco `.app` / `Contents` 或 CLT 根目录。 |
| `TOOL_HOME` | 未指定上一项时采用的 DevEco / CLT 根目录。 |
| `HARMONY_CLT_ARCHIVE` | 已下载的同版本 SDL ZIP；安装时校验固定大小与 SHA-256。 |

显式路径缺失、不可执行或能力不兼容时不自动换用其它 SDK；`--check` 直接失败，交互模式可在准备向导中明确改选路径。无显式路径才检查标准 DevEco 安装位置、脚本安装的 CLT 目录及所有 PATH 候选，逐个执行带 15 秒上限的 `-help`，过滤 Android 同名工具和不支持新建的旧版本；仅有一个兼容候选时自动选定，多个兼容候选才要求明确指定。macOS 不区分大小写时，PATH 中的 `emulator` 也可能匹配 `Emulator`，因此不能只按文件名或候选数量判断。环境只影响本次进程，不写 Shell 配置或代理。查询字段严格按官方 `SoftWareVersion`、`deviceType`、`downloaded`、`osVersion`、`releaseType` 处理，Beta 与未下载镜像不进入创建列表。

创建命令成功后仍须在 `-list -details` 中验证唯一名称、设备类型与系统版本；无法解析或内容不匹配时停止，不报告创建成功、不继续启动、不删除实例。官方文档只提供实例字段表，没有完整容器示例；当前接受实例数组或单个明确具 `name` 的对象，并兼容嵌套 `os.osVersion` 与同名扁平键，两者冲突时拒绝。针对 Emulator 6.1.1.200 实测的空结果，仅将退出码为 0 的精确 `No images matching the criteria were found.` / `[Empty]` 转为空数组；其余未知结构仍停止。2026-10-23 已用本机下载的 HarmonyOS 6.0.0(20) 验证非空镜像解析、创建及启动。独立 CLT 布局下，新实例若缺少 SDK 路径，脚本从同包 SDK 验证 HDC 后补入该实例的 `sdkPath`，避免官方按 Studio 目录层级推导到错误位置；保留已有 SDK 字段，不改全局配置或旧实例。

下载 / 启动前展示许可并由本人回车确认，启动保留官方 stdin 处理额外交互。`--no-start` 只创建并核验。工具失败保留退出码、日志和现有设备，启动返回仅表示官方启动命令结束，最终状态看官方窗口与输出。

## 三、<span id="layout">安装单元与目录</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
./
├── JobsHarmonySimulatorCreator.xcodeproj/
├── JobsHarmonySimulatorCreator/        # 后台宿主与私有 Terminal 载体
├── JobsHarmonySimulatorFinderSync/     # 系统桌面空白菜单
├── JobsHarmonySimulatorShared/         # 真实桌面白名单、固定 URL
├── Scripts/                           # 自包含业务脚本、启用辅助脚本及 README
├── Tests/                             # 假 Emulator、菜单、传输及安装测试
├── 【MacOS】安装鸿蒙模拟器Finder扩展.command
└── 【MacOS】卸载鸿蒙模拟器Finder扩展.command
```

| 标识 | 值 |
| --- | --- |
| Scheme / App | `JobsHarmonySimulatorCreator` |
| 扩展 | `JobsHarmonySimulatorFinderSync.appex` |
| 宿主 / 扩展 Bundle ID | `com.jobs.harmonysimulatorcreator` / `com.jobs.harmonysimulatorcreator.findersync` |
| 总面板功能 ID | `harmony-simulator-create` |
| 固定请求 | `jobsharmonysimulatorcreator://simulator/create`，不接受外部参数、路径或脚本。 |

安装 / 卸载入口裸露，与本 README 平级。工程为父仓中的普通源码目录，不含独立 Git，不依赖相邻功能。独立安装产物位于 `./work/DerivedData/`，总安装产物位于上级 `work/JobsHarmonySimulatorCreatorDerivedData/`；系统从该位置启动 App / appex，使用期间保留。两种入口核对并注销同 Bundle ID 的旧路径，保留其它应用。

Finder 监控根目录并按真实 Home/Desktop 白名单筛选，兼容沙盒 Home 重定向、目录元数据不可读及可解析桌面别名。菜单资格由 `contextualMenuForContainer` 表示空白背景；旧 `selectedURLs` 元数据不用于推断菜单类型。所有 `contextualMenuForItems` 均隐藏。宿主每次运行只派发首个合法请求，私有载体目录权限 `700`、文件 `600`，结束后精确清理本次载体，保留业务退出码。

## 四、<span id="logs">日志与排查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 业务日志：系统临时目录 `JobsHarmonySimulator.*/CreateHarmonySimulator.log`，交互确认并通过主机检查后、发现工具之前创建，包含工具筛选与早期失败诊断。
- 宿主诊断：系统临时目录 `JobsHarmonySimulatorCreator.log`；独立安装日志为 `JobsHarmonySimulatorCreatorInstall.log`。
- Terminal 未启动：检查“系统设置 → 隐私与安全性 → 自动化”中本宿主控制 Terminal 的授权。
- 帮助缺少创建能力：升级或选定匹配的官方 DevEco / CLT，不使用 Android emulator 替代。
- 没有工具：正常入口确认后自动从 SDL 下载并校验工具包。下载失败可用 `HARMONY_CLT_ARCHIVE` 指定手动下载的同版本 ZIP；官方登录下载保留为备选。
- 没有镜像：自动读取可下载清单并按所选项下载；本地复检成功后继续。若官方报账号、地区或网络错误，按该错误处理，不会自动登录或无限重试。
- 路径不在标准位置：在准备向导输入 2，可粘贴 DevEco `.app`、CLT 目录或 `Emulator` 文件路径；路径仅用于本次进程，不写 Shell 配置。

## 五、<span id="validation">验证与未执行边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

隔离测试与可复制命令见 [Scripts README](./Scripts/README.md)。2026-10-23 SDL 接入验证：

- macOS CLI 主回归：58 组 / 461 断言通过，包含连续回车下载、许可确认 / 取消、下载失败及假成功、默认手机与数字版本排序；后续参数注入检查与工具恢复专项也通过。
- 总安装映射 8 组 / 42 断言、独立注册 10 组 / 67 断言、桌面菜单 5 组 / 79 断言通过；当前已注册位置的 App 重新构建成功，深度严格签名与打包脚本字节核对通过，Finder 扩展仍启用。
- 已完整获取 SDL Mac ARM64 与 Windows x64 包并固定 SHA-256；Windows ZIP CRC 全检及 102,433 条归档路径核查通过。Mac 包已通过实际安装流程，Emulator 的 Mac 签名显示 Huawei Device / `TZEA3TN37Q`。
- 当前真实在线清单解析通过，共 63 个 Release 条目，默认 `phone / HarmonyOS 6.1.1(24)`；新 `--prepare` 已实测进入下载选择并可取消。后续用户已完成许可确认及 HarmonyOS 6.0.0(20) 镜像下载。
- 本机 CLT 6.1.1.280 / Emulator 6.1.1.200 实测：复用已下载的 HarmonyOS 6.0.0(20) 镜像，成功创建 `JobsHarmony_phone_20261023_142346`；修正 SDK 路径后，官方日志报告 `Guest OS Boot Completed`，HDC 识别 `127.0.0.1:5555` 且远程 shell 返回 `HARMONY_SHELL_READY`。未重新下载镜像；真实实例已保留。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
