# `MacOS@Extension`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、环境先决条件](#environment-prerequisites)
- [二、工程索引](#jobs-toc-heading-3)
- [三、运行方式](#jobs-toc-heading-4)
  - [3.1、原生 UI 勾选安装](#jobs-toc-heading-5)
  - [3.2、已安装 App 内调整 Terminal 功能](#jobs-toc-heading-6)
  - [3.3、单工程手动运行](#jobs-toc-heading-7)
- [四、维护边界](#jobs-toc-heading-8)
- [五、源码取得与单仓管理](#single-repository-management)
- [六、本仓目录与脚本入口](#repository-layout-and-entrypoints)
  - [【MacOS】🧩安装Finder扩展.command](#jobs-toc-heading-11)
  - [【MacOS】🧩卸载Finder扩展.command](#jobs-toc-heading-12)
- [七、项目统计与复核口径](#project-statistics)
  - [7.1、工具链与锁定状态](#jobs-toc-heading-14)
  - [7.2、建库与提交历史](#jobs-toc-heading-15)
  - [7.3、界面、功能与后端边界](#jobs-toc-heading-16)
  - [7.4、模块依赖与核心运行流程](#jobs-toc-heading-17)
  - [7.5、功能实现矩阵](#jobs-toc-heading-18)
  - [7.6、业务代码占比与聚合边界](#jobs-toc-heading-19)
- [八、直接依赖、来源与风险](#direct-dependencies)
- [九、运行、构建与验证补充](#run-and-verify)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

**项目定位：** 面向 Jobs 与 macOS 开发人员的 Finder 日常开发工具集合。**状态：维护中**（基于当前源码与提交活动）；负责人 **Jobs** / [**JobsKits**](https://github.com/JobsKits)，未登记其他维护团队。当前为 **2026-10-20** 完成的单仓管理结构；功能、工程与代码规模的详细复核日期见统计章。

十二个工程的源码由本仓统一管理，取得与更新方式见[源码取得与单仓管理](#single-repository-management)。

本仓由父仓 [`JobsGenesis`](../../README.md) 的 [`.gitmodules`](../../.gitmodules) 直接登记；`OS@Extension/` 只是普通分类目录，没有独立 Git：

```ini
[submodule "MacOS@Extension"]
    path = OS@Extension/MacOS@Extension
    url = ../MacOS_Extension.git
    branch = main
```

`path` 是相对父仓的本地路径，`url` 使用真实远端仓名；本仓根部 `.git` 指向 `../../.git/modules/MacOS@Extension`，不为十二个源码工程重建子 Git。父仓已配置线路的解析如下：

| 父仓地址 | 本仓解析地址 |
| --- | --- |
| `ssh://git@github.com/JobsKits/JobsGenesis.git` | `ssh://git@github.com/JobsKits/MacOS_Extension.git` |
| `git@gitee.com:JobsGo/JobsGenesis.git` | `git@gitee.com:JobsGo/MacOS_Extension.git` |

两平台须拥有父仓 gitlink 引用的提交；`branch = main` 不能代替固定提交，父仓关联提交并推送后才会随远端克隆分发。

> **16 个 Finder 右键功能，可逐项勾选：`打开 Git 远程地址`｜`复制 Git 远程地址`｜`复制绝对路径`｜`用 Xcode 打开项目`｜`用 VSCode 打开项目`｜`用 Android Studio 打开项目`｜`安装/切换 Flutter SDK（FVM）`｜`拉取 Git 到最新`｜`提取 Flutter 第三方依赖`｜`运行 Flutter 项目`｜`用终端打开`｜`pod install`｜`flutter pub get`｜`更新代码地图（.codegraph）`｜`空白 Commit 并 Push`｜`新建 iOS 模拟器`。** 其中 `JobsTerminalOpener` 工程内含 `用终端打开` 至 `空白 Commit 并 Push` 这 5 项。

`MacOS@Extension` 用来收纳 Jobs 本机自用的 <u>[**Swift**](https://www.swift.org/)</u> macOS App + Finder Sync Extension 工程。当前目录下有十二个 Finder 扩展工程，共提供十六个右键增强动作：打开 Git 远程地址、复制 Git 远程地址、复制文件或文件夹绝对路径、分别用 [**Xcode**](https://developer.apple.com/xcode/)、[**Visual Studio Code**](https://code.visualstudio.com/) 和 [**Android Studio**](https://developer.android.com/studio) 打开项目、用终端打开文件或文件夹所在目录、在合法 iOS 工程直接执行 `pod install`、在合法 [**Flutter**](https://flutter.dev/) 工程通过 [**FVM**](https://fvm.app/) 安装或切换 SDK、提取已解析的 Pub 第三方依赖、执行 `flutter pub get`、更新普通文件夹中的 [**CodeGraph**](https://github.com/colbymchenry/codegraph) 代码地图、拉取 Git 到最新，在桌面右键新建并启动 iOS 模拟器，以及在 Git 管理的当前文件夹创建无文件变更的空白 Commit 并 Push。

| 右键入口 | 检查与执行结果 |
| --- | --- |
| [新建 iOS 模拟器](./JobsIOSSimulatorCreator/README.md) | 仅桌面空白处右键打开 Terminal，读取本机可用 iOS Runtime，选择兼容 iPhone / iPad 并创建、启动；不关闭已有设备，不自动下载运行时。 |
| [拉取 Git 到最新](./JobsGitPuller/README.md) | 非 Git 目录静默退出；未提交内容列出后回车确认。先快照再合并，冲突可回滚、`YES` 放弃未提交内容后重试、输入 commit 信息提交后重试；空信息直接回车即可。保留本地提交、不推送、不递归子模块。Windows [对应独立包](../WindowsOS@Extension/JobsGitPuller/README.md)采用相同流程。 |
| [运行 Flutter 项目](./JobsFlutterRunner/README.md) | 只在精确 Flutter 项目根显示；Terminal 选设备，内置缺失 iOS 模拟器创建；launchd 独立托管 Flutter，实时日志、热重载、停止，关闭终端继续运行。 |
| [提取 Flutter 第三方依赖](./JobsFlutterDependencyExtractor/README.md) | 精确 Flutter 项目，终端输入或拖入目标，直接回车默认系统桌面；复制全部已解析 Pub 第三方源码（含间接 / dev），保留许可证并输出版本清单。只读源目录，缺缓存或解析过期停止提示 pub get。Windows [独立包](../WindowsOS@Extension/JobsFlutterDependencyExtractor/README.md)采用同一引擎。 |
| 用 Xcode 打开项目 | 仅 Xcode 项目目录 / 工程包显示；当前层识别有效 workspace、project 或 `Package.swift`，Flutter 根目录优先排除；直接打开，不检查安装或跳下载页。 |
| 用 VSCode 打开项目 | Xcode 项目隐藏；其它目标先检查 VSCode，未安装时停止并打开 [官方下载页](https://code.visualstudio.com/download)。 |
| 用 Android Studio 打开项目 | Xcode 项目隐藏；其它目标先检查 Android Studio，未安装时停止并打开 [官方下载页](https://developer.android.com/studio)。 |
| `pod install` | 目标同层同时存在普通文件 `Podfile` 和至少一个 `*.xcodeproj` 目录包即显示入口，无需已有 workspace。点击后打开 Terminal，在现有交互 Shell 中直接执行单行 `cd -- <安全引用的目标路径> && pod install`；安装交互和错误由 `pod` / `Podfile` 原生处理。 |
| 更新代码地图（.codegraph） | 更新所选文件夹的代码地图；每次检查完整工具链并显示健康 / 异常。缺失工具时在 Terminal 等待回车确认，通过 [**Homebrew**](https://brew.sh/) 补齐 [**Node.js**](https://nodejs.org/) / [**npm**](https://docs.npmjs.com/)，再安装官方 CodeGraph 包。已有健康工具直接复用。 |
| 安装/切换 Flutter SDK（FVM） | 仅对根 `pubspec.yaml` 声明 Flutter SDK 依赖的文件夹显示；右键后直接进入 Terminal，后台宿主不显示管理窗口。在终端体检 Homebrew、FVM、[**fzf**](https://formulae.brew.sh/formula/fzf) 及实际依赖链，查询官方历史和最新发行版，用 fzf 单选精确版本，最终回车执行安装或切换、非空输入取消。详见[独立工程说明](./JobsFlutterVersionMgr/README.md)。 |

<strong id="desktop-menu-scope">桌面与文件夹菜单范围</strong>

| 右键场景 | 本仓加入的菜单 |
| --- | --- |
| 系统桌面空白处 | 仅“新建 iOS 模拟器” |
| 普通文件夹背景 | 按项目条件显示原有开发菜单，不加入“新建 iOS 模拟器” |
| 选中的文件或文件夹（含桌面上的项目） | 保留原有条件菜单，不加入“新建 iOS 模拟器” |

系统自带的“新建文件夹”“更改墙纸”等菜单继续由 macOS 管理。规则按系统桌面真实路径判断，不会把其它位置名为 `Desktop` 的普通目录当作桌面。

桌面范围隔离回归直接编译菜单源码，验证桌面只保留模拟器、普通目录与选中项不显示模拟器，并检查其它项目菜单保持原行为：

```shell
ruby ./Tests/DesktopFinderMenuTests.rb
```

<strong id="single-repository-quick-look">源码与工程边界速览</strong>

十二个 Finder 扩展工程均为本仓中的普通源码目录，源码、文档和版本由 `MacOS@Extension` 统一管理。原工程独立远端已删除，不再使用 `.gitmodules`、gitlink 或工程内 `.git` 关联；克隆或更新本仓即可一并取得全部工程源码，无需递归下载子模块。

Git 管理合并不改变安装单元：各工程保留自己的 Xcode 工程、Scheme、宿主 App、Finder 扩展、Bundle ID 以及原有独立安装 / 卸载入口；Terminal 工程仍包含五个可逐项勾选的功能。文档目录转换统一使用根目录的 [目录过滤器](./.jobs-markdown-toc/README.md)。

## 一、<span id="environment-prerequisites">环境先决条件</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 检查项 | 最低要求 | 说明 |
| --- | --- | --- |
| 系统版本 | macOS `12.0` 及以上 | 十二个工程的 `MACOSX_DEPLOYMENT_TARGET` 均为 `12.0`，并依赖 macOS 的 Finder Sync Extension 机制。 |
| 开发工具 | [**Xcode**](https://developer.apple.com/xcode) 可正常打开 `.xcodeproj` | 手动运行需要 Xcode；批量安装脚本还需要 `xcodebuild`。首次换机器构建时，按 Xcode 提示完成本机签名配置。 |
| 命令行工具 | `xcodebuild`、`pluginkit`、`pkill`、`killall` 可用 | `xcodebuild` 负责构建 App，`pluginkit` 负责注册和启用 Finder Sync Extension，`pkill pkd` 和 `killall Finder` 用来刷新扩展发现索引与 Finder 菜单缓存。 |
| 安装选择 | 系统 `osascript` 与 AppKit 可用 | 根目录安装脚本会打开 macOS 原生复选框窗口，不再依赖 fzf。 |
| 扩展工程 | 本仓十二个工程源码完整 | 源码随本仓一起取得。安装脚本会列出缺失的 `.xcodeproj` 路径并停止；恢复完整源码后重试。 |
| Finder 扩展权限 | 系统设置中允许对应 Finder 扩展 | 构建或安装后，如果右键菜单未出现，先到系统设置的扩展管理里确认对应 Finder 扩展已启用，再重新打开 Finder 窗口。 |
| 功能权限 | 按扩展 README 单独确认 | `JobsTerminalOpener` 需要允许控制 `Terminal.app`，iOS / Flutter 依赖操作还要求终端环境已安装 [**CocoaPods**](https://cocoapods.org/) 或 Flutter；代码地图操作会体检实际依赖链，缺失组件时等待回车确认，再按需经 Homebrew 补齐 Node/npm 并安装 CodeGraph；空白 Commit 操作需要 Git 可用、当前分支可推送且暂存区为空；`JobsGitRemoteOpener` 和 `JobsGitRemoteCopier` 需要读取目标仓库的 `.git/config`；`JobsPathCopier` 和 `JobsGitRemoteCopier` 主要依赖系统剪贴板。 |

常用自检命令：

```shell
xcode-select -p
xcodebuild -version
pluginkit -m -p com.apple.FinderSync -A -v
osascript -e 'return "AppKit UI 可用"'
```

在本仓根目录运行安装器集成回归，核对十六项功能、十二个工程的选择映射，以及工程缺失时的停止提示；测试只使用隔离目录，不构建或注册扩展：

```shell
ruby ./Tests/FlutterInstallerIntegrationTests.rb
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、工程索引 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 工程 | 入口文案 | 核心用途 | 打开方式 |
| --- | --- | --- | --- |
| `./JobsGitRemoteOpener` | `打开 Git 远程地址` | 右键 Git 仓库文件夹，打开 `remote` 对应网页。 | `./JobsGitRemoteOpener/JobsGitRemoteOpener.xcodeproj` |
| `./JobsGitRemoteCopier` | `复制 Git 远程地址` | 右键 Git 仓库文件夹、子目录或文件，复制 `remote` 原始地址。 | `./JobsGitRemoteCopier/JobsGitRemoteCopier.xcodeproj` |
| `./JobsPathCopier` | `复制绝对路径` | 右键任意一个本地文件或文件夹，把绝对路径写入剪贴板。 | `./JobsPathCopier/JobsPathCopier.xcodeproj` |
| `./JobsXcodeOpener` | `用 Xcode 打开项目` | 仅当前层 Xcode 工程 / 工作区 / Swift Package 显示；Flutter 根目录只保留 Android Studio / VSCode，即使同层也有原生工程；单独右键 `ios/` 原生工程按 Xcode 处理。 | `./JobsXcodeOpener/JobsXcodeOpener.xcodeproj` |
| `./JobsVSCodeOpener` | `用 VSCode 打开项目` | Xcode 项目隐藏；其它目录检查 VSCode 后打开，缺失时打开官方下载页。 | `./JobsVSCodeOpener/JobsVSCodeOpener.xcodeproj` |
| `./JobsAndroidStudioOpener` | `用 Android Studio 打开项目` | Xcode 项目隐藏；其它目录检查 Android Studio 后打开，缺失时打开官方下载页。 | `./JobsAndroidStudioOpener/JobsAndroidStudioOpener.xcodeproj` |
| [JobsFlutterVersionMgr](./JobsFlutterVersionMgr/README.md) | `安装/切换 Flutter SDK（FVM）` | 检查 Flutter 项目，终端体检依赖后用 fzf 选择历史或最新 SDK，通过 FVM 安装或切换。 | `./JobsFlutterVersionMgr/JobsFlutterVersionMgr.xcodeproj` |
| [JobsFlutterRunner](./JobsFlutterRunner/README.md) | `运行 Flutter 项目` | 终端选择设备、内置 iOS 模拟器初始化、独立后台运行与日志重连。 | `./JobsFlutterRunner/JobsFlutterRunner.xcodeproj` |
| [JobsFlutterDependencyExtractor](./JobsFlutterDependencyExtractor/README.md) | `提取 Flutter 第三方依赖` | 只读实际 Pub 解析，导出源码、许可证、manifest；目标回车默认桌面。 | `./JobsFlutterDependencyExtractor/JobsFlutterDependencyExtractor.xcodeproj` |
| [JobsGitPuller](./JobsGitPuller/README.md) | `拉取 Git 到最新` | 保护未提交改动，合并当前分支 upstream，冲突提供回滚、放弃、提交后三选一。 | `./JobsGitPuller/JobsGitPuller.xcodeproj` |
| [JobsIOSSimulatorCreator](./JobsIOSSimulatorCreator/README.md) | `新建 iOS 模拟器` | 仅桌面空白右键，选择已安装运行时和兼容机型，新建并启动设备。 | `./JobsIOSSimulatorCreator/JobsIOSSimulatorCreator.xcodeproj` |
| `./JobsTerminalOpener` | 5 个可独立勾选的 Terminal 功能 | 包含 `用终端打开`、`pod install`、`flutter pub get`、`更新代码地图（.codegraph）`和空白 Commit Push；安装时或 App 内均可逐项决定是否显示。 | `./JobsTerminalOpener/JobsTerminalOpener.xcodeproj` |

十二个工程均为本仓管理的普通源码目录，可独立构建与卸载。每个工程根目录统一提供裸露的安装 / 卸载双击脚本，说明见各自 README 的「安装与卸载」章节；使用、自检与项目选择说明同样见各自 README。

各子功能的独立安装入口统一为：直接回车安装，输入任意字符（包括空格）后回车跳过。根目录总安装入口按回车后进入功能勾选面板，选好功能再点击“安装”。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">3.1、原生 UI 勾选安装 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、双击根目录脚本 `./【MacOS】🧩安装Finder扩展.command`。

2、脚本打印内置自述后，按回车继续，检查系统工具及十二个工程的 `.xcodeproj`。

3、任一工程文件缺失时，脚本列出具体路径并停止；从本仓恢复完整源码后重新运行。检查通过后打开 macOS 原生复选框窗口。

4、逐项勾选需要安装的右键菜单功能，也可点击“全选”或“全不选”，选好后点击“安装”；没有勾选时安装按钮置灰。功能列表与底部按钮固定显示，中间区域不滚动。`JobsTerminalOpener` 的五项选择会归并为一次工程构建；十二个工程源码均应随本仓完整取得。

5、确认后，脚本会调用 `xcodebuild` 构建相关 App，清理同 Bundle ID 的旧 LaunchServices / PlugInKit 记录，注册并启用 Finder Sync Extension，最后重启 `pkd` 和 Finder 刷新右键菜单缓存。

### <span id="jobs-toc-heading-6" data-jobs-toc="v2">3.2、已安装 App 内调整 Terminal 功能 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、打开已经安装的 `JobsTerminalOpener` App。

2、在“可选功能”区域查看五个独立复选框；每个功能单独占一行，并显示对应的适用条件。

3、勾选后点击“保存功能选择”，关闭当前 Finder 右键菜单并重新右键即可生效，不需要重新编译或重新安装。

4、这里仅管理 `JobsTerminalOpener` 内的五项 Terminal 功能；其余独立 Finder 扩展由根安装脚本选择安装。

### <span id="jobs-toc-heading-7" data-jobs-toc="v2">3.3、单工程手动运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、进入目标工程目录。

2、用 [**Xcode**](https://developer.apple.com/xcode) 打开对应 `.xcodeproj`。

3、选择同名 Scheme 运行主 App。

4、App 或 Xcode Build Phase 会注册并启用 Finder Sync Extension。

5、回到 Finder，右键符合条件的文件或文件夹，点击对应一级菜单入口。

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">四、维护边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 每个扩展工程保持独立目录、独立 `.xcodeproj`、独立 Bundle ID 和独立卸载脚本；三个 IDE 入口各用一个独立工程。`JobsTerminalOpener` 是当前兼容例外，同一工程承载五项 Terminal 菜单动作，但安装器仍按单个右键功能提供独立复选框；`pod install` 是其中一项。
- Finder Sync Extension 菜单位置由 macOS 决定，本目录只保证扩展注册、启用和菜单动作逻辑。
- 如果 `pluginkit` 显示扩展前缀为 `+`，但 Finder 右键菜单仍缺少对应入口，优先重新运行根目录安装脚本；脚本会清理旧会话、旧 DerivedData 或散落 appex 留下的同 Bundle ID 注册记录。
- 新增同类工程时优先沿用 `JobsGitRemoteOpener` 的主 App 注册流程、Build Phase 启用脚本和 README 结构。
- 根目录只做工程索引；每个工程的具体使用、排查和卸载说明写在各自 `README.md`。

[**Homebrew**](https://brew.sh/) 安装路径由用户选择：已有可运行安装时复用；确实需要安装时先强提示，只有精确输入大写 `YES` 才选择系统标准目录，其它输入或直接回车选择当前用户的 `.local/homebrew`。`YES` 只表示选择路径，权限与密码由官方安装器实际处理；有管理员权限也可以选用户目录。选定路径失败立即停止，不自动切换；`Ctrl+C` / 输入结束取消整个任务。

## 五、<span id="single-repository-management">源码取得与单仓管理</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

从 [**GitHub**](https://github.com/JobsKits/MacOS_Extension) 或 [**Gitee**](https://gitee.com/JobsGo/MacOS_Extension) 取得本仓，十二个工程源码随仓库一起检出，不需要 `--recurse-submodules`。例如：

```shell
git clone https://github.com/JobsKits/MacOS_Extension.git
cd MacOS_Extension
```

已有工作区使用本仓现行分支和 upstream 正常更新；未提交改动先保留、审阅，再按日常 Git 流程处理。工程目录不再单独提交或推送，版本审阅与提交统一在本仓进行。

原根目录的子模块下载、关联修复和 `gitmodules` 更新三个入口已撤销。安装器只检查本仓工程文件是否完整；缺失时列出具体路径并停止，由使用者恢复完整源码后重试。各工程原有独立构建、安装及卸载能力保持不变。

新克隆后，在本仓根目录安装一次文档过滤器；维护本地 `[toc]`，正常整文件暂存时生成远端折叠目录。命令和首次接入边界见 [目录过滤器说明](./.jobs-markdown-toc/README.md)。

```shell
node ./.jobs-markdown-toc/MarkdownToc.mjs install
node ./.jobs-markdown-toc/MarkdownToc.mjs verify
```

## 六、<span id="repository-layout-and-entrypoints">本仓目录与脚本入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下为本仓统一管理的源码与维护入口；依赖环境、Git 元数据、构建缓存和生成产物略去，工程仅列目录。

```text
.
├── .gitignore
├── .gitattributes
├── .jobs-markdown-toc/  # 本仓文档目录工具与精确清单
├── 【MacOS】🧩卸载Finder扩展.command
├── 【MacOS】🧩安装Finder扩展.command
├── icon.png
├── JobsGitRemoteCopier/  # 本仓普通源码目录
├── JobsGitRemoteOpener/  # 本仓普通源码目录
├── JobsPathCopier/  # 本仓普通源码目录
├── JobsXcodeOpener/  # 本仓普通源码目录
├── JobsVSCodeOpener/  # 本仓普通源码目录
├── JobsAndroidStudioOpener/  # 本仓普通源码目录
├── JobsFlutterRunner/  # 本仓普通源码目录
├── JobsFlutterVersionMgr/  # 本仓普通源码目录
├── JobsFlutterDependencyExtractor/  # 本仓普通源码目录
├── JobsGitPuller/  # 本仓普通源码目录
├── JobsIOSSimulatorCreator/  # 桌面右键新建 iOS 模拟器
├── JobsTerminalOpener/  # 本仓普通源码目录
├── README.md
├── Scripts/
│   ├── README.md
│   └── SelectFinderExtensionFeatures.swift
├── Tests/
│   ├── DesktopFinderMenuTests.rb
│   └── FlutterInstallerIntegrationTests.rb
└── work/
    └── README.md
```

* 原有四个扩展工程均为普通源码目录；本仓统一维护各工程、总安装 / 卸载入口及 `Scripts/SelectFinderExtensionFeatures.swift` 原生选择界面。
  * [JobsGitRemoteCopier](./JobsGitRemoteCopier/README.md)、[JobsGitRemoteOpener](./JobsGitRemoteOpener/README.md)、[JobsPathCopier](./JobsPathCopier/README.md)、[JobsTerminalOpener](./JobsTerminalOpener/README.md)。
* 三个 IDE 工程也由本仓统一管理，各自保留独立构建和安装能力：[JobsXcodeOpener](./JobsXcodeOpener/README.md)、[JobsVSCodeOpener](./JobsVSCodeOpener/README.md)、[JobsAndroidStudioOpener](./JobsAndroidStudioOpener/README.md)。
* [JobsFlutterRunner](./JobsFlutterRunner/README.md)：独立 Flutter 运行扩展；Terminal 选设备，launchd 独立托管，关闭终端后继续；仅打包运行脚本与 JXA helper。
* [JobsFlutterVersionMgr](./JobsFlutterVersionMgr/README.md)：独立安装工程，提供 Flutter SDK 安装 / 切换功能，包含宿主、Finder 扩展、终端脚本、独立安装和卸载入口；Windows 对应实现见[平行仓库](../WindowsOS@Extension/README.md)。
* [JobsFlutterDependencyExtractor](./JobsFlutterDependencyExtractor/README.md)：独立安装工程，包含 Flutter 依赖提取宿主与 Finder 扩展；[桌面脚本源包](./JobsFlutterDependencyExtractor/【MacOS】提取Flutter第三方依赖.command/README.md)可整体拷走使用。
* [JobsGitPuller](./JobsGitPuller/README.md)：独立安装工程，包含宿主、Finder 扩展及安装 / 卸载入口；拉取 Git 与冲突三选一在 Terminal 内执行。
* [JobsIOSSimulatorCreator](./JobsIOSSimulatorCreator/README.md)：独立的桌面空白右键入口，后台宿主转发至 Terminal 选择运行时、机型和名称；不清理已有模拟器，内含独立安装 / 卸载脚本。
* [Scripts 目录说明](./Scripts/README.md)：安装器使用的原生功能选择界面及调用约定。
* [目录过滤器说明](./.jobs-markdown-toc/README.md)：本仓自包含转换工具与精确文档清单；本地保留 `[toc]`，整文件暂存时自动生成折叠目录。十二个工程的含标签文档统一登记在根工具的精确清单中。
* [work 目录说明](./work/README.md)：本地 DerivedData、生成 App 与扩展的保存位置及 Git 忽略边界。安装器直接从其中注册 App / appex，清理前应先通过对应卸载入口停用、注销，不能把它当作可随手删除的纯缓存；复制 Git 地址扩展使用工程专用卸载入口。
* 总卸载菜单管理十一个宿主，包括三个 IDE 扩展、Flutter 版本管理、Git 拉取、Flutter 依赖提取、Flutter 运行与 iOS 模拟器创建；`JobsGitRemoteCopier/` 的复制 Git 地址扩展使用其工程卸载脚本。

### <span id="jobs-toc-heading-11" data-jobs-toc="v2">[【MacOS】🧩安装Finder扩展.command](./【MacOS】🧩安装Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 选择并安装本目录的 Finder 右键功能，刷新菜单使其生效。

* 阅读自述并回车，检查系统工具与十二个扩展工程。
  * 任一工程缺失：列出具体 `.xcodeproj` 路径并停止；恢复本仓完整源码后重试。
* 在原生复选框窗口逐项勾选或使用“全选 / 全不选”，再点击“安装”；Terminal 的五项功能归并为一次工程安装。
  * 未选择项目时“安装”置灰；点击取消或关闭窗口退出安装。
* 构建选中的宿主 APP，清理同 Bundle ID 的过期注册，注册并启用对应 Finder 扩展，保存 Terminal 功能选择。
* 对成功安装项刷新 pkd / Finder，汇总结果与日志；失败项在终端显示具体原因。

### <span id="jobs-toc-heading-12" data-jobs-toc="v2">[【MacOS】🧩卸载Finder扩展.command](./【MacOS】🧩卸载Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 批量卸载菜单中选定的 Finder 扩展，并清理相关构建残留。

* 阅读自述并回车，检查 fzf、扩展管理与进程工具。
* 在菜单勾选“打开 Git 远程地址”“复制绝对路径”、三个 IDE 打开入口、“安装/切换 Flutter SDK（FVM）”、“拉取 Git 到最新”、“提取 Flutter 第三方依赖”、“运行 Flutter 项目”、“新建 iOS 模拟器”、“用终端打开”或全选，再回车确认卸载。
  * 取消选择：退出；复制 Git 地址扩展使用其工程专用卸载入口。
* 停用并注销选中扩展，停止对应宿主与扩展进程，清理构建 APP、运行标记和旧 Automator 服务。
* 保留工程源码，刷新 Services 缓存并重启 Finder，汇总成功项、失败项与日志位置。

## 七、<span id="project-statistics">项目统计与复核口径</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

本章功能与运行边界的原复核日期为 **2026-10-19（Asia/Shanghai）**；Git 历史于 **2026-10-20** 按本仓当前 `HEAD` 复核。现有十二个工程均为普通目录，当前历史不合并原工程独立历史；第 7.6 节保留迁移前基线，并另列当前单仓源码快照。本仓及各工程均无根 `.codegraph/`，未建立代码索引。后续功能、依赖或工程变化时同步更新本章。

### <span id="jobs-toc-heading-14" data-jobs-toc="v2">7.1、工具链与锁定状态 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 类别 | 名称 / 版本 | 依据与锁文件入库状态 |
| --- | --- | --- |
| 语言 / SDK | Swift 语言模式 `5.0`；macOS SDK 随所选 Xcode | 十二个 `*.xcodeproj/project.pbxproj` 的 `SWIFT_VERSION`；不是编译器版本锁。 |
| 构建工具 | Xcode 未固定精确版本；工程 `LastUpgradeCheck = 2650` | 此字段仅为工程升级检查记录，最低可构建 Xcode 版本待实机矩阵核实；用 `xcodebuild -version` 记录实际环境。 |
| 最低系统 | macOS `12.0` | 十二个工程全部 target 的 `MACOSX_DEPLOYMENT_TARGET`。 |
| 安装 / 维护 | 系统 zsh、osascript、swiftc、PlugInKit、Git；Ruby 用于隔离测试 | 未设精确版本；本机版本由环境自检确认，不把本机输出视为仓库版本约束。 |
| Node 工具链 | 文档 Node.js `20+`；CodeGraph `1.6.2` 安装链要求 `>=20 <25`，修复使用 Homebrew `node@24` | `.jobs-markdown-toc/README.md` 与 Terminal 工程 `TerminalOpener.swift`；CodeGraph 兼容范围于 2026-10-20 复核，健康既有工具先复用，非精确补丁版本锁。 |
| 功能工具 | FVM / fzf / Flutter / Dart；Pod 功能直接使用终端环境中的 CocoaPods；CodeGraph 经健康检查复用 | 工具按功能使用现有环境或原有安装链，版本来源与风险见[依赖清单](#direct-dependencies)。 |
| 依赖锁定 | 无已入库 `Package.resolved`、`Podfile.lock`、`pubspec.lock` 或 npm 锁文件 | 扩展源码没有第三方 SPM / Pod 包依赖；目标项目自己的锁文件属于操作对象，不属于扩展依赖。源码版本统一由本仓提交记录；这不替代外部工具自身的版本锁。 |

### <span id="jobs-toc-heading-15" data-jobs-toc="v2">7.2、建库与提交历史 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 项目 | 本仓结果 | 口径 / 依据 |
| --- | --- | --- |
| 托管平台建库时间 | 待核实 | 本地 Git 不保存远端仓库创建时间，不拿首个提交冒充建库时间。 |
| 首次提交 | `2026-06-28 20:40:54 +08:00`，`ab9f8b365ed742f8aa8dc640a371500e2f608487` | `git log --reverse --format='%aI %H'` 的首行。 |
| 最近提交 | `2026-10-19 23:45:11 +08:00`，`0c2d4d3640cf1891841006efdb415ce73edf6482` | `git log -1 --format='%aI %H'`；不含未提交修改。 |
| 提交数 | `24` | `git rev-list --count HEAD`；仅本仓当前分支可达历史，原工程独立历史未合并。 |
| 贡献者 | `1` | `git shortlog -sn --all` 按作者身份行数；不等同于当前维护团队规模。 |
| 历史完整性 | 非浅克隆 | `git rev-parse --is-shallow-repository` 为 `false`；以上均为 2026-10-20 本地已取得的历史。 |

在对应 Git 根复核：

```shell
git log --reverse --format='%aI %H %an'
git log -1 --format='%aI %H %an'
git rev-list --count HEAD
git shortlog -sn --all
git rev-parse --is-shallow-repository
```

### <span id="jobs-toc-heading-16" data-jobs-toc="v2">7.3、界面、功能与后端边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 端 / 单位 | 页面数 | 子页面数 | 页面路由数 | 统计依据与排除项（2026-10-20） |
| --- | --- | --- | --- | --- |
| macOS / `NSViewController` | `7` | `0` | `0` | 七个宿主的 `MainViewController.swift`，对应 Git 打开、Git 复制、路径复制、三个 IDE、Terminal。未发现子控制器导航或页面路由表。 |
| 独立安装面板 | 不并入页面数 | — | — | `Scripts/SelectFinderExtensionFeatures.swift` 使用 `NSWindow` / `NSObject`，是安装工具界面；按控制器单位排除。 |
| iOS / Android / Web | 不适用 | 不适用 | 不适用 | 本仓未交付这些平台的前端。Finder 菜单、`NSAlert`、文件选择对话框、终端及外部 IDE 窗口不计页面；无 H5 / 跨端页面容器。 |

七个宿主 `Info.plist` 声明本地 URL Scheme（Terminal、VSCode、FVM、Git 拉取、依赖提取、Flutter 运行、模拟器创建），它们负责 Finder 到宿主的进程间请求，**不算 Web 页面路由或后端 RPC 接口**。右键功能数按选择器中的独立功能标识去重为 `16`，部署按本仓 Xcode 工程去重为 `12` 个 App + 各自 Finder Extension；二者不与页面数混算。

| 后端统计项 | 结果与依据（2026-10-20） |
| --- | --- |
| 对外接口：HTTP / RPC / MQ | 均为 `0`；各宿主、FinderSync 与终端脚本未提供对外监听服务。下载与 Git 网络请求是客户端出站调用，不计入。 |
| 服务模块 / 部署单元 | 后端服务 `0`；本地部署单元为十二组宿主 App / 内嵌 appex，依据十二个 Xcode 工程；不计为十二个后端服务。 |
| 核心业务表 | `0`；未声明自有业务数据库。目标 `.codegraph` 的 SQLite 由外部工具管理。 |
| 业务状态机 | 后端业务状态机 `0`；安装、确认、冲突恢复是本地操作流程，不作为订单等服务业务对象计数。 |
| 外部系统集成 | 无支付 / 短信 / ERP 等业务服务；Git 托管、官方 SDK / 包源及 IDE 为条件工具集成，详见依赖表，目标服务地址随项目配置变化。 |
| 定时 Job / 批处理消费者 | `0` 个常驻调度任务 / 消费者；入口均由用户操作触发，无后台定时同步。 |
| 中间件 | 未声明 Redis、MQ、搜索或对象存储服务；操作目标的依赖不计入扩展自身。 |
| 运行时规模 | QPS、日增数据、存储量不适用；本地耗时、缓存体积未测量，不给出推算值。 |

本地工具没有“页面 : 接口”的业务映射，因此不应用页面与接口比例校验。

### <span id="jobs-toc-heading-17" data-jobs-toc="v2">7.4、模块依赖与核心运行流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

以下为可编辑 [**Mermaid**](https://mermaid.js.org) 源码，虚线表示外部系统或进程边界，节点标出真实入口文件。

```mermaid
flowchart TD
    A["总安装入口<br/>【MacOS】🧩安装Finder扩展.command"] --> B["原生选择器<br/>Scripts/SelectFinderExtensionFeatures.swift"]
    A --> C["本仓十二个工程<br/>安装映射 + 各 project.pbxproj"]
    C --> D["宿主 App<br/>各工程 AppDelegate.swift / main.swift"]
    C --> E["Finder 扩展<br/>各 FinderSync.swift"]
    E --> F["直接系统操作<br/>ProjectOpener.swift / GitRemoteResolver.swift / PathClipboardWriter.swift"]
    E --> D
    D --> G["终端业务桥<br/>TerminalOpener.swift / 各 TerminalLauncher.swift"]
    G --> H["业务脚本<br/>ManageFlutterVersion.zsh / PullGitRepository.zsh / ExtractFlutterDependencies.zsh / CreateIOSSimulator.zsh"]
    F -.-> I["外部 macOS / 剪贴板 / IDE / 浏览器"]
    H -.-> J["外部 Git / FVM / Pub / CocoaPods / CodeGraph / simctl"]
    A -.-> K["外部 xcodebuild / PlugInKit / Finder"]
```

```mermaid
flowchart TD
    A["Finder 右键<br/>各 FinderSync.swift"] --> B{"所选目标符合功能条件?"}
    B -->|否| C["隐藏入口 / 停止并提示"]
    B -->|是| D{"系统直达或终端业务?"}
    D -->|系统操作| E["ProjectOpener / Resolver / ClipboardWriter<br/>打开目标或复制结果"]
    D -->|终端业务| F["宿主 AppDelegate.swift<br/>解码路径并重新校验"]
    F --> G["TerminalLauncher / TerminalOpener.swift<br/>派发终端命令或私有脚本与参数"]
    G -->|pod install| P["Terminal 交互 Shell<br/>cd -- 目标目录 && pod install"]
    P -.-> K
    G -->|脚本动作| H["各 Scripts 业务脚本<br/>自检、展示来源、等待对应确认"]
    H -->|取消 / 失败| I["退出或保留诊断 / 恢复快照"]
    H -->|确认| J["执行所选工具并核验结果"]
    J -.-> K["外部工具及远端 / 项目文件"]
    J --> L["终端展示结果与日志位置"]
```

各动作确认方式不同：FVM 最终回车执行，空白提交须 `YES`，Git 拉取冲突三选一；具体交互沿用[前述运行说明](#前言)与对应工程文档。

### <span id="jobs-toc-heading-18" data-jobs-toc="v2">7.5、功能实现矩阵 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 类目 | 是否涉及 / 实现方式与证据 |
| --- | --- |
| 网络与安全 | 涉及出站 HTTPS、Git 认证复用；无自有 OAuth / JWT / Session 服务、接口加解密或证书绑定实现。FVM 官方清单和来源校验在 `JobsFlutterVersionMgr/Scripts/ManageFlutterVersion.zsh`；Git 网络能力由 Git 承担，不复制用户密钥。 |
| 持久化 / 缓存 / 迁移 | 涉及功能选择配置、终端日志、恢复快照、构建缓存；`JobsTerminalShared/FinderMenuFeatureConfiguration.swift` 位于 Terminal 工程，FVM 脚本保留项目配置字段；无自有数据库 / 通用数据库迁移层。 |
| 端能力 | 涉及 Finder Sync、剪贴板、LaunchServices、AppleEvent / Terminal，见各 `FinderSync.swift`、宿主 `AppDelegate.swift`；蓝牙、推送、定位、相机、相册、生物识别、扫码、NFC、支付未实现，复制路径不计系统分享能力。 |
| 国际化 / 埋点 / 崩溃 | 当前中文菜单与文案；未发现本仓多语言资源表、分析 SDK、崩溃上传 SDK。系统 Console / 终端日志用于诊断。 |
| 热更新 / CI / 多环境 | 无热更新服务与 dev / test / prod API 配置；各工程 Debug / Release。本仓未配置 CI；`Tests/FlutterInstallerIntegrationTests.rb` 为本地隔离集成检查，工程测试各自维护。 |
| 后端工程能力 | 幂等、限流、降级、熔断、分布式锁、业务事务、链路追踪、灰度、对账均无服务端实现；安装去重、临时目录权限和 Git 快照是本地安全机制。 |
| 权限 / 隐私 / 脱敏 | 各工程 `*.entitlements`、`Info.plist` 管理 Finder / 自动化权限；外部路径与远程地址进入日志时需按各实现脱敏，复制 Git 地址按功能保留原始值。未发现已入库 `PrivacyInfo.xcprivacy`，发布前需按实际 API / 数据行为复核，不宣称已经完成商店隐私验收。 |

### <span id="jobs-toc-heading-19" data-jobs-toc="v2">7.6、业务代码占比与聚合边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

以下为 **2026-10-20 单仓迁移前**保存的历史基线：当时将总仓及十个独立工程的 `git ls-files -c -o --exclude-standard` 候选合并，按仓库相对路径去重后统计现存普通文本文件，覆盖当时未提交与未跟踪的自有文件。保留完整分类、聚合表和图，供迁移前后比较；其中含现已撤销的三个根 Git 入口与各工程文档工具副本，不能当作单仓收口后的最新行数或远端已发布统计。后续重算统一使用本仓 `git ls-files -c -o --exclude-standard`，不再跨工程 Git 根聚合。

行数为物理文本行，**包含空行和注释**。业务代码：非测试 Swift / Dart 和三份 FVM、Git 拉取、依赖提取 zsh；测试代码：`Tests/` 下的代码；配置与脚本：其余自有命令、启用 / 卸载脚本、文档目录工具、Xcode 配置、plist、entitlements、Scheme、JSON 和 Git 配置。文档 `.md`、图片等资源、锁文件、`xcuserdata`、第三方、生成代码、`.git`、`node_modules`、`Pods`、`.dart_tool`、`build`、`DerivedData` 与 `work` 排除。自有独立分发的源码副本按物理文件分别计入，不以内容相同合并。

| 类别 | 文件数 | 行数 | 行数占比 |
| --- | --- | --- | --- |
| 业务代码 | `66` | `12,747` | `32.10%` |
| 测试代码 | `16` | `5,020` | `12.64%` |
| 配置与脚本 | `130` | `21,938` | `55.25%` |
| 纳入合计 | `212` | `39,705` | `100.00%` |
| 第三方源码（排除） | 纳入候选中未发现 | — | 不参与分母 |

```mermaid
pie showData
    title 2026-10-20 迁移前自有源码物理行数占比
    "业务代码" : 12747
    "测试代码" : 5020
    "配置与脚本" : 21938
```

| 聚合范围 | 文件数 / 行数（2026-10-20，同上口径） |
| --- | --- |
| 迁移前总仓根级文件 | `12 / 6,924` |
| `JobsGitRemoteCopier` | `15 / 2,398` |
| `JobsGitRemoteOpener` | `15 / 2,334` |
| `JobsPathCopier` | `15 / 2,430` |
| `JobsTerminalOpener` | `23 / 5,364` |
| `JobsAndroidStudioOpener` | `19 / 2,505` |
| `JobsVSCodeOpener` | `21 / 2,915` |
| `JobsXcodeOpener` | `19 / 2,464` |
| `JobsFlutterVersionMgr` | `23 / 3,848` |
| `JobsGitPuller` | `23 / 3,081` |
| `JobsFlutterDependencyExtractor` | `27 / 5,442` |

<strong id="current-source-statistics">当前单仓源码规模（2026-10-20）</strong>

依据本仓 `git ls-files -c -o --exclude-standard` 合并候选、按相对路径去重，统计现存普通 UTF-8 文本；包含未提交与未跟踪源码，排除 Markdown、资源、锁文件、第三方、生成代码、`xcuserdata`、`work` 与常规依赖 / 构建目录。纳入 Swift、Dart、JXA、Shell、Ruby、JS/MJS、AppleScript、Xcode / plist / entitlements / Scheme / JSON / YAML 和 Git 属性配置。行数含空行与注释；`Tests/` 独立计为测试，其余运行时 Swift / Dart / JXA 及五份核心业务 zsh 计为业务，根 `Scripts` 安装选择器和其它工具 / 配置计为配置与脚本。此快照包含模拟器创建与并行新增的 Flutter 运行工程，不代表已提交或远端发布。

| 类别 | 文件数 | 物理行数 | 行数占比 |
| --- | --- | --- | --- |
| 业务代码 | `82` | `15458` | `41.05%` |
| 测试代码 | `23` | `7069` | `18.77%` |
| 配置与脚本 | `116` | `15131` | `40.18%` |
| 纳入合计 | `221` | `37658` | `100.00%` |

```mermaid
pie showData
    title 2026-10-20 当前单仓源码物理行数
    "业务代码" : 15458
    "测试代码" : 7069
    "配置与脚本" : 15131
```

## 八、<span id="direct-dependencies">直接依赖、来源与风险</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

统计日期 **2026-10-19**。十二个 Xcode 工程未声明外部 SPM / Pod 直接源码包，因此构建链接的第三方包数为 `0`；Jobs 工程是自有模块，不当作第三方库。下表列直接调用的外部工具，均为公有来源、私库地址不适用；每项按功能条件使用，不将工具自身的传递依赖或目标项目依赖计入包总数。许可证链接核对上游声明，不替代实际分发版本的 LICENSE / NOTICE。

| 直接工具 | 版本 / 来源 | 许可证 | 用途与仍在使用 |
| --- | --- | --- | --- |
| Git | 未锁定；[官方公库](https://git-scm.com/) / 系统 CLI | [GPL-2.0](https://github.com/git/git/blob/master/COPYING) | 是；远程解析、拉取、空白提交与源码版本管理。 |
| Homebrew | 健康安装复用；缺失时官方稳定发行版，未锁精确版；[公库](https://github.com/Homebrew/brew) | [BSD-2-Clause](https://github.com/Homebrew/brew/blob/master/LICENSE.txt) | 是，按功能需要；依赖安装 / 修复。 |
| FVM | 健康版本能力检测；[公库](https://github.com/leoafarias/fvm)，未锁精确版 | [MIT](https://github.com/leoafarias/fvm/blob/main/LICENSE) | 是；当前目标 Flutter SDK 管理。 |
| fzf | 未锁定；[公库](https://github.com/junegunn/fzf) | [MIT](https://github.com/junegunn/fzf/blob/master/LICENSE) | 是；SDK 单选与卸载选择菜单。 |
| Flutter / Dart | 目标项目精确 SDK 或健康本机工具；[Flutter](https://github.com/flutter/flutter) / [Dart](https://github.com/dart-lang/sdk) 公库 | [Flutter BSD-3-Clause](https://github.com/flutter/flutter/blob/master/LICENSE) / [Dart BSD-3-Clause](https://github.com/dart-lang/sdk/blob/main/LICENSE) | 是；pub get、选版验证、运行自有提取引擎；未将 SDK 源码打入扩展。 |
| Node.js / npm | 文档 Node `20+`；CodeGraph 缺失安装链为 `node@24`；精确补丁未锁定；[Node](https://nodejs.org/) / [npm](https://docs.npmjs.com/) | [Node MIT 及附带第三方条款](https://github.com/nodejs/node/blob/main/LICENSE)；npm 分发条款须随实际版本复核 | 是；文档目录、FVM JSON 辅助与 CodeGraph 安装链。 |
| CodeGraph | 健康 CLI 复用；代码注释和行为基线 `1.6.2`，macOS 安装未锁精确包版本；[公有 npm 包](https://www.npmjs.com/package/@colbymchenry/codegraph) | [MIT](https://github.com/colbymchenry/codegraph/blob/main/LICENSE) | 是；用户触发代码地图创建 / 同步；源码位于 Terminal 工程 `TerminalOpener.swift`。 |
| Ruby / CocoaPods | 复用本机终端环境，精确版由使用者和目标工程决定；[Ruby](https://www.ruby-lang.org/) / [CocoaPods](https://github.com/CocoaPods/CocoaPods) 公有来源 | [Ruby / BSD-2-Clause 双选](https://www.ruby-lang.org/en/about/license.txt)；[CocoaPods MIT](https://github.com/CocoaPods/CocoaPods/blob/master/LICENSE) | 是；Pod 入口直接执行 `pod install`，Ruby 也用于本地测试。 |
| Xcode / Apple 系统框架、IDE 与浏览器 | Xcode / AppKit / FinderSync 随环境；VSCode、Android Studio 按本机安装 | Apple SDK 与各 IDE 自身产品许可；本仓不再分发其二进制 | 是；系统集成与打开目标；不并入第三方源码包数。 |

**风险与处置：** 多数工具浮动或由目标工程决定，首次安装与升级需记录实际 `--version`，健康检查通过仍需验收新版本；尤其 macOS CodeGraph 没有固定 npm 版本，不能把行为基线视为已锁定。Git 的 GPL-2.0 单独标注，当前按外部 CLI 调用，若将工具二进制或源码随产品分发须按该版本条款复核。npm 与 IDE 的完整分发许可仍待核实。未实施安全公告 / 归档状态的全量版本审计，不能声称无漏洞或所有上游均在维护。

## 九、<span id="run-and-verify">运行、构建与验证补充</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[环境先决条件](#environment-prerequisites)与既有运行、安装、卸载章节保留完整操作说明。开发时可在根目录仅构建一个工程，以下示例为 VSCode 工程：

```shell
xcodebuild \
  -project ./JobsVSCodeOpener/JobsVSCodeOpener.xcodeproj \
  -scheme JobsVSCodeOpener \
  -configuration Debug \
  -derivedDataPath ./work/JobsVSCodeOpenerDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 \
  build
```

此命令用于源码构建检查，跳过自有扩展注册 Build Phase；`CODE_SIGNING_ALLOWED=NO` 的产物不能作为已通过签名或 Finder 加载验收。Xcode 自身可能仍登记 App，隔离构建时须按测试产物精确路径处理。用户正式安装使用原安装入口完成签名、注册和刷新，不把上述命令当作安装。

| 环境 / 问题 | 配置与处理 |
| --- | --- |
| dev / test / prod | 未设置服务器环境；Debug / Release 在各 `project.pbxproj`。Terminal 功能配置由安装选择与 `FinderMenuFeatureConfiguration.swift` 管理；测试使用临时项目，避免写真实仓库。 |
| 启动 | 用 Xcode 运行同名宿主 Scheme，或按第三章根安装入口部署；FVM、拉取、提取、模拟器创建宿主只做后台转发，不应期待独立管理窗口。 |
| 测试 | 本仓运行 `ruby ./Tests/FlutterInstallerIntegrationTests.rb`；工程 `Tests/` 按各自 README 运行；文档只读检查 `node ./.jobs-markdown-toc/MarkdownToc.mjs verify`。 |
| 菜单缺失 | 检查 Finder 扩展启用、签名与同 Bundle ID 旧注册；按既有维护章节处理，不能仅以构建成功认定真实菜单可用。 |
| 找不到子工程 / 工具 | 工程缺失时恢复本仓完整源码；缺 Xcode Command Line Tools 或对应 SDK 时先修环境。目标路径、Pod 同层 `Podfile` / `*.xcodeproj` 或 Flutter 根声明不合法时修目标，不绕过门禁。 |
| 网络 / 离线 | 本仓没有 API 假数据模式；FVM 官方列表失败仅可选就绪缓存，其余联网工具依原实现停止并展示来源与错误。 |

本章统计与图按静态源码核对；未因文档维护执行真实安装、卸载、依赖下载、构建、Finder 重启或远端推送。签名加载和全部十六项右键交互仍以对应设备的实际验收为准。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
