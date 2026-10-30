> 安装与卸载由 [JobsProjectTools](../JobsProjectTools/README.md) 统一管理，同一 Finder 扩展固定 IDE / Git 菜单顺序。此目录的管理入口仅启停对应单项；请保留完整仓库。下文说明本目录保留的源码工程与构建方式；常规菜单安装使用统一包。

# `JobsVSCodeOpener`

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

独立 <u>[**Swift**](https://www.swift.org/)</u> macOS App + [**Finder Sync Extension**](https://developer.apple.com/documentation/findersync) 工程，为 Finder 增加“用 VSCode 打开项目”。点击前检查 [**Visual Studio Code**](https://code.visualstudio.com)，没有可用安装时停止项目打开流程，转到[官方下载网页](https://code.visualstudio.com/download)。

**常规菜单通过 [管理入口](./【MacOS】管理用VSCode打开Finder扩展.command) 启停对应功能，由 [JobsProjectTools](../JobsProjectTools/README.md) 承载；请保留完整仓库。**

| 项目 | 当前配置 |
| --- | --- |
| 宿主 App / Scheme | `JobsVSCodeOpener` |
| 宿主 Bundle ID | `com.jobs.JobsVSCodeOpener` |
| 扩展产物 | `JobsVSCodeFinderSync.appex` |
| 扩展 Bundle ID | `com.jobs.JobsVSCodeOpener.FinderSyncExtension` |
| 内部唤起通道 | `jobsvscodeopener://open?p=<base64url 路径>` |
| 系统要求 | macOS `12.0` 及以上 |
| Git 挂载 | [MacOS@Extension](../README.md) 中的普通源码目录，由总仓统一管理 |

源码、文档与版本由 [MacOS@Extension](../README.md) 统一管理，取得总仓即可获得本工程。工程仍保留自己的 Xcode 工程、Scheme、宿主、Finder 扩展与卸载入口。文档目录使用总仓根目录的 [目录过滤器](../.jobs-markdown-toc/README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、使用方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、用 [**Xcode**](https://developer.apple.com/xcode) 打开 `./JobsVSCodeOpener.xcodeproj`，选择 `JobsVSCodeOpener` Scheme 后运行宿主 App。

2、构建阶段会注册、启用此扩展并刷新 Finder；宿主 App 也提供“重新启用扩展”“打开扩展设置”和“刷新状态”入口。

3、在 Finder 中右键非空、非 iOS 的普通文件夹；包括一般目录、Android、Flutter 官方 / 鸿蒙、macOS 工程及纯 Swift Package，也可在该目录内部空白处右键，点击“📝 用 VSCode 打开项目”。空目录不显示此入口。

4、符合条件的项目文件夹原样交给编辑器。所有 IDE 入口先验证所选对象是可读取的非空目录；仅含 `.DS_Store`、`Thumbs.db`、`desktop.ini` 时视为空，其余隐藏项（包括 `.git`）仍算内容。普通文件、符号链接、多选、失效路径和不支持的目录包不显示；不把普通文件或无效工程包归一到父目录。菜单生成、点击及宿主派发前共用同一规则，目录被清空或项目类型改变时停止打开，也不先查询 IDE 安装或进入下载页。

   Android 原生根目录要求本层存在 `settings.gradle` 或 `settings.gradle.kts`，并在本层 / `app/` 的构建脚本中有 Android 插件声明，或存在本层 / `src/main/` / `app/src/main/` 的 `AndroidManifest.xml`；普通 Gradle 项目不满足。Flutter 官方和 Flutter 鸿蒙根目录均以 `pubspec.yaml` 的有效 `dependencies.flutter.sdk: flutter` 声明识别，并优先于本层原生工程。只检查当前层与明确的 Android 标准路径，不递归向上或向下寻找项目。

   iOS 资格要求本层 `.xcodeproj/project.pbxproj` 明确配置 `SDKROOT = iphoneos / iphonesimulator`，或 `SUPPORTED_PLATFORMS` 含 iPhone 平台；`.xcworkspace` 必须通过明确的本地工程引用指向这类项目。纯 macOS 工程、仅有 `Package.swift` 或 `Podfile` 不自动当作 iOS 项目。Flutter 根目录即使包含 `ios/` 子工程仍保留 Android Studio / VSCode；单独进入 `ios/` 才按本层工程判断。

读取 Xcode 元数据时单文件上限为 1 MiB；已存在但不可读、编码 / XML 损坏、超过上限或明确的工程引用无法解析时，按未知类型处理，隐藏 VSCode / Android Studio 项目入口，不把读取失败当作非 iOS。可正常读取的 macOS 工程、SDK 宏以及纯 Swift Package 不因此禁用 VSCode。

5、菜单点击只把路径交给宿主 App：扩展进程在沙盒里调用 LaunchServices 启动外部 App 可能静默失败，所以由宿主完成查找 IDE、打开项目和错误提示。菜单冷启动宿主时不显示配置窗口、不进 Dock，处理完自动退出；手动运行宿主仍显示配置界面。完整宿主必须向 LaunchServices 登记，正常构建或安装会登记 `jobsvscodeopener` 唤起通道；通道未登记时可手动运行一次宿主排查，无须每次先打开配置界面。

6、每次点击都通过 LaunchServices 的 Bundle ID 查找所有已登记副本，核验 App 目录、Bundle ID 和可执行文件；支持常规安装、用户应用目录及系统已登记的其它位置，不依赖终端 `PATH` 或固定的 `/Applications` 路径。

7、缺失、注册残留或可执行文件损坏时，直接打开 `https://code.visualstudio.com/download` 并结束，不会再尝试打开项目。已安装应用启动失败时显示错误，供用户处理系统权限、首次启动或应用自身问题。菜单点击和宿主收到请求后都会复查项目类型；iOS、空目录或失效目标会在查询 VSCode 安装之前被拒绝，也不会进入下载页。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

菜单安装与卸载统一使用 [图形管理入口](./【MacOS】管理用VSCode打开Finder扩展.app)。直接打开面板，选择“安装 / 更新”或“卸载”并勾选当前范围内的功能；默认空选，点击操作按钮即确认。每项显示等待、正在安装 / 卸载、成功或失败；底部日志实时滚动，可选择复制或复制全部。运行中锁定选择和关闭入口，结束后保留结果与日志。首次打开或面板源码更新后会在后台编译，失败以桌面提示和启动日志说明。

原同名 `.command` 入口保留，终端只负责唤起独立 GUI，随后结束启动脚本；本次启动任务结束后自动关闭对应终端页，安装 / 卸载、进度与实时日志均由 GUI 后台处理。已有交互 Shell 中手工调用时保留原工作会话。内部实现为 `Scripts/ManageExtension.zsh`；完整仓内单功能入口使用总面板的受限范围。可独立复制的包须整体保留 `.command`、`.app`、Scripts、工程源码和资源。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

本入口转交 [JobsProjectTools](../JobsProjectTools/README.md)，只管理 `vscode_opener`，需要保留同仓聚合工程源码。旧宿主、扩展与 Xcode 工程仍供实现参考和隔离验证；常规菜单安装不再注册本目录的旧独立扩展。

需要 macOS 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 与 macOS SDK。安装成功后启用本入口对应功能并保留其它已装选择；卸载仅减去对应功能，仍有其它项时保留共享 App 和登记，最后一项才停用聚合扩展。源码、用户工程、SDK、模拟器、业务数据和既有业务配置保留；安装与卸载只管理菜单，不执行菜单业务。操作完成后刷新 Finder，请先结束 Finder 文件搬移。

诊断保留在终端；聚合工程的构建、配置与登记边界见包说明。

也可从 [总管理面板](../【MacOS】🧩管理Finder扩展.command) 选择一个或多个功能，在同一面板切换安装 / 更新或卸载。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、构建与隔离验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 集成安装可使用父目录的 `../【MacOS】🧩管理Finder扩展.command`；也可独立运行本工程，不依赖其它工程的源码。
- `./Scripts/EnableFinderExtension.zsh` 由 Xcode Build Phase 调用，默认注册扩展并重启 Finder；日志为系统临时目录中的 `JobsVSCodeOpenerBuildPhase.log`。
- 设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 可跳过构建阶段注册与 Finder 重启。宿主 App 未启动时，以下命令只构建，不调用 `pluginkit` 或重启 Finder；Xcode 自带的 LaunchServices 登记任务仍可能记录临时 App：

  ```shell
  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 xcodebuild \
    -project './JobsVSCodeOpener.xcodeproj' \
    -scheme 'JobsVSCodeOpener' \
    -configuration Debug \
    -derivedDataPath "${TMPDIR}JobsVSCodeOpenerValidation" \
    CODE_SIGNING_ALLOWED=NO build
  ```

- 行为回归使用 `./Tests/ProjectOpenerBehaviorTests.swift`，通过临时目录和打开器替身验证非空目录、iOS 排除、普通文件 / 链接拒绝、特殊路径、应用健康检查、下载失败及点击时复核；VSCode 同时验证请求编码和主线程完成回调。不会启动真实 IDE 或浏览器：

  ```shell
  xcrun swiftc -parse-as-library \
    './JobsVSCodeFinderSync/ProjectOpener.swift' \
    './JobsVSCodeFinderSync/ProjectRequest.swift' \
    './JobsVSCodeFinderSync/XcodeProjectDetector.swift' \
    './JobsVSCodeFinderSync/FlutterProjectValidator.swift' \
    './Tests/ProjectOpenerBehaviorTests.swift' \
    -o "${TMPDIR}JobsVSCodeOpenerBehaviorTests"
  "${TMPDIR}JobsVSCodeOpenerBehaviorTests"
  ```

- 验证记录（2026-10-19）：Debug ad-hoc 签名完整构建、`codesign --verify --deep --strict` 和上述行为测试通过；通过 `jobsvscodeopener` URL 冷启动宿主已成功在 VSCode 打开 `JobsBaseConfig@JobsFlutterBaseConfigDemo` [**Flutter**](https://flutter.dev/) 项目，宿主随后正常退出；真实 Finder 右键功能已由用户确认可用。早期无签名构建基线通过，最新修复采用上述 ad-hoc 构建验证；真实用户证书签名未验证。
- 源码修复后必须重新编译并部署宿主 App 和其内置扩展，再刷新 Finder；仅重新勾选扩展不会替换系统正在使用的旧二进制。隔离验证结束后，应按精确路径注销该次临时 App 的 LaunchServices 记录；正式部署路径应保留登记。
- 扩展保留 App Sandbox，沿用本机自用模板的 `/` 只读例外，用于读取项目和已安装应用；不修改所选项目。面向商店分发前需重新设计文件授权。
- 路径以 `URL` 直接传给 [**NSWorkspace**](<https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:)>)，不拼接 Shell、AppleScript 或 IDE 命令行。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、目录与维护入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
.
├── JobsVSCodeOpener/
│   ├── main.swift
│   ├── AppDelegate.swift
│   ├── MainViewController.swift
│   ├── Info.plist
│   └── JobsVSCodeOpener.entitlements
├── JobsVSCodeFinderSync/
│   ├── FinderSync.swift
│   ├── ProjectOpener.swift
│   ├── ProjectRequest.swift
│   ├── XcodeProjectDetector.swift
│   ├── FlutterProjectValidator.swift
│   ├── Info.plist
│   └── JobsVSCodeFinderSync.entitlements
├── JobsVSCodeOpener.xcodeproj/
│   └── xcshareddata/xcschemes/JobsVSCodeOpener.xcscheme
├── Scripts/EnableFinderExtension.zsh
├── Tests/ProjectOpenerBehaviorTests.swift
├── 【MacOS】管理用VSCode打开Finder扩展.command
└── README.md
```

### <span id="jobs-toc-heading-6" data-jobs-toc="v2">[EnableFinderExtension.zsh](./Scripts/EnableFinderExtension.zsh)</span><!-- jobs-toc:heading-end -->

> **目的：** 构建后注册、启用内置扩展，刷新 Finder 菜单。

- 外层安装器或隔离验证传入 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 时立即跳过。
- 普通 Xcode 构建会等待系统异步登记并请求启用，成功后重启 Finder。
- 超时则保留运行标记，交给宿主 App 继续尝试；构建成功不等于菜单已经启用。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">五、排查与实现依据 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 菜单未出现：先排除空目录、iOS 项目、普通文件或符号链接；符合范围的目标再在宿主 App 打开扩展设置，确认“用 VSCode 打开项目”已启用，再重新打开 Finder 窗口。
- 点击后完全没反应：先确认已重新编译、部署完整 App 并刷新 Finder，再运行一次宿主，让系统登记 `jobsvscodeopener` 唤起通道；查看系统临时目录中的 `JobsVSCodeOpener.log` 是否收到 `open request`。没有记录时，结合宿主启动日志及“控制台”里 `JobsVSCodeFinderSync` 的 `request host` / `handoff` 日志定位请求停在哪一段。
- 宿主生命周期：纯代码 App 只有 `@main` 时没有显式连接 `AppDelegate`，会导致生命周期和打开请求没有进入代理。`./JobsVSCodeOpener/main.swift` 现在强持有代理、设置 `NSApplication.shared.delegate` 后进入 `NSApplicationMain`；代理在 `applicationWillFinishLaunching` 提前注册 `GURL`，冷启动请求先排队，再于启动完成后处理。入口依据：[Apple NSApplication](https://developer.apple.com/documentation/appkit/nsapplication)。
- 菜单路径传递：原菜单依赖 `NSMenuItem.representedObject` 保存路径，Finder 转发动作时该值丢失会使动作提前返回。现在选中项和空白处菜单分别使用独立 selector，在点击时实时读取 `selectedItemURLs()` / `targetedURL()`；上下文失效会显示提示。调用时机依据：[Apple selectedItemURLs](<https://developer.apple.com/documentation/findersync/fifindersynccontroller/selecteditemurls()>)。
- IDE 明明存在却进入下载页：先手动运行一次 IDE 让系统登记，确认应用包里的可执行文件完整，再重新点击菜单。
- 查看扩展日志：使用系统“控制台”应用，过滤进程 `JobsVSCodeFinderSync`。宿主与构建日志位于系统临时目录，分别为 `JobsVSCodeOpener.log` 和 `JobsVSCodeOpenerBuildPhase.log`。
- 应用发现 API：[Apple NSWorkspace.urlsForApplications](<https://developer.apple.com/documentation/appkit/nsworkspace/urlsforapplications(withbundleidentifier:)>)；打开项目 API：[Apple NSWorkspace.open](<https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:)>)。
- 下载页：[VSCode 官方页面](https://code.visualstudio.com/download)；地址以官方入口为准，浏览器页面可按芯片和系统版本选择安装包。
- 源码基于同仓的 `JobsGitRemoteOpener` 自维护模板，使用独立 Bundle ID、Scheme 与源文件；没有复制旧 Git 元数据、截图或构建缓存。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
