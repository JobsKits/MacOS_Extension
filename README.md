# `MacOS@Extension`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

> **8 个 Finder 右键功能，可逐项勾选：`打开 Git 远程地址`｜`复制 Git 远程地址`｜`复制绝对路径`｜`用终端打开`｜`pod install`｜`flutter pub get`｜`CodeGraph 代码地图`｜`空白 Commit 并 Push`。** 其中 `JobsTerminalOpener` 工程内含后 5 项。

`MacOS@Extension` 用来收纳 Jobs 本机自用的 [**Swift**](https://www.swift.org/) macOS App + Finder Sync Extension 工程。当前目录下有四个 Finder 扩展工程，共提供八个右键增强动作：打开 Git 远程地址、复制 Git 远程地址、复制文件或文件夹绝对路径、用终端打开文件或文件夹所在目录、在合法 iOS 工程执行 `pod install`、在合法 [**Flutter**](https://flutter.dev/) 工程执行 `flutter pub get`、为普通文件夹安装或升级 [**CodeGraph**](https://github.com/colbymchenry/codegraph) 代码地图，以及在 Git 管理的当前文件夹创建无文件变更的空白 Commit 并 Push。

## 一、环境先决条件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 检查项 | 最低要求 | 说明 |
| --- | --- | --- |
| 系统版本 | macOS `12.0` 及以上 | 四个工程的 `MACOSX_DEPLOYMENT_TARGET` 均为 `12.0`，并依赖 macOS 的 Finder Sync Extension 机制。 |
| 开发工具 | [**Xcode**](https://developer.apple.com/xcode) 可正常打开 `.xcodeproj` | 手动运行需要 Xcode；批量安装脚本还需要 `xcodebuild`。首次换机器构建时，按 Xcode 提示完成本机签名配置。 |
| 命令行工具 | `xcodebuild`、`pluginkit`、`pkill`、`killall` 可用 | `xcodebuild` 负责构建 App，`pluginkit` 负责注册和启用 Finder Sync Extension，`pkill pkd` 和 `killall Finder` 用来刷新扩展发现索引与 Finder 菜单缓存。 |
| 安装选择 | 系统 `osascript` 与 AppKit 可用 | 根目录安装脚本会打开 macOS 原生复选框窗口，不再依赖 fzf。 |
| 扩展工程 | 已同步 Finder 扩展子工程 | 如果刚拉取父仓但还没同步子工程，安装脚本会先拉起 `./【MacOS】⏬下载配置当前Git子模块.command`，同步结束并复检通过后再回到安装流程。 |
| Finder 扩展权限 | 系统设置中允许对应 Finder 扩展 | 构建或安装后，如果右键菜单未出现，先到系统设置的扩展管理里确认对应 Finder 扩展已启用，再重新打开 Finder 窗口。 |
| 功能权限 | 按扩展 README 单独确认 | `JobsTerminalOpener` 需要允许控制 `Terminal.app`，iOS / Flutter 依赖操作还要求终端环境已安装 [**CocoaPods**](https://cocoapods.org/) 或 Flutter；CodeGraph 操作会自动检查并补齐 npm、Node.js 和 Homebrew；空白 Commit 操作需要 Git 可用、当前分支可推送且暂存区为空；`JobsGitRemoteOpener` 和 `JobsGitRemoteCopier` 需要读取目标仓库的 `.git/config`；`JobsPathCopier` 和 `JobsGitRemoteCopier` 主要依赖系统剪贴板。 |

常用自检命令：

```shell
xcode-select -p
xcodebuild -version
pluginkit -m -p com.apple.FinderSync -A -v
osascript -e 'return "AppKit UI 可用"'
```

## 二、工程索引 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 工程 | 入口文案 | 核心用途 | 打开方式 |
| --- | --- | --- | --- |
| `./JobsGitRemoteOpener` | `打开 Git 远程地址` | 右键 Git 仓库文件夹，打开 `remote` 对应网页。 | `./JobsGitRemoteOpener/JobsGitRemoteOpener.xcodeproj` |
| `./JobsGitRemoteCopier` | `复制 Git 远程地址` | 右键 Git 仓库文件夹、子目录或文件，复制 `remote` 原始地址。 | `./JobsGitRemoteCopier/JobsGitRemoteCopier.xcodeproj` |
| `./JobsPathCopier` | `复制绝对路径` | 右键任意一个本地文件或文件夹，把绝对路径写入剪贴板。 | `./JobsPathCopier/JobsPathCopier.xcodeproj` |
| `./JobsTerminalOpener` | 5 个可独立勾选的 Terminal 功能 | 包含 `用终端打开`、`pod install`、`flutter pub get`、CodeGraph 代码地图和空白 Commit Push；安装时或 App 内均可逐项决定是否显示。 | `./JobsTerminalOpener/JobsTerminalOpener.xcodeproj` |

## 三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 3.1、原生 UI 勾选安装 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、双击根目录脚本 `./【MacOS】🧩安装Finder扩展.command`。

2、脚本打印内置自述后，按回车继续；如果检测到 `.xcodeproj` 缺失，会先拉起 `./【MacOS】⏬下载配置当前Git子模块.command`。

3、子模块同步结束并复检通过后，脚本会重新进入安装流程并打开 macOS 原生复选框窗口。

4、逐项勾选需要安装的八个右键菜单功能，或点击“全部安装”。`JobsTerminalOpener` 的五项选择会归并为一次工程构建。

5、确认后，脚本会调用 `xcodebuild` 构建相关 App，清理同 Bundle ID 的旧 LaunchServices / PlugInKit 记录，注册并启用 Finder Sync Extension，最后重启 `pkd` 和 Finder 刷新右键菜单缓存。

### 3.2、已安装 App 内调整 Terminal 功能 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、打开已经安装的 `JobsTerminalOpener` App。

2、在“可选功能”区域查看五个独立复选框；每个功能单独占一行，并显示对应的适用条件。

3、勾选后点击“保存功能选择”，关闭当前 Finder 右键菜单并重新右键即可生效，不需要重新编译或重新安装。

4、这里仅管理 `JobsTerminalOpener` 内的五项 Terminal 功能；另外三个独立 Finder 扩展仍由根安装脚本选择安装。

### 3.3、单工程手动运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、进入目标工程目录。

2、用 [**Xcode**](https://developer.apple.com/xcode) 打开对应 `.xcodeproj`。

3、选择同名 Scheme 运行主 App。

4、App 或 Xcode Build Phase 会注册并启用 Finder Sync Extension。

5、回到 Finder，右键符合条件的文件或文件夹，点击对应一级菜单入口。

## 四、维护边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 每个扩展工程保持独立目录、独立 `.xcodeproj`、独立 Bundle ID 和独立卸载脚本；`JobsTerminalOpener` 是当前兼容例外，同一工程承载五项 Terminal 菜单动作，但安装器仍按单个右键功能提供独立复选框。
- Finder Sync Extension 菜单位置由 macOS 决定，本目录只保证扩展注册、启用和菜单动作逻辑。
- 如果 `pluginkit` 显示扩展前缀为 `+`，但 Finder 右键菜单仍缺少对应入口，优先重新运行根目录安装脚本；脚本会清理旧会话、旧 DerivedData 或散落 appex 留下的同 Bundle ID 注册记录。
- 新增同类工程时优先沿用 `JobsGitRemoteOpener` 的主 App 注册流程、Build Phase 启用脚本和 README 结构。
- 根目录只做工程索引；每个工程的具体使用、排查和卸载说明写在各自 `README.md`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
