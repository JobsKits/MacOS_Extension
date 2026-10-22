# 桌面右键新建鸿蒙模拟器

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、平台与官方命令](#requirements)
- [二、运行、环境与保护边界](#usage)
- [三、安装单元与目录](#layout)
- [四、日志与排查](#logs)
- [五、验证与未执行边界](#validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

Jobs 维护的独立 [**Finder**](https://support.apple.com/guide/mac-help/welcome/mac) 扩展，仅在系统桌面空白菜单提供“新建鸿蒙模拟器”。点击后在 Terminal 选择已下载的 Release 镜像，经确认调用华为官方 `Emulator -create` 创建唯一实例、复查详情并按需启动。源码与安装框架已实现，真实 DevEco 创建仍需相应机器验收。

| 入口 / 条件 | 实际行为 |
| --- | --- |
| 系统桌面空白右键 | 固定请求交给独立 Terminal，执行自包含创建脚本，不要求项目。 |
| 普通目录背景、任何选中项菜单 | 隐藏本入口；点击旧菜单时重新核对桌面上下文。 |
| [独立安装](./【MacOS】安装鸿蒙模拟器Finder扩展.command) | 阅读自述，回车安装，任意非空输入跳过；只构建并启用本扩展。 |
| [独立卸载](./【MacOS】卸载鸿蒙模拟器Finder扩展.command) | 核对已登记路径并输入 `YES`，只移除本功能 App / appex，保留模拟器与镜像。 |
| 没有已下载 Release 镜像 | 提示在 DevEco Studio → Tools → Device Manager → Local Emulator 下载镜像，再重新运行；停止创建。 |

## 一、<span id="requirements">平台与官方命令</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

鸿蒙模拟器使用 [**HarmonyOS**](https://developer.huawei.com/consumer/cn/harmonyos/) 的 DevEco 工具链，与 Android AVD 不互通。本套入口支持 Mac ARM / Windows x86_64（x64）；本目录只处理 Apple Silicon macOS，Windows 实现见[平行工程](../../WindowsOS@Extension/JobsHarmonySimulatorCreator/README.md)。Intel Mac 会停止；Rosetta 终端提示改用原生 Terminal。

扩展构建要求 macOS 12.0+、完整 [**Xcode**](https://developer.apple.com/xcode/) 和 macOS SDK。创建要求 DevEco Studio / Command Line Tools 中具备 `-create` 与 `-imageList` 的官方 Emulator，官方从 DevEco Studio 6.1.0 Beta1 开始提供这两项能力。脚本先运行 `-help` 双检，Android 的同名工具会被拒绝。macOS 27 尚未做真实 DevEco SDK 验收。

实际命令如下，名称及镜像版本均以独立参数传入：

```shell
Emulator -help
Emulator -imageList -downloaded true
Emulator -list -details
Emulator -create JobsHarmony-phone \
  -deviceType phone \
  -osVersion 'HarmonyOS 6.0.1(21)'
Emulator -start JobsHarmony-phone
```

版本文字仅示例，运行时从本机官方查询结果选择，不写死可用版本。实例与镜像目录沿用 DevEco 当前默认配置；不调用 `-config`。命令契约和首次启动许可说明见[华为官方文档](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line)。需要开发者登录的镜像应在 Device Manager 中启动。

## 二、<span id="usage">运行、环境与保护边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行：

```shell
/bin/zsh ./Scripts/CreateHarmonySimulator.zsh --help
/bin/zsh ./Scripts/CreateHarmonySimulator.zsh --check
/bin/zsh ./Scripts/CreateHarmonySimulator.zsh --create
/bin/zsh ./Scripts/CreateHarmonySimulator.zsh \
  --name JobsHarmony-phone \
  --no-start
```

`--check` 可在非交互环境执行，只查询工具帮助、已下载镜像与现有实例；不创建日志目录、不创建、启动或下载。正常运行先显示内置自述并回车确认，再选择设备类型与本地 Release 镜像；健康 fzf 优先，缺失时编号选择，回车采用首项。`q`、Esc 或 `Ctrl+C` 取消。名称默认按设备类型和时间生成；显式名称与已有实例按大小写不敏感规则检测冲突，确认创建前再查询一次，不覆盖或删除现有设备。

工具定位支持：

| 环境变量 | 范围 |
| --- | --- |
| `HARMONY_EMULATOR_BIN` | 官方 `Emulator` 可执行文件完整路径，优先级最高。 |
| `DEVECO_STUDIO_HOME` | DevEco `.app` / `Contents` 或 CLT 根目录。 |
| `TOOL_HOME` | 未指定上一项时采用的 DevEco / CLT 根目录。 |

显式路径缺失或不可执行时直接停止。无显式路径才检查 PATH 与标准 DevEco 安装位置；发现多个候选时要求明确指定，不静默选择。环境只影响本次进程，不写 Shell 配置或代理。查询字段严格按官方 `SoftWareVersion`、`deviceType`、`downloaded`、`osVersion`、`releaseType` 处理，Beta 与未下载镜像不进入创建列表。

创建命令成功后仍须在 `-list -details` 中验证唯一名称、设备类型与系统版本；无法解析或内容不匹配时停止，不报告创建成功、不继续启动、不删除实例。官方文档只提供实例字段表，没有完整容器示例；当前接受实例数组或单个明确具 `name` 的对象，并兼容嵌套 `os.osVersion` 与同名扁平键，两者冲突时拒绝。真实 SDK 输出仍须实机验收，其它未知结构明确停止。

启动保留官方 stdin 许可交互，不传 `-force`、不代答 `yes`。`--no-start` 只创建并核验。工具失败保留退出码、日志和现有设备，启动返回仅表示官方启动命令结束，最终状态看官方窗口与输出。

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

- 业务日志：系统临时目录 `JobsHarmonySimulator.*/CreateHarmonySimulator.log`，交互确认后创建。
- 宿主诊断：系统临时目录 `JobsHarmonySimulatorCreator.log`；独立安装日志为 `JobsHarmonySimulatorCreatorInstall.log`。
- Terminal 未启动：检查“系统设置 → 隐私与安全性 → 自动化”中本宿主控制 Terminal 的授权。
- 帮助缺少创建能力：升级或选定匹配的官方 DevEco / CLT，不使用 Android emulator 替代。
- 没有镜像或官方要求登录：进入 DevEco Device Manager 准备；脚本不下载、不登录、不接受许可。

## 五、<span id="validation">验证与未执行边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

隔离测试与可复制命令见 [Scripts README](./Scripts/README.md)。2026-10-23，CLI 假工具、真实 JXA、固定 URL、桌面背景、私有载体与安装映射回归通过；arm64 两 target Debug 隔离构建、深度严格签名、Bundle ID 和打包业务脚本字节核验通过。Xcode 自动产生的临时注册已按本次 App 精确注销，PlugInKit 前后记录一致。

本次未找到可用的 DevEco Emulator；真实只读检查识别到 PATH 中 Android 同名候选并正确拒绝。未真实下载镜像、创建或启动鸿蒙模拟器，未运行宿主、启用扩展或刷新 Finder。源码与隔离构建通过不替代 macOS 27 / DevEco 实机许可、镜像 JSON 和创建流程验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
