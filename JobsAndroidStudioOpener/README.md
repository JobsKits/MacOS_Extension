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

3、在 Finder 中选中一个本地文件或文件夹后右键，也可在文件夹空白处右键，点击“用 Android Studio 打开项目”。多选多个 Finder 项目时不显示此菜单。实际打开目录属于 Xcode 项目时，隐藏此菜单，只保留“用 Xcode 打开项目”。

4、项目文件夹原样交给编辑器；普通文件归一到其所在目录；选中 `.xcworkspace` / `.xcodeproj` 文件包时归一到文件包的父目录。

   Xcode 项目按当前层的有效 `.xcworkspace` / `.xcodeproj` 目录包或普通 `Package.swift` 文件判定；工程包分别要求含 `contents.xcworkspacedata` / `project.pbxproj` 普通文件，不递归扫描子目录。[**Flutter**](https://flutter.dev/) 根目录由 `pubspec.yaml` 中的 Flutter SDK 依赖识别，只显示 Android Studio / [**Visual Studio Code**](https://code.visualstudio.com) 两种 IDE 入口，即使同层有原生工程也不显示 Xcode；直接选中有效原生工程包或进入 `ios/` 原生项目目录时只显示 Xcode。菜单点击与打开器均会再次复核，Xcode 项目在 IDE 健康检查或下载提示前直接结束。

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

- 行为回归使用 `./Tests/ProjectOpenerBehaviorTests.swift`，通过替身打开器验证目录与特殊路径、Xcode 项目互斥、Flutter 子目录边界、缺失应用停止、多候选选择和取消；不会实际启动 IDE 或浏览器：

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
