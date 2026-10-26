> 安装与卸载由 [JobsProjectTools](../JobsProjectTools/README.md) 统一管理，同一 Finder 扩展固定 IDE / Git 菜单顺序。此目录的安装、卸载入口仅启停对应单项；请保留完整仓库。下文说明本目录保留的源码工程与构建方式；常规菜单安装使用统一包。

# `JobsAndroidStudioOpener`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、使用方式](#jobs-toc-heading-2)
- [二、安装与卸载](#jobs-toc-heading-3)
  - [【MacOS】安装用AndroidStudio打开Finder扩展.command](#jobs-toc-heading-4)
  - [【MacOS】卸载用AndroidStudio打开Finder扩展.command](#jobs-toc-heading-5)
- [三、构建与隔离验证](#jobs-toc-heading-6)
- [四、目录与维护入口](#jobs-toc-heading-7)
  - [EnableFinderExtension.zsh](#jobs-toc-heading-8)
- [五、排查与实现依据](#jobs-toc-heading-9)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**菜单范围：桌面空白处不显示本功能；文件夹与项目菜单仍按下文条件显示。桌面上选中的项目文件夹不受此空白菜单规则影响。**

独立 <u>[**Swift**](https://www.swift.org/)</u> macOS App + [**Finder Sync Extension**](https://developer.apple.com/documentation/findersync) 工程，为 Finder 增加“用 Android Studio 打开项目”。点击前检查 [**Android Studio**](https://developer.android.com/studio?hl=zh-c)，没有可用安装时停止项目打开流程，转到[官方下载网页](https://developer.android.com/studio)。

**本工程是独立安装单元：工程根目录下双击 `./【MacOS】安装用AndroidStudio打开Finder扩展.command` 即可安装本功能，双击 `./【MacOS】卸载用AndroidStudio打开Finder扩展.command` 只卸载本功能，详见[安装与卸载](#jobs-toc-heading-3)。**

| 项目 | 当前配置 |
| --- | --- |
| 宿主 App / Scheme | `JobsAndroidStudioOpener` |
| 宿主 Bundle ID | `com.jobs.JobsAndroidStudioOpener` |
| 扩展产物 | `JobsAndroidStudioFinderSync.appex` |
| 扩展 Bundle ID | `com.jobs.JobsAndroidStudioOpener.FinderSyncExtension` |
| 系统要求 | macOS `12.0` 及以上 |
| Git 挂载 | [MacOS@Extension](../README.md) 中的普通源码目录，由总仓统一管理 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、使用方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、用 [**Xcode**](https://developer.apple.com/xcode) 打开 `./JobsAndroidStudioOpener.xcodeproj`，选择 `JobsAndroidStudioOpener` Scheme 后运行宿主 App。

2、构建阶段会注册、启用此扩展并刷新 Finder；宿主 App 也提供“重新启用扩展”“打开扩展设置”和“刷新状态”入口。

3、在 Finder 中右键非空的 Android 原生、Flutter 官方或 Flutter 鸿蒙项目根目录，也可在该目录内部空白处右键，点击“🧭 用 Android Studio 打开项目”。空目录不显示此入口。

4、符合条件的项目文件夹原样交给编辑器。所有 IDE 入口先验证所选对象是可读取的非空目录；仅含 `.DS_Store`、`Thumbs.db`、`desktop.ini` 时视为空，其余隐藏项（包括 `.git`）仍算内容。普通文件、符号链接、多选、失效路径和不支持的目录包不显示；不把普通文件或无效工程包归一到父目录。菜单生成、点击及宿主派发前共用同一规则，目录被清空或项目类型改变时停止打开，也不先查询 IDE 安装或进入下载页。

   Android 原生根目录要求本层存在 `settings.gradle` 或 `settings.gradle.kts`，并在本层 / `app/` 的构建脚本中有 Android 插件声明，或存在本层 / `src/main/` / `app/src/main/` 的 `AndroidManifest.xml`；普通 Gradle 项目不满足。Flutter 官方和 Flutter 鸿蒙根目录均以 `pubspec.yaml` 的有效 `dependencies.flutter.sdk: flutter` 声明识别，并优先于本层原生工程。只检查当前层与明确的 Android 标准路径，不递归向上或向下寻找项目。

   iOS 资格要求本层 `.xcodeproj/project.pbxproj` 明确配置 `SDKROOT = iphoneos / iphonesimulator`，或 `SUPPORTED_PLATFORMS` 含 iPhone 平台；`.xcworkspace` 必须通过明确的本地工程引用指向这类项目。纯 macOS 工程、仅有 `Package.swift` 或 `Podfile` 不自动当作 iOS 项目。Flutter 根目录即使包含 `ios/` 子工程仍保留 Android Studio / VSCode；单独进入 `ios/` 才按本层工程判断。

读取 Xcode 元数据时单文件上限为 1 MiB；已存在但不可读、编码 / XML 损坏、超过上限或明确的工程引用无法解析时，按未知类型处理，隐藏 VSCode / Android Studio 项目入口，不把读取失败当作非 iOS。可正常读取的 macOS 工程、SDK 宏以及纯 Swift Package 不因此禁用 VSCode。

5、每次点击都通过 LaunchServices 的 Bundle ID 查找所有已登记副本，核验 App 目录、Bundle ID 和可执行文件；支持常规安装、用户应用目录及系统已登记的其它位置，不依赖终端 `PATH` 或固定的 `/Applications` 路径。

6、缺失、注册残留或可执行文件损坏时，直接打开 `https://developer.android.com/studio` 并结束，不会再尝试打开项目。已安装应用启动失败时显示错误，供用户处理系统权限、首次启动或应用自身问题。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

两个入口都是工程根目录下裸露的双击脚本，独立于总仓安装器；本工程可单独拷走安装，不依赖其它工程源码。

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">[【MacOS】安装用AndroidStudio打开Finder扩展.command](./【MacOS】安装用AndroidStudio打开Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 独立构建、注册并启用本工程的“用 Android Studio 打开项目”Finder 扩展。

- 先决条件是完整 [**Xcode**](https://developer.apple.com/xcode)：脚本会体检 `xcodebuild`、`xcrun` macOS SDK、`pluginkit` 等系统命令与工具链健康，缺失时明确停止，不自动改 `xcode-select`。
- 直接回车安装，输入任意字符（包括空格）后回车跳过；构建产物固定在 `./work/DerivedData/Build/Products/Debug/`，注册后打开宿主 App 并重启 Finder。
- 安装过程不下载 Android Studio；IDE 健康检查发生在右键点击时。日志为系统临时目录中的 `JobsAndroidStudioOpenerInstall.log`。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">[【MacOS】卸载用AndroidStudio打开Finder扩展.command](./【MacOS】卸载用AndroidStudio打开Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 停用、注销本功能的 Finder 菜单，并移除已登记的自有 App 构建产物。

- 先阅读内置自述并按回车，再核对真实注册路径与待删除的自有 App；必须输入 `YES` 才继续，其它输入取消，非交互输入直接退出。
- 固定扩展 ID 为 `com.jobs.JobsAndroidStudioOpener.FinderSyncExtension`，只删除名称与 Info.plist Bundle ID 双重核验通过的 `JobsAndroidStudioOpener.app`；符号链接不进入删除范围。
- 保留工程源码、Android Studio、其它扩展与未登记的构建缓存；不使用 `sudo`。日志为系统临时目录中的 `【MacOS】卸载用AndroidStudio打开Finder扩展.log`。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">三、构建与隔离验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 集成安装可使用父目录的 `../【MacOS】🧩安装Finder扩展.command`；也可独立运行本工程，不依赖其它工程的源码。
- `./Scripts/EnableFinderExtension.zsh` 由 Xcode Build Phase 调用，默认注册扩展并重启 Finder；日志为系统临时目录中的 `JobsAndroidStudioOpenerBuildPhase.log`。
- 设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 可跳过构建阶段注册与 Finder 重启。宿主 App 未启动时，以下命令只构建，不调用 `pluginkit` 或重启 Finder；Xcode 自带的 LaunchServices 登记任务仍可能记录临时 App：

  ```shell
  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 xcodebuild \
    -project './JobsAndroidStudioOpener.xcodeproj' \
    -scheme 'JobsAndroidStudioOpener' \
    -configuration Debug \
    -derivedDataPath "${TMPDIR}JobsAndroidStudioOpenerValidation" \
    CODE_SIGNING_ALLOWED=NO build
  ```

- 行为回归使用 `./Tests/ProjectOpenerBehaviorTests.swift`，通过临时目录和打开器替身验证非空目录、iOS 排除、普通文件 / 链接拒绝、特殊路径、应用健康检查、下载失败及点击时复核；VSCode 同时验证请求编码和主线程完成回调。不会启动真实 IDE 或浏览器：

  ```shell
  xcrun swiftc -parse-as-library \
    './JobsAndroidStudioFinderSync/FlutterProjectValidator.swift' \
    './JobsAndroidStudioFinderSync/XcodeProjectDetector.swift' \
    './JobsAndroidStudioFinderSync/ProjectOpener.swift' \
    './Tests/ProjectOpenerBehaviorTests.swift' \
    -o "${TMPDIR}JobsAndroidStudioOpenerBehaviorTests"
  "${TMPDIR}JobsAndroidStudioOpenerBehaviorTests"
  ```

- 已验证无签名完整构建、ad-hoc 签名完整构建与上述行为测试；真实用户签名、Finder 加载和 IDE 启动仍需在安装后验收。构建验证产生的临时 App LaunchServices 记录已按对应精确路径注销。
- 扩展保留 App Sandbox，沿用本机自用模板的 `/` 只读例外，用于读取项目和已安装应用；不修改所选项目。面向商店分发前需重新设计文件授权。
- 路径以 `URL` 直接传给 [**NSWorkspace**](<https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:)>)，不拼接 Shell、AppleScript 或 IDE 命令行。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">四、目录与维护入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
.
├── JobsAndroidStudioOpener/
│   ├── AppDelegate.swift
│   ├── MainViewController.swift
│   ├── Info.plist
│   └── JobsAndroidStudioOpener.entitlements
├── JobsAndroidStudioFinderSync/
│   ├── FinderSync.swift
│   ├── ProjectOpener.swift
│   ├── XcodeProjectDetector.swift
│   ├── FlutterProjectValidator.swift
│   ├── Info.plist
│   └── JobsAndroidStudioFinderSync.entitlements
├── JobsAndroidStudioOpener.xcodeproj/
│   └── xcshareddata/xcschemes/JobsAndroidStudioOpener.xcscheme
├── Scripts/EnableFinderExtension.zsh
├── Tests/ProjectOpenerBehaviorTests.swift
├── 【MacOS】安装用AndroidStudio打开Finder扩展.command
├── 【MacOS】卸载用AndroidStudio打开Finder扩展.command
└── README.md
```

### <span id="jobs-toc-heading-8" data-jobs-toc="v2">[EnableFinderExtension.zsh](./Scripts/EnableFinderExtension.zsh)</span><!-- jobs-toc:heading-end -->

> **目的：** 构建后注册、启用内置扩展，刷新 Finder 菜单。

- 外层安装器或隔离验证传入 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 时立即跳过。
- 普通 Xcode 构建会等待系统异步登记并请求启用，成功后重启 Finder。
- 超时则保留运行标记，交给宿主 App 继续尝试；构建成功不等于菜单已经启用。

## <span id="jobs-toc-heading-9" data-jobs-toc="v2">五、排查与实现依据 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 菜单未出现：Xcode 项目会按规则隐藏；其它目录先在宿主 App 打开扩展设置，确认“用 Android Studio 打开项目”已启用，再重新打开 Finder 窗口。
- IDE 明明存在却进入下载页：先手动运行一次 IDE 让系统登记，确认应用包里的可执行文件完整，再重新点击菜单。
- 查看扩展日志：使用系统“控制台”应用，过滤进程 `JobsAndroidStudioFinderSync`。宿主与构建日志位于系统临时目录，分别为 `JobsAndroidStudioOpener.log` 和 `JobsAndroidStudioOpenerBuildPhase.log`。
- 应用发现 API：[Apple NSWorkspace.urlsForApplications](<https://developer.apple.com/documentation/appkit/nsworkspace/urlsforapplications(withbundleidentifier:)>)；打开项目 API：[Apple NSWorkspace.open](<https://developer.apple.com/documentation/appkit/nsworkspace/open(_:withapplicationat:configuration:completionhandler:)>)。
- 下载页：[Android Studio 官方页面](https://developer.android.com/studio)；地址以官方入口为准，浏览器页面可按芯片和系统版本选择安装包。
- 源码基于同仓的 `JobsGitRemoteOpener` 自维护模板，使用独立 Bundle ID、Scheme 与源文件；没有复制旧 Git 元数据、截图或构建缓存。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
