# `JobsXcodeOpener`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、使用方式](#jobs-toc-heading-2)
- [二、构建与隔离验证](#jobs-toc-heading-3)
- [三、目录与维护入口](#jobs-toc-heading-4)
  - [EnableFinderExtension.zsh](#jobs-toc-heading-5)
  - [【MacOS】卸载用Xcode打开Finder扩展.command](#jobs-toc-heading-6)
- [四、排查与实现依据](#jobs-toc-heading-7)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**菜单范围：桌面空白处不显示本功能；文件夹与项目菜单仍按下文条件显示。桌面上选中的项目文件夹不受此空白菜单规则影响。**

独立 <u>[**Swift**](https://www.swift.org/)</u> macOS App + [**Finder Sync Extension**](https://developer.apple.com/documentation/findersync) 工程，为 Finder 增加“用 Xcode 打开项目”。安装 Finder 扩展已以 [**Xcode**](https://developer.apple.com/xcode) 为前提，点击后直接交给系统打开所选项目，不再重复检测 Xcode 安装状态或打开下载页。

只在 Xcode 项目目录或工程包上显示入口；同一目标由 [VSCode](../JobsVSCodeOpener/README.md)、[Android Studio](../JobsAndroidStudioOpener/README.md) 扩展隐藏各自的打开菜单。

| 右键目标 | Xcode 入口 | VSCode / Android Studio 入口 |
| --- | --- | --- |
| 当前层有 `.xcworkspace` / `.xcodeproj` 的项目目录、工程包本身 | 显示 | 隐藏 |
| 当前层有 `Package.swift` 文件的 Swift Package 目录 | 显示 | 隐藏 |
| Flutter 根目录（即使同层也有 Xcode 工程） | 隐藏 | 保留 Android Studio / VSCode |
| 普通目录 | 隐藏 | 保留原行为 |
| 普通文件 | 隐藏 | 所在目录为 Xcode 项目时隐藏，否则保留原行为 |

工程包必须是目录，并含 `contents.xcworkspacedata` / `project.pbxproj` 文件；空包、同名普通文件或目录形式的 `Package.swift` 不作为项目。只检查当前层，不递归，也不向父目录寻找工程。

Flutter 根目录优先按 `pubspec.yaml` 的 `dependencies.flutter.sdk: flutter` 识别，复用 [Flutter 版本管理器](../JobsFlutterVersionMgr/README.md) 的清单解析；支持块映射和单行 flow 映射，忽略注释及描述字符串中的伪声明。Flutter 根目录只显示 Android Studio / VSCode 打开入口；单独右键它的 `ios/` 原生工程目录或有效工程包时，仍只显示 Xcode。

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

3、在 Finder 中选中一个 Xcode 项目目录或工程包后右键，也可在项目目录空白处右键，点击“用 Xcode 打开项目”。普通文件、非项目目录和多选时不显示此菜单；点击时重新读取原菜单上下文并复核项目类型。

4、直接选中有效 `.xcworkspace` / `.xcodeproj` 时打开所选工程。目录内先找 `.xcworkspace`，再找 `.xcodeproj`，同一优先级有多个候选时显示选择框，取消后不打开任何项目；仅有 `Package.swift` 时打开 Swift Package 目录。没有候选时停止打开，不再把任意目录交给 Xcode。

5、每次点击通过 `Process` 启动系统 `/usr/bin/open`，独立参数为 `-a`、`Xcode` 和项目路径。系统负责定位 Xcode，不预查应用 Bundle、不依赖终端 `PATH` 或固定的 `/Applications` 路径。

6、系统打开命令启动失败或返回非零退出码时显示普通错误，供用户处理系统权限、首次启动或应用自身问题，不转向下载网页。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、构建与隔离验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 集成安装可使用父目录的 `../【MacOS】🧩安装Finder扩展.command`；也可独立运行本工程，不依赖其它工程的源码。
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

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、目录与维护入口 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

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
├── 【MacOS】卸载用Xcode打开Finder扩展.command/
│   ├── 【MacOS】卸载用Xcode打开Finder扩展.command
│   └── README.md
└── README.md
```

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">[EnableFinderExtension.zsh](./Scripts/EnableFinderExtension.zsh)</span><!-- jobs-toc:heading-end -->

> **目的：** 构建后注册、启用内置扩展，刷新 Finder 菜单。

- 外层安装器或隔离验证传入 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 时立即跳过。
- 普通 Xcode 构建会等待系统异步登记并请求启用，成功后重启 Finder。
- 超时则保留运行标记，交给宿主 App 继续尝试；构建成功不等于菜单已经启用。

### <span id="jobs-toc-heading-6" data-jobs-toc="v2">[【MacOS】卸载用Xcode打开Finder扩展.command](./【MacOS】卸载用Xcode打开Finder扩展.command/【MacOS】卸载用Xcode打开Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 停用、注销本功能的 Finder 菜单，并移除已登记的自有 App 构建产物。

- 先打印内置自述，回车后只读收集固定扩展注册路径和核验 App 的 Bundle ID。
- 展示待注销和待删除路径，必须输入 `YES` 才继续；取消不改注册和 App。
- 仅处理本扩展与核验通过的 `JobsXcodeOpener.app`，保留源码与 Xcode 本身，结束时重启 Finder。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">四、排查与实现依据 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 菜单未出现：先在宿主 App 打开扩展设置，确认“用 Xcode 打开项目”已启用；重新打开 Finder 窗口。
- 系统打开失败：先手动启动 Xcode，处理许可、首次启动或系统权限提示，再重新点击菜单；错误弹窗会显示系统打开命令的失败原因。
- 查看扩展日志：使用系统“控制台”应用，过滤进程 `JobsXcodeFinderSync`。宿主与构建日志位于系统临时目录，分别为 `JobsXcodeOpener.log` 和 `JobsXcodeOpenerBuildPhase.log`。
- 打开方式：系统 `open(1)` 命令通过 `-a Xcode` 定位应用；使用 [**Process**](https://developer.apple.com/documentation/foundation/process) 的独立参数传递所选项目路径，不执行 Shell 字符串。
- 源码基于同仓的 `JobsGitRemoteOpener` 自维护模板，使用独立 Bundle ID、Scheme 与源文件；没有复制旧 Git 元数据、截图或构建缓存。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
