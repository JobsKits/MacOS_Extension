# `MacOS@Extension`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、环境先决条件](#jobs-toc-heading-2)
- [二、工程索引](#jobs-toc-heading-3)
- [三、运行方式](#jobs-toc-heading-4)
  - [3.1、原生 UI 勾选安装](#jobs-toc-heading-5)
  - [3.2、已安装 App 内调整 Terminal 功能](#jobs-toc-heading-6)
  - [3.3、单工程手动运行](#jobs-toc-heading-7)
- [四、维护边界](#jobs-toc-heading-8)
- [五、Git 子模块脚本](#git-submodule-scripts)
  - [【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command](#jobs-toc-heading-10)
  - [【MacOS】🧭更新引用Git父仓=\>子仓.command](#jobs-toc-heading-11)
  - [【MacOS】🧾更新gitmodules.command](#jobs-toc-heading-12)
- [六、本仓目录与脚本入口](#repository-layout-and-entrypoints)
  - [【MacOS】🧩安装Finder扩展.command](#jobs-toc-heading-14)
  - [【MacOS】🧩卸载Finder扩展.command](#jobs-toc-heading-15)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

子仓下载与关联操作见 [Git 子模块脚本](#git-submodule-scripts)。

> **11 个 Finder 右键功能，可逐项勾选：`打开 Git 远程地址`｜`复制 Git 远程地址`｜`复制绝对路径`｜`用 Xcode 打开项目`｜`用 VSCode 打开项目`｜`用 Android Studio 打开项目`｜`用终端打开`｜`安装/升级 Pod`｜`flutter pub get`｜`更新代码地图（.codegraph）`｜`空白 Commit 并 Push`。** 其中 `JobsTerminalOpener` 工程内含后 5 项。

`MacOS@Extension` 用来收纳 Jobs 本机自用的 <u>[**Swift**](https://www.swift.org/)</u> macOS App + Finder Sync Extension 工程。当前目录下有七个 Finder 扩展工程，共提供十一个右键增强动作：打开 Git 远程地址、复制 Git 远程地址、复制文件或文件夹绝对路径、分别用 [**Xcode**](https://developer.apple.com/xcode/)、[**Visual Studio Code**](https://code.visualstudio.com/) 和 [**Android Studio**](https://developer.android.com/studio) 打开项目、用终端打开文件或文件夹所在目录、在合法 iOS 工程安装或升级 Pod 依赖、在合法 [**Flutter**](https://flutter.dev/) 工程执行 `flutter pub get`、更新普通文件夹中的 [**CodeGraph**](https://github.com/colbymchenry/codegraph) 代码地图，以及在 Git 管理的当前文件夹创建无文件变更的空白 Commit 并 Push。

| 右键入口 | 检查与执行结果 |
| --- | --- |
| 用 Xcode 打开项目 | 直接打开目标项目；开发和安装扩展已以 Xcode 为前提，不再检查安装状态或跳转下载页。 |
| 用 VSCode 打开项目 | 先检查 VSCode；未安装时停止并打开 [官方下载页](https://code.visualstudio.com/download)。 |
| 用 Android Studio 打开项目 | 先检查 Android Studio；未安装时停止并打开 [官方下载页](https://developer.android.com/studio)。 |
| 安装/升级 Pod | 目标同层必须齐全：`Podfile`、`*.xcodeproj`、`*.xcworkspace`。缺任一项不显示入口，宿主也会在打开 Terminal 前拒绝。符合条件后，没有 `Pods/Manifest.lock` 执行 `pod install`，已有则执行 `pod update`；新克隆即便带 `Podfile.lock` 也先安装。 |
| 更新代码地图（.codegraph） | 更新所选文件夹的代码地图；缺失工具时在 Terminal 等待回车确认，通过 [**Homebrew**](https://brew.sh/) 补齐 [**Node.js**](https://nodejs.org/) / [**npm**](https://docs.npmjs.com/)，再安装官方 CodeGraph 包。已有健康工具直接复用。 |

<strong id="submodule-quick-look">父子仓多平台地址速览</strong>

当前七个扩展工程均通过 `./.gitmodules` 和 gitlink 作为独立子仓管理，地址使用相对写法，例如：

```ini
[submodule "JobsGitRemoteCopier"]
    path = JobsGitRemoteCopier
    url = ../JobsGitRemoteCopier.git
    branch = main
```

三个 IDE 工程原先是尚未登记的独立 Git 仓库；现在增量补齐下列关联，原有四个子模块保持不变：

| 本地子仓目录 | `.gitmodules` 地址 | 跟踪分支 |
| --- | --- | --- |
| `JobsAndroidStudioOpener/` | `../JobsAndroidStudioOpener.git` | `main` |
| `JobsVSCodeOpener/` | `../JobsVSCodeOpener.git` | `main` |
| `JobsXcodeOpener/` | `../JobsXcodeOpener.git` | `main` |

父仓仅记录各子仓提交号，不重复跟踪其源码。三个子仓根目录的 `.git` 文件指向父仓实际 Git 目录下各自的 `modules/<子仓名>/`；各自提交历史、分支和已有 HTTPS 远端保持独立。

下表展示原生 Git 从父仓地址解析相对 URL 的结果，前提是全新克隆且没有本地 URL 覆盖。前两行来自本地已配置的 [**GitHub**](https://github.com) / [**Gitee**](https://gitee.com) 远端；自建平台仅为结构示例，未部署。

| 平台 | 父仓克隆地址 | 子仓解析地址 |
| --- | --- | --- |
| GitHub | `git@github.com:JobsKits/MacOS_Extension.git` | `git@github.com:JobsKits/JobsGitRemoteCopier.git` |
| Gitee | `git@gitee.com:JobsGo/MacOS_Extension.git` | `git@gitee.com:JobsGo/JobsGitRemoteCopier.git` |
| 自建平台，仅结构示例 | `ssh://git@git.example.com:2222/team/MacOS_Extension.git` | `ssh://git@git.example.com:2222/team/JobsGitRemoteCopier.git` |

三个 IDE 子仓沿用同一解析规则，例如 `../JobsXcodeOpener.git` 在 GitHub 对应 `git@github.com:JobsKits/JobsXcodeOpener.git`，在 Gitee 对应 `git@gitee.com:JobsGo/JobsXcodeOpener.git`。父仓现有远端使用 SSH；子仓已有的 HTTPS `origin` / `gitee` 不会因登记而被改写。

`path` 是本地目录，`url` 是远端仓库位置；相对 URL 跟随父仓默认远端的平台、组织、协议与端口，前提是该平台已有对应子仓及父仓锁定的提交。已有克隆须核对默认远端和本地子模块配置，仅新增 remote 不会切换线路。

**下载脚本的 Gitee 传输规则：** `【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command` 在本次运行中，将 `git@gitee.com:`、`ssh://git@gitee.com/`、`ssh://git@gitee.com:22/` 开头的标准地址统一通过 `https://gitee.com/` 访问，保留账号、真实仓名和分支；即使设置 `GIT_URL_STYLE=ssh`，这类 Gitee 地址仍使用 HTTPS。各层首次克隆和后续拉取都继承该规则，历史子模块中的 SSH 地址无需新电脑先配置 SSH 密钥。

规则通过追加进程级 `GIT_CONFIG_COUNT` / `url.https://gitee.com/.insteadOf` 配置传给子进程，不写入全局 Git 配置，也不依赖其它工程路径。GitHub、其它主机及非 `22` 的自定义 SSH 端口保持原规则。克隆或递归更新失败会返回非零状态，停止本轮同步并保留错误；不会再输出该项同步成功。各仓清单与浅克隆参数保留；全量删除重建须输入 `YES` 确认，范围限定为清单目标及对应旧仓名目录。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、环境先决条件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 检查项 | 最低要求 | 说明 |
| --- | --- | --- |
| 系统版本 | macOS `12.0` 及以上 | 七个工程的 `MACOSX_DEPLOYMENT_TARGET` 均为 `12.0`，并依赖 macOS 的 Finder Sync Extension 机制。 |
| 开发工具 | [**Xcode**](https://developer.apple.com/xcode) 可正常打开 `.xcodeproj` | 手动运行需要 Xcode；批量安装脚本还需要 `xcodebuild`。首次换机器构建时，按 Xcode 提示完成本机签名配置。 |
| 命令行工具 | `xcodebuild`、`pluginkit`、`pkill`、`killall` 可用 | `xcodebuild` 负责构建 App，`pluginkit` 负责注册和启用 Finder Sync Extension，`pkill pkd` 和 `killall Finder` 用来刷新扩展发现索引与 Finder 菜单缓存。 |
| 安装选择 | 系统 `osascript` 与 AppKit 可用 | 根目录安装脚本会打开 macOS 原生复选框窗口，不再依赖 fzf。 |
| 扩展工程 | 已同步 Finder 扩展子工程 | 如果刚拉取父仓但还没同步子工程，安装脚本会先拉起 `./【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command`，同步结束并复检通过后再回到安装流程。 |
| Finder 扩展权限 | 系统设置中允许对应 Finder 扩展 | 构建或安装后，如果右键菜单未出现，先到系统设置的扩展管理里确认对应 Finder 扩展已启用，再重新打开 Finder 窗口。 |
| 功能权限 | 按扩展 README 单独确认 | `JobsTerminalOpener` 需要允许控制 `Terminal.app`，iOS / Flutter 依赖操作还要求终端环境已安装 [**CocoaPods**](https://cocoapods.org/) 或 Flutter；代码地图操作会体检实际依赖链，缺失组件时等待回车确认，再按需经 Homebrew 补齐 Node/npm 并安装 CodeGraph；空白 Commit 操作需要 Git 可用、当前分支可推送且暂存区为空；`JobsGitRemoteOpener` 和 `JobsGitRemoteCopier` 需要读取目标仓库的 `.git/config`；`JobsPathCopier` 和 `JobsGitRemoteCopier` 主要依赖系统剪贴板。 |

常用自检命令：

```shell
xcode-select -p
xcodebuild -version
pluginkit -m -p com.apple.FinderSync -A -v
osascript -e 'return "AppKit UI 可用"'
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、工程索引 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 工程 | 入口文案 | 核心用途 | 打开方式 |
| --- | --- | --- | --- |
| `./JobsGitRemoteOpener` | `打开 Git 远程地址` | 右键 Git 仓库文件夹，打开 `remote` 对应网页。 | `./JobsGitRemoteOpener/JobsGitRemoteOpener.xcodeproj` |
| `./JobsGitRemoteCopier` | `复制 Git 远程地址` | 右键 Git 仓库文件夹、子目录或文件，复制 `remote` 原始地址。 | `./JobsGitRemoteCopier/JobsGitRemoteCopier.xcodeproj` |
| `./JobsPathCopier` | `复制绝对路径` | 右键任意一个本地文件或文件夹，把绝对路径写入剪贴板。 | `./JobsPathCopier/JobsPathCopier.xcodeproj` |
| `./JobsXcodeOpener` | `用 Xcode 打开项目` | 直接打开目标项目；优先 workspace，同优先级多个候选时明确选择。 | `./JobsXcodeOpener/JobsXcodeOpener.xcodeproj` |
| `./JobsVSCodeOpener` | `用 VSCode 打开项目` | 检查 VSCode 后打开项目目录；缺失时打开官方下载页。 | `./JobsVSCodeOpener/JobsVSCodeOpener.xcodeproj` |
| `./JobsAndroidStudioOpener` | `用 Android Studio 打开项目` | 检查 Android Studio 后打开项目目录；缺失时打开官方下载页。 | `./JobsAndroidStudioOpener/JobsAndroidStudioOpener.xcodeproj` |
| `./JobsTerminalOpener` | 5 个可独立勾选的 Terminal 功能 | 包含 `用终端打开`、`安装/升级 Pod`、`flutter pub get`、`更新代码地图（.codegraph）`和空白 Commit Push；安装时或 App 内均可逐项决定是否显示。 | `./JobsTerminalOpener/JobsTerminalOpener.xcodeproj` |

七个工程均为独立 Git 子模块；父仓维护组合安装入口与各子仓的固定提交引用。每个工程的使用、自检、项目选择与独立卸载说明见各自 README。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">3.1、原生 UI 勾选安装 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、双击根目录脚本 `./【MacOS】🧩安装Finder扩展.command`。

2、脚本打印内置自述后，按回车继续；如果检测到任一子模块的 `.xcodeproj` 缺失，会先拉起 `./【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command`。

3、子模块同步结束并复检通过后，脚本会重新进入安装流程并打开 macOS 原生复选框窗口；三个 IDE 工程与原有四个工程共用这一补齐流程。

4、逐项勾选需要安装的十一个右键菜单功能，或点击“全部安装”。`JobsTerminalOpener` 的五项选择会归并为一次工程构建。

5、确认后，脚本会调用 `xcodebuild` 构建相关 App，清理同 Bundle ID 的旧 LaunchServices / PlugInKit 记录，注册并启用 Finder Sync Extension，最后重启 `pkd` 和 Finder 刷新右键菜单缓存。

### <span id="jobs-toc-heading-6" data-jobs-toc="v2">3.2、已安装 App 内调整 Terminal 功能 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、打开已经安装的 `JobsTerminalOpener` App。

2、在“可选功能”区域查看五个独立复选框；每个功能单独占一行，并显示对应的适用条件。

3、勾选后点击“保存功能选择”，关闭当前 Finder 右键菜单并重新右键即可生效，不需要重新编译或重新安装。

4、这里仅管理 `JobsTerminalOpener` 内的五项 Terminal 功能；另外六个独立 Finder 扩展仍由根安装脚本选择安装。

### <span id="jobs-toc-heading-7" data-jobs-toc="v2">3.3、单工程手动运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、进入目标工程目录。

2、用 [**Xcode**](https://developer.apple.com/xcode) 打开对应 `.xcodeproj`。

3、选择同名 Scheme 运行主 App。

4、App 或 Xcode Build Phase 会注册并启用 Finder Sync Extension。

5、回到 Finder，右键符合条件的文件或文件夹，点击对应一级菜单入口。

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">四、维护边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 每个扩展工程保持独立目录、独立 `.xcodeproj`、独立 Bundle ID 和独立卸载脚本；三个 IDE 入口各用一个独立工程。`JobsTerminalOpener` 是当前兼容例外，同一工程承载五项 Terminal 菜单动作，但安装器仍按单个右键功能提供独立复选框；Pod 安装与升级合为其中一项，不拆成两个开关。
- Finder Sync Extension 菜单位置由 macOS 决定，本目录只保证扩展注册、启用和菜单动作逻辑。
- 如果 `pluginkit` 显示扩展前缀为 `+`，但 Finder 右键菜单仍缺少对应入口，优先重新运行根目录安装脚本；脚本会清理旧会话、旧 DerivedData 或散落 appex 留下的同 Bundle ID 注册记录。
- 新增同类工程时优先沿用 `JobsGitRemoteOpener` 的主 App 注册流程、Build Phase 启用脚本和 README 结构。
- 根目录只做工程索引；每个工程的具体使用、排查和卸载说明写在各自 `README.md`。

[**Homebrew**](https://brew.sh/) 安装路径由用户选择：已有可运行安装时复用；确实需要安装时先强提示，只有精确输入大写 `YES` 才选择系统标准目录，其它输入或直接回车选择当前用户的 `.local/homebrew`。`YES` 只表示选择路径，权限与密码由官方安装器实际处理；有管理员权限也可以选用户目录。选定路径失败立即停止，不自动切换；`Ctrl+C` / 输入结束取消整个任务。

## 五、<span id="git-submodule-scripts">Git 子模块脚本</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### <span id="jobs-toc-heading-10" data-jobs-toc="v2">[【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command](./【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 将选中的子仓及可选的后代子模块更新到各自远端目标分支最新版本，并维护入口父仓关联。

* 确认自述后读取脚本清单、检查远端，尝试拉取父仓。
* 父仓有未提交改动：跳过父仓拉取，继续处理子仓。
* 在主菜单选择同步范围；“切换同步深度”可在默认“向下递归”和“仅直属子模块”之间切换，当前深度适用于各同步动作。
  * 全量同步：选择清单内全部目标重建，须输入 `YES` 执行，其它输入取消。
  * 只更新已有：更新清单内已存在的子仓；一个都没有时转全量同步。
  * 指定子模块：回车勾选或取消，空格确认开始。
  * 添加地址：输入新仓地址，自动用仓名作为目录，本轮登记并同步。
* 补齐关联配置，检查并处理目标子仓目录。
  * 全量模式：清洁检查通过后删除目标目录、对应仓名的旧目录及缓存，再重新克隆。
  * 其它模式：缺失的目标目录首次克隆，已有子仓继续更新。
  * 子仓有未提交改动：停止该项更新。
* 拉取并强制对齐远端目标分支最新提交：优先使用该层 `.gitmodules` 显式 `branch`，`.` 继承直接父仓分支；未设置时优先 `main`，不存在则使用远端默认分支。
  * 使用 `checkout -B` 和 `reset --hard`：目标本地分支未推送的独有提交可能被覆盖。
* 按当前深度同步：默认逐层读取所选子仓下的 `.gitmodules`，将已登记后代同步到各自远端目标分支最新提交；仅直属模式不下载或更新下层代码。
  * 只处理本层所选子树，不向上扫描，也不接管未登记的嵌套仓库。
  * 深层只下载更新，不自动暂存或提交其父仓的 gitlink；递归后这些父仓可能显示子模块指针改动，保留待审阅。
* 整理入口父仓 Git 元数据与来源日志。
* 默认自动提交入口父仓的关联变化，不自动推送。
  * 设置 `AUTO_PARENT_COMMIT=0`：跳过提交；`AUTO_PARENT_PUSH=1`：启用父仓推送。

### <span id="jobs-toc-heading-11" data-jobs-toc="v2">[【MacOS】🧭更新引用Git父仓=>子仓.command](./【MacOS】🧭更新引用Git父仓=%3E子仓.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 修复目录改名、旧路径残留或元数据指向错误，让父仓关联符合当前磁盘布局。

* 扫描父仓第一层实际带 `.git` 的子目录，读取远端和已有登记。
  * 远端缺失、元数据归属不明或属于链接工作树：停止修复。
* 展示磁盘目录、父仓状态与清理计划，确认后备份关联状态。
  * 直接回车：跳过；输入任意字符后回车：执行；`--dry-run`：只预览。
* 按现存目录对齐 `.gitmodules`，保留仍存在条目的 URL、分支及扩展字段。
  * 目录缺失，包括尚未下载：移除旧登记和旧子模块指针，磁盘文件保留。
* 修复可证明失效的工作树指向，暂存各子仓当前提交号，用官方命令归集元数据并补齐父仓本地登记。
* 核对磁盘目录、清单和父仓子模块指针是否一致，输出状态；不拉取代码、不提交、不推送。

### <span id="jobs-toc-heading-12" data-jobs-toc="v2">[【MacOS】🧾更新gitmodules.command](./【MacOS】🧾更新gitmodules.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 将新放入的直属子仓完整纳入父仓子模块管理，保留已有登记与指针。

* 读取已有登记，扫描直属子仓，预检远端、提交、索引和元数据冲突。
  * 有冲突或缺少必要信息：停止，展示问题。
* 生成增量计划，保留已有 URL、分支、扩展字段、子模块指针和暂缺目录登记。
  * `--dry-run` 或 `DRY_RUN=1`：只预览，不执行关联写入。
* 确认计划后备份关联配置和父仓索引。
  * 直接回车：跳过；输入任意字符后回车：执行。
* 补齐 `.gitmodules` 和缺失的子模块指针，初始化本地登记，将元数据归集到父仓。
* 核验父子关系和子仓提交号；仅暂存必要关联，不联网拉取、不提交、不推送。

## 六、<span id="repository-layout-and-entrypoints">本仓目录与脚本入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下为当前检出的源码与维护入口；依赖环境、Git 元数据、构建缓存和生成产物略去，独立子仓仅列目录。

```text
.
├── .gitignore
├── .gitmodules
├── 【MacOS】⏬下载配置当前Git子模块（可向下同步递归）.command
├── 【MacOS】🧩卸载Finder扩展.command
├── 【MacOS】🧩安装Finder扩展.command
├── 【MacOS】🧭更新引用Git父仓=>子仓.command
├── 【MacOS】🧾更新gitmodules.command
├── icon.png
├── JobsGitRemoteCopier/  # 独立 Git 子仓
├── JobsGitRemoteOpener/  # 独立 Git 子仓
├── JobsPathCopier/  # 独立 Git 子仓
├── JobsXcodeOpener/  # 独立 Git 子仓
├── JobsVSCodeOpener/  # 独立 Git 子仓
├── JobsAndroidStudioOpener/  # 独立 Git 子仓
├── JobsTerminalOpener/  # 独立 Git 子仓
├── README.md
├── Scripts/
│   ├── README.md
│   └── SelectFinderExtensionFeatures.applescript
└── work/
    └── README.md
```

* 原有四个扩展工程均为独立 Git 子仓；本仓维护总安装 / 卸载入口、三个 Git 入口及 `Scripts/SelectFinderExtensionFeatures.applescript` 原生选择界面。
  * [JobsGitRemoteCopier](./JobsGitRemoteCopier/README.md)、[JobsGitRemoteOpener](./JobsGitRemoteOpener/README.md)、[JobsPathCopier](./JobsPathCopier/README.md)、[JobsTerminalOpener](./JobsTerminalOpener/README.md)。
* 三个 IDE 工程也通过 Git 子模块独立管理：[JobsXcodeOpener](./JobsXcodeOpener/README.md)、[JobsVSCodeOpener](./JobsVSCodeOpener/README.md)、[JobsAndroidStudioOpener](./JobsAndroidStudioOpener/README.md)。
* [Scripts 目录说明](./Scripts/README.md)：安装器使用的原生功能选择界面及调用约定。
* [work 目录说明](./work/README.md)：本地 DerivedData、生成 App 与扩展的保存位置及 Git 忽略边界。安装器直接从其中注册 App / appex，清理前应先通过对应卸载入口停用、注销，不能把它当作可随手删除的纯缓存；复制 Git 地址扩展使用子仓专用卸载入口。
* 总卸载菜单管理六个宿主，包括三个 IDE 扩展；`JobsGitRemoteCopier/` 的复制 Git 地址扩展使用其子仓卸载脚本。

### <span id="jobs-toc-heading-14" data-jobs-toc="v2">[【MacOS】🧩安装Finder扩展.command](./【MacOS】🧩安装Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 选择并安装本目录的 Finder 右键功能，刷新菜单使其生效。

* 阅读自述并回车，检查系统工具与七个扩展工程。
  * 任一子模块工程缺失：先运行同层子模块下载脚本，复检通过后重新进入安装器；七个工程共用同一流程。
* 在原生复选框窗口勾选功能或全选；Terminal 的五项功能归并为一次工程安装。
  * 取消窗口或未选择项目：退出安装。
* 构建选中的宿主 APP，清理同 Bundle ID 的过期注册，注册并启用对应 Finder 扩展，保存 Terminal 功能选择。
* 对成功安装项刷新 pkd / Finder，汇总结果与日志；失败项在终端显示具体原因。

### <span id="jobs-toc-heading-15" data-jobs-toc="v2">[【MacOS】🧩卸载Finder扩展.command](./【MacOS】🧩卸载Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 批量卸载菜单中选定的 Finder 扩展，并清理相关构建残留。

* 阅读自述并回车，检查 fzf、扩展管理与进程工具。
* 在菜单勾选“打开 Git 远程地址”“复制绝对路径”、三个 IDE 打开入口、“用终端打开”或全选，再回车确认卸载。
  * 取消选择：退出；复制 Git 地址扩展使用其子仓专用卸载入口。
* 停用并注销选中扩展，停止对应宿主与扩展进程，清理构建 APP、运行标记和旧 Automator 服务。
* 保留工程源码，刷新 Services 缓存并重启 Finder，汇总成功项、失败项与日志位置。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
