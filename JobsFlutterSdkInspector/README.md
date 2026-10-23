> 本功能的右键入口已迁入 [JobsFlutterTools](../JobsFlutterTools/README.md)。以下保留旧独立工程的实现说明；新安装使用统一菜单与项目 FVM。原“Flutter项目体检”在新菜单中称为“原生Flutter项目体检”。

# JobsFlutterSdkInspector

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、使用入口](#jobs-toc-heading-2)
- [二、安装与卸载](#jobs-toc-heading-3)
  - [【MacOS】安装FlutterSDK版本查看Finder扩展.command](#jobs-toc-heading-4)
  - [【MacOS】卸载FlutterSDK版本查看Finder扩展.command](#jobs-toc-heading-5)
- [三、Flutter 项目识别](#jobs-toc-heading-6)
- [四、终端行为与项目配置](#jobs-toc-heading-7)
- [五、工程与项目配置支持](#jobs-toc-heading-8)
- [六、验证与排查](#verification-troubleshooting)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**菜单范围：桌面空白处不显示本功能；文件夹与项目菜单仍按下文条件显示。桌面上选中的项目文件夹不受此空白菜单规则影响。**

独立的 macOS Finder 右键扩展，为指定 [**Flutter**](https://flutter.dev/) 项目**只读查询当前实际使用的 Flutter SDK 版本**。项目由 [**FVM**](https://fvm.app) 管理且已链接 SDK 时显示 FVM 版本；没有 FVM 或 SDK 未链接时显示系统 Flutter SDK 环境。右键直接进入系统 Terminal，版本执行、来源判定与约束核对均在终端中进行；宿主仅在后台转交请求，不显示管理窗口或 Dock 图标。

本工程是 [MacOS@Extension](../README.md) 中的普通源码目录，源码、文档与版本由总仓统一管理。取得总仓即可获得本工程，无需单独远端或子模块下载；工程仍可独立构建、安装与卸载。

本地文档保留 `[toc]`，由总仓根目录的 [目录过滤器](../.jobs-markdown-toc/README.md) 统一管理；新克隆后在总仓根目录安装一次，整文件暂存时生成远端折叠目录。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、使用入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 入口 | 行为 |
| --- | --- |
| 父目录的总安装器 | 勾选“查看当前 Flutter SDK 版本”，构建并启用本功能 |
| [独立安装脚本](#jobs-toc-heading-4) | 只构建、注册并启用本工程 |
| Finder 右键项目文件夹 | 选择“查看当前 Flutter SDK 版本”进入终端 |
| 直接运行 `JobsFlutterSdkInspector.app` | 在后台检查、注册和启用扩展，完成后退出；不打开 Terminal |
| [独立卸载脚本](#jobs-toc-heading-5) | 精确卸载本 Finder 扩展，保留项目与 SDK 工具链 |

首次使用时，在系统扩展设置中允许本 Finder 扩展，并允许宿主 App 自动化控制 Terminal。扩展开关由系统设置或安装器处理；宿主在后台记录注册、启用和调度结果。安装过程会刷新 Finder；请先完成 Finder 中的重要文件操作。

点击菜单后，后台宿主向 Terminal 交付业务启动命令；终端显示业务自述与“已了解用途与影响，按回车继续”的首个确认。Finder 在实际点击时重新读取当前所选项目或空白处对应目录，再次检查项目身份；菜单打开后目录失效、请求无法创建或宿主无法启动时，扩展显示警告。宿主已在处理请求和由菜单首次启动都使用同一入口；后台初始化与所有终端派发完成后自动退出，业务脚本继续在 Terminal 中运行。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

两个入口都是工程根目录下裸露的双击脚本，独立于总仓安装器；本工程可单独拷走安装，不依赖其它工程源码。

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">[【MacOS】安装FlutterSDK版本查看Finder扩展.command](./【MacOS】安装FlutterSDK版本查看Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 独立构建、注册并启用本工程的“查看当前 Flutter SDK 版本”Finder 扩展。

- 先决条件是完整 [**Xcode**](https://developer.apple.com/xcode)：脚本体检 `xcodebuild`、macOS SDK、`pluginkit` 等系统命令与工具链健康，缺失时明确停止，不自动改 `xcode-select`。
- 直接回车安装，输入任意字符（包括空格）后回车跳过；构建产物固定在 `./work/DerivedData/Build/Products/Debug/`，注册后打开宿主 App 并重启 Finder。
- 安装过程不安装任何工具；SDK 版本查询由项目右键动作在 Terminal 中只读执行。日志为系统临时目录中的 `JobsFlutterSdkInspectorInstall.log`。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">[【MacOS】卸载FlutterSDK版本查看Finder扩展.command](./【MacOS】卸载FlutterSDK版本查看Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 停用、注销本功能的 Finder 菜单，并移除已登记的自有 App 构建产物。

- 阅读内置自述并回车，核对真实注册路径与待删除的自有 App；必须输入 `YES` 才继续，其它输入取消，非交互输入直接退出。
- 只删除 Bundle ID 双重核验通过的 `JobsFlutterSdkInspector.app`；保留工程源码、Flutter SDK、FVM 与项目配置。
- 日志为系统临时目录中的 `【MacOS】卸载FlutterSDK版本查看Finder扩展.log`。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">三、Flutter 项目识别 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

仅对单个真实普通文件夹显示菜单，也支持该项目目录的 Finder 空白处右键。多选、普通文件、应用文件包、别名和符号链接不作为目标。只检查所选目录根层的 `pubspec.yaml`，不递归查找项目。

清单必须真实声明 `dependencies.flutter.sdk: flutter`。共享验证器用于菜单显示、点击复检和宿主启动，避免仅凭文件名、注释、`description` 或 `dev_dependencies.flutter_test` 误判。

```yaml
dependencies:
  flutter:
    sdk: flutter
```

也支持常见单行 flow 映射及带引号的键和值：

```yaml
dependencies: {flutter: {sdk: flutter}}
```

验证器采用保守的清单结构识别，拒绝含歧义的重复依赖键；复杂 YAML 锚点、多文档或跨行 flow 映射不属于原生菜单支持范围。遇到这种清单，可先改为上述标准块格式。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">四、终端行为与项目配置 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务脚本全程**只读**：不安装工具、不下载 SDK、不修改任何项目文件。SDK 来源按以下顺序判定：

| 项目状态 | 显示结论 |
| --- | --- |
| `.fvm/flutter_sdk` 链接存在且可执行 | FVM 项目 SDK；执行该链接指向的 `flutter --version --machine` |
| 仅有 `.fvmrc` / `.fvm/fvm_config.json`，无有效链接 | 提示 FVM 配置版本未生效，回退显示系统 SDK |
| 无 FVM 配置 | 系统 Flutter SDK（PATH 与常见安装位置，含 `~/fvm/default`） |

版本结论以实际执行 `flutter --version --machine` 的输出为准，同时输出 Flutter / Dart 版本、发布渠道、Framework 与 Engine revision、SDK 路径，并与 `.fvmrc` 配置版本、`pubspec.yaml` 的 `environment.sdk` / `environment.flutter` 约束逐项核对；无法可靠判定的约束写法明确输出“未判定”，不假装满足。具体确认规则、系统候选顺序、超时与日志说明见 [Scripts 说明](./Scripts/README.md)。脚本也可以在终端独立执行：

```zsh
/bin/zsh "./Scripts/InspectFlutterSdkVersion.zsh" \
  --project "/路径/Flutter项目"
```

终端首个确认提示为“👉 已了解用途与影响，按回车继续；Ctrl+C 取消：”。回车后依次执行项目校验、SDK 定位与版本探测；查询结束输出汇总报告与日志路径。不会改变全局 Flutter 默认版本，也不会写项目任何文件。其它项目继续使用各自配置。

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">五、工程与项目配置支持 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
./
├── JobsFlutterSdkInspector.xcodeproj/   # 工程和共享 Scheme
├── JobsFlutterSdkInspector/            # 后台宿主与终端调度
├── JobsFlutterSdkInspectorFinderSync/     # Finder 菜单扩展
├── JobsFlutterShared/                # 项目识别与请求类型
├── Scripts/                         # 版本查询业务和构建后挂载脚本
├── Tests/                           # 隔离验证
├── 【MacOS】安装FlutterSDK版本查看Finder扩展.command
├── 【MacOS】卸载FlutterSDK版本查看Finder扩展.command
└── work/                            # 本工程独立构建时的本地产物（忽略）
```

`Scripts/` 的实际入口与依赖见 [脚本说明](./Scripts/README.md)。总安装器的构建产物放在总仓 `work/`，本工程独立安装入口使用本工程 `work/`；产物承担系统注册路径，清理前先停用并注销对应扩展。

| 项目项 | 当前值 |
| --- | --- |
| [**Xcode**](https://developer.apple.com/xcode) 工程 / Scheme | `JobsFlutterSdkInspector.xcodeproj` / `JobsFlutterSdkInspector` |
| 宿主产品 / Bundle ID | `JobsFlutterSdkInspector.app` / `com.jobs.JobsFlutterSdkInspector` |
| 扩展产品 / Bundle ID | `JobsFlutterSdkInspectorFinderSync.appex` / `com.jobs.JobsFlutterSdkInspector.FinderSyncExtension` |
| 最低系统 | macOS 12.0 |
| 宿主运行方式 | `LSUIElement` 后台 App，无管理窗口和 Dock 图标，完成初始化与派发后自动退出 |
| Finder 到宿主 | `jobsfluttersdkinspector://inspect?path=...` |
| 宿主业务资源 | `InspectFlutterSdkVersion.zsh`，在宿主 Resources Build Phase 中打包 |
| 构建后挂载脚本 | `Scripts/EnableFinderExtension.zsh` |

`EnableFinderExtension.zsh` 在 Xcode 构建后注册并启用固定扩展，写入系统临时目录中的 `JobsFlutterSdkInspectorBuildPhase.log`；成功后刷新 Finder，尚未启用时保留 `JobsFlutterSdkInspectorNeedsFinderRestart` 标记，宿主启用成功后消费标记。外层安装器及隔离构建设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1`，避免构建期间发生重复注册。

Finder 扩展只读取项目和传送 URL；终端调度由独立宿主执行。宿主复制业务资源到本次专属临时目录，以单行 `/bin/zsh` 启动载体。目录权限 `0700`、文件权限 `0600`，特殊字符路径按字面量传递；正常退出、业务失败或可捕获中断时只清理本次载体及空目录，调度失败也精确清理。业务日志由业务脚本保留。

宿主采用无 nib 的纯代码入口，`main.swift` 显式挂接并持有应用代理，在应用启动完成前注册 URL Apple event 接收器，负责冷启动时的 Finder 请求。它不创建窗口、文件选择器或管理按钮；初始化和所有 Terminal 派发完成后退出，不等待 SDK 操作结束。宿主启动、扩展注册 / 启用、接收项目、Terminal 调度与退出状态会追加写入系统 `/tmp` 目录中的固定日志 `JobsFlutterSdkInspector.log`，并同步到系统日志；它与每次业务操作自己的日志分开保存。

## 六、<span id="verification-troubleshooting">验证与排查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

`Tests/FlutterProjectBehaviorTests.swift` 可与共享验证器、请求转换和终端载体代码一起通过 `swiftc` 编译运行。它使用临时目录和假业务脚本，覆盖标准及 inline 清单、误判排除、路径特殊字符、载体权限、退出码和并发清理，不启动 Terminal 或安装工具。

业务脚本的三种判定分支（系统 SDK、FVM 已链接、非 Flutter 项目拒绝）已在本机用假 SDK 与假项目目录验证：FVM 链接版本与 `.fvmrc` 一致性告警、`environment` 约束满足 / 不满足 / 未判定三类结论均按预期输出。

| 现象 | 排查 |
| --- | --- |
| 没有右键菜单 | 确认扩展开关；只选一个项目根文件夹，并核对清单格式 |
| 菜单出现但点击后没有 Terminal | 核对 `JobsFlutterSdkInspector.log` 是否有本次启动、项目请求及派发记录；宿主没有窗口和 Dock 图标属于正常运行方式 |
| 扩展提示菜单上下文失效 | 关闭菜单，重新选中项目根目录或在该目录空白处右键；点击时会重新读取和验证目标 |
| 日志提示项目无效 | 文件夹可能已移动；确认不是符号链接或文件包 |
| 日志已收到请求但 Terminal 未打开 | 核对日志中的调度错误；在系统隐私设置中允许宿主自动化控制 Terminal |
| 提示未找到可执行的 Flutter SDK | 先安装 Flutter 或用 FVM 安装版本；本功能不自动安装 SDK |
| 版本查询超时 | 按终端提示查看日志；首次冷启动生成 kernel snapshot 较慢，可重试一次 |

宿主日志按以下阶段定位。每次复现先记录时间，避免把之前的追加记录当作本次结果：

| 最后看到的记录 | 下一步核对 |
| --- | --- |
| 没有“宿主启动，URL 接收器已注册” | 直接运行本次安装产物，核对日志中是否出现后台初始化与扩展状态记录；在系统“控制台”按 `JobsFlutterSdkInspector` / `JobsFlutterSdkInspectorFinderSync` 查看启动及扩展错误 |
| 有启动记录，没有“收到 Finder 项目请求” | 核对 Finder 点击警告和扩展日志，确认菜单对应本次安装的宿主与 URL 注册 |
| 已“收到 Finder 项目请求”，没有“正在请求 Terminal” | 查看紧接其后的项目验证或请求错误 |
| 已“正在请求 Terminal”，没有“已交给 Terminal” | 查看宿主随后写入的自动化错误；核对 Terminal 控制权限 |
| 已“已交给 Terminal” | 切到 Terminal 查看业务自述或错误；这个状态只代表启动命令已交付，SDK 操作结果仍以终端为准 |
| 已“后台初始化与所有终端派发已完成，宿主退出” | 宿主按设计退出；已派发的业务继续在 Terminal 中运行，其结果查看终端与业务日志 |

系统交互验收至少覆盖：直接运行 App 只做后台初始化后退出，不出现管理窗口、Dock 图标或 Terminal；宿主未运行时从 Finder 菜单冷启动；后台仍在处理请求时继续接收请求；项目文件夹右键和项目内空白处右键。每条菜单路径均须到达 Terminal 的首个确认，核对目标路径，再按 `Ctrl+C` 退出即可验证启动链路，无需安装工具。构建成功、签名检查和隔离单测通过都不能替代这项验收；真实 SDK 的版本查询结果还需在真实项目上单独核对。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
