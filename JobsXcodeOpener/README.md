> 安装与卸载由 [JobsProjectTools](../JobsProjectTools/README.md) 统一管理，同一 Finder 扩展固定 IDE / Git 菜单顺序。此目录的管理入口仅启停对应单项；请保留完整仓库。下文说明本目录保留的源码工程与构建方式；常规菜单安装使用统一包。

# `JobsXcodeOpener`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、使用方式](#jobs-toc-heading-2)
- [二、安装与卸载](#jobs-toc-heading-3)
- [三、构建与隔离验证](#jobs-toc-heading-4)
- [四、目录与维护入口](#jobs-toc-heading-5)
  - [EnableFinderExtension.zsh](#jobs-toc-heading-6)
- [五、排查与实现依据](#jobs-toc-heading-7)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**菜单范围：桌面空白处不显示本功能；文件夹与项目菜单仍按下文条件显示。桌面上选中的项目文件夹不受此空白菜单规则影响。**

独立 <u>[**Swift**](https://www.swift.org/)</u> macOS App + [**Finder Sync Extension**](https://developer.apple.com/documentation/findersync) 工程，为 Finder 增加“用 Xcode 打开项目”。安装 Finder 扩展已以 [**Xcode**](https://developer.apple.com/xcode) 为前提，点击后直接交给系统打开所选项目，不再重复检测 Xcode 安装状态或打开下载页。

只对非空的 iOS 项目目录或有效 iOS 工程包显示“🛠️ 用 Xcode 打开项目”；同一目标隐藏 Android Studio / VSCode 项目入口。

| 右键目标 | Xcode 入口 | VSCode / Android Studio 入口 |
| --- | --- | --- |
| 当前层有效 iOS Xcode 工程、明确引用它的工作区，或工程包本身 | 显示 | 隐藏 |
| 非空 Flutter 官方 / 鸿蒙根目录 | 隐藏 | 两项显示 |
| 非空 Android 原生根目录 | 隐藏 | 两项显示 |
| 非空普通目录、macOS 工程、纯 Swift Package | 隐藏 | 只显示 VSCode |
| 空目录、仅系统目录元数据、普通文件、链接或多选 | 隐藏 | 隐藏 |

所有 IDE 入口先验证所选对象是可读取的非空目录；仅含 `.DS_Store`、`Thumbs.db`、`desktop.ini` 时视为空，其余隐藏项（包括 `.git`）仍算内容。普通文件、符号链接、多选、失效路径和不支持的目录包不显示；不把普通文件或无效工程包归一到父目录。菜单生成、点击及宿主派发前共用同一规则，目录被清空或项目类型改变时停止打开，也不先查询 IDE 安装或进入下载页。

iOS 资格要求本层 `.xcodeproj/project.pbxproj` 明确配置 `SDKROOT = iphoneos / iphonesimulator`，或 `SUPPORTED_PLATFORMS` 含 iPhone 平台；`.xcworkspace` 必须通过明确的本地工程引用指向这类项目。纯 macOS 工程、仅有 `Package.swift` 或 `Podfile` 不自动当作 iOS 项目。Flutter 根目录即使包含 `ios/` 子工程仍保留 Android Studio / VSCode；单独进入 `ios/` 才按本层工程判断。

读取 Xcode 元数据时单文件上限为 1 MiB；已存在但不可读、编码 / XML 损坏、超过上限或明确的工程引用无法解析时，按未知类型处理，隐藏 VSCode / Android Studio 项目入口，不把读取失败当作非 iOS。可正常读取的 macOS 工程、SDK 宏以及纯 Swift Package 不因此禁用 VSCode。

**常规菜单通过 [管理入口](./【MacOS】管理用Xcode打开Finder扩展.command) 启停对应功能，由 [JobsProjectTools](../JobsProjectTools/README.md) 承载；请保留完整仓库。**

| 项目 | 当前配置 |
| --- | --- |
| 宿主 App / Scheme | `JobsXcodeOpener` |
| 宿主 Bundle ID | `com.jobs.JobsXcodeOpener` |
| 扩展产物 | `JobsXcodeFinderSync.appex` |
| 扩展 Bundle ID | `com.jobs.JobsXcodeOpener.FinderSyncExtension` |
| 系统要求 | macOS `12.0` 及以上 |
| Git 挂载 | [MacOS@Extension](../README.md) 中的普通源码目录，由总仓统一管理 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、使用方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、用 [**Xcode**](https://developer.apple.com/xcode) 打开 `./JobsXcodeOpener.xcodeproj`，选择 `JobsXcodeOpener` Scheme 后运行宿主 App。

2、构建阶段会注册、启用此扩展并刷新 Finder；宿主 App 也提供“重新启用扩展”“打开扩展设置”和“刷新状态”入口。

3、在 Finder 中选中一个非空的 iOS 项目目录或有效 iOS 工程包后右键，也可在项目目录空白处右键，点击“用 Xcode 打开项目”。普通文件、非项目目录和多选时不显示此菜单；点击时重新读取原菜单上下文并复核项目类型。

4、直接选中有效 `.xcworkspace` / `.xcodeproj` 时打开所选工程。目录内先找 `.xcworkspace`，再找 `.xcodeproj`，同一优先级有多个候选时显示选择框，取消后不打开任何项目；仅有 `Package.swift` 时不显示或打开 Xcode 项目入口。没有候选时停止打开，不再把任意目录交给 Xcode。

5、每次点击通过 `Process` 启动系统 `/usr/bin/open`，独立参数为 `-a`、`Xcode` 和项目路径。系统负责定位 Xcode，不预查应用 Bundle、不依赖终端 `PATH` 或固定的 `/Applications` 路径。

6、系统打开命令启动失败或返回非零退出码时显示普通错误，供用户处理系统权限、首次启动或应用自身问题，不转向下载网页。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

菜单安装与卸载统一使用 [图形管理入口](./【MacOS】管理用Xcode打开Finder扩展.app)。直接打开面板，选择“安装 / 更新”或“卸载”并勾选当前范围内的功能；默认空选，点击操作按钮即确认。每项显示等待、正在安装 / 卸载、成功或失败；底部日志实时滚动，可选择复制或复制全部。运行中锁定选择和关闭入口，结束后保留结果与日志。首次打开或面板源码更新后会在后台编译，失败以桌面提示和启动日志说明。

原同名 `.command` 入口保留，终端只负责唤起独立 GUI，随后结束启动脚本；本次启动任务结束后自动关闭对应终端页，安装 / 卸载、进度与实时日志均由 GUI 后台处理。已有交互 Shell 中手工调用时保留原工作会话。内部实现为 `Scripts/ManageExtension.zsh`；完整仓内单功能入口使用总面板的受限范围。可独立复制的包须整体保留 `.command`、`.app`、Scripts、工程源码和资源。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

本入口转交 [JobsProjectTools](../JobsProjectTools/README.md)，只管理 `xcode_opener`，需要保留同仓聚合工程源码。旧宿主、扩展与 Xcode 工程仍供实现参考和隔离验证；常规菜单安装不再注册本目录的旧独立扩展。

需要 macOS 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 与 macOS SDK。安装成功后启用本入口对应功能并保留其它已装选择；卸载仅减去对应功能，仍有其它项时保留共享 App 和登记，最后一项才停用聚合扩展。源码、用户工程、SDK、模拟器、业务数据和既有业务配置保留；安装与卸载只管理菜单，不执行菜单业务。操作完成后刷新 Finder，请先结束 Finder 文件搬移。

诊断保留在终端；聚合工程的构建、配置与登记边界见包说明。

也可从 [总管理面板](../【MacOS】🧩管理Finder扩展.command) 选择一个或多个功能，在同一面板切换安装 / 更新或卸载。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、构建与隔离验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 集成安装可使用父目录的 `../【MacOS】🧩管理Finder扩展.command`；也可独立运行本工程，不依赖其它工程的源码。
- `./Scripts/EnableFinderExtension.zsh` 由 Xcode Build Phase 调用，默认注册扩展并重启 Finder；日志为系统临时目录中的 `JobsXcodeOpenerBuildPhase.log`。
- 设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 可跳过构建阶段注册与 Finder 重启。宿主 App 未启动时，以下命令只构建，不调用 `pluginkit` 或重启 Finder；Xcode 自带的 LaunchServices 登记任务仍可能记录临时 App：

  ```shell
  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 xcodebuild \
    -project './JobsXcodeOpener.xcodeproj' \
    -scheme 'JobsXcodeOpener' \
    -configuration Debug \
    -derivedDataPath "${TMPDIR}JobsXcodeOpenerValidation" \
    CODE_SIGNING_ALLOWED=NO build
  ```

- 行为回归使用 `./Tests/ProjectOpenerBehaviorTests.swift`，通过替身打开器验证项目识别、普通 / Flutter 目录排除、Swift Package、伪工程排除、特殊路径、workspace 优先、多候选选择和取消、系统打开错误；不会实际启动 Xcode 或浏览器：

  ```shell
  xcrun swiftc -parse-as-library \
    './JobsXcodeFinderSync/FlutterProjectValidator.swift' \
    './JobsXcodeFinderSync/XcodeProjectDetector.swift' \
    './JobsXcodeFinderSync/ProjectOpener.swift' \
    './Tests/ProjectOpenerBehaviorTests.swift' \
    -o "${TMPDIR}JobsXcodeOpenerBehaviorTests"
  "${TMPDIR}JobsXcodeOpenerBehaviorTests"
  ```

- 已验证无签名完整构建、ad-hoc 签名完整构建与上述行为测试；真实用户签名、Finder 加载和 IDE 启动仍需在安装后验收。构建验证产生的临时 App LaunchServices 记录已按对应精确路径注销。
- 三个 IDE 扩展各自携带相同的 `XcodeProjectDetector.swift` 和 `FlutterProjectValidator.swift`，无需其它工程源码即可构建。更新菜单规则后须重新构建、安装这三个扩展，再刷新 Finder；只更新 Xcode 扩展不能隐藏另外两个独立扩展的菜单。
- 扩展保留 App Sandbox，沿用本机自用模板的 `/` 只读例外，用于读取所选项目；不修改所选项目。面向商店分发前需重新设计文件授权。
- 先用 `URL` 解析项目，再把完整路径作为 `Process.arguments` 的独立元素传给 `/usr/bin/open -a Xcode`。中文、空格、引号与 Shell 元字符不会被作为 Shell 代码解释，不通过 AppleScript 控制 Xcode。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、目录与维护入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
.
├── JobsXcodeOpener/
│   ├── AppDelegate.swift
│   ├── MainViewController.swift
│   ├── Info.plist
│   └── JobsXcodeOpener.entitlements
├── JobsXcodeFinderSync/
│   ├── FinderSync.swift
│   ├── ProjectOpener.swift
│   ├── XcodeProjectDetector.swift
│   ├── FlutterProjectValidator.swift
│   ├── Info.plist
│   └── JobsXcodeFinderSync.entitlements
├── JobsXcodeOpener.xcodeproj/
│   └── xcshareddata/xcschemes/JobsXcodeOpener.xcscheme
├── Scripts/EnableFinderExtension.zsh
├── Tests/ProjectOpenerBehaviorTests.swift
├── 【MacOS】管理用Xcode打开Finder扩展.command
└── README.md
```

### <span id="jobs-toc-heading-6" data-jobs-toc="v2">[EnableFinderExtension.zsh](./Scripts/EnableFinderExtension.zsh)</span><!-- jobs-toc:heading-end -->

> **目的：** 构建后注册、启用内置扩展，刷新 Finder 菜单。

- 外层安装器或隔离验证传入 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 时立即跳过。
- 普通 Xcode 构建会等待系统异步登记并请求启用，成功后重启 Finder。
- 超时则保留运行标记，交给宿主 App 继续尝试；构建成功不等于菜单已经启用。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">五、排查与实现依据 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 菜单未出现：先在宿主 App 打开扩展设置，确认“用 Xcode 打开项目”已启用；重新打开 Finder 窗口。
- 系统打开失败：先手动启动 Xcode，处理许可、首次启动或系统权限提示，再重新点击菜单；错误弹窗会显示系统打开命令的失败原因。
- 查看扩展日志：使用系统“控制台”应用，过滤进程 `JobsXcodeFinderSync`。宿主与构建日志位于系统临时目录，分别为 `JobsXcodeOpener.log` 和 `JobsXcodeOpenerBuildPhase.log`。
- 打开方式：系统 `open(1)` 命令通过 `-a Xcode` 定位应用；使用 [**Process**](https://developer.apple.com/documentation/foundation/process) 的独立参数传递所选项目路径，不执行 Shell 字符串。
- 源码基于同仓的 `JobsGitRemoteOpener` 自维护模板，使用独立 Bundle ID、Scheme 与源文件；没有复制旧 Git 元数据、截图或构建缓存。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
