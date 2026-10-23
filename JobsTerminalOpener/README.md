# `JobsTerminalOpener`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、适用场景](#jobs-toc-heading-2)
- [二、环境先决条件](#jobs-toc-heading-3)
- [三、运行方式](#jobs-toc-heading-4)
  - [3.1、原生 UI 勾选安装](#jobs-toc-heading-5)
  - [3.2、App 内查看和修改功能](#jobs-toc-heading-6)
  - [3.3、Xcode 手动运行](#jobs-toc-heading-7)
- [四、实现边界](#jobs-toc-heading-8)
  - [4.1、直接执行 pod install](#jobs-toc-heading-9)
  - [4.2、代码地图更新与缺失组件安装](#jobs-toc-heading-10)
- [五、排查说明](#jobs-toc-heading-11)
- [六、安装与卸载](#install-uninstall)
  - [【MacOS】安装用终端打开Finder扩展.command](#jobs-toc-heading-13)
  - [【MacOS】卸载用终端打开Finder扩展.command](#jobs-toc-heading-14)
- [七、本仓目录与脚本入口](#repository-layout-and-entrypoints)
  - [EnableFinderExtension.zsh](#jobs-toc-heading-16)
  - [清理构建产物](#jobs-toc-heading-17)
    - [菜单标题与工程识别](#jobs-toc-heading-18)
    - [清理范围](#jobs-toc-heading-19)
    - [为未来工程类型保留的扩展接口](#jobs-toc-heading-20)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

> **本工程提供 5 个 Finder 菜单功能：`用终端打开`｜`Pod Install`｜`清理原生工程构建产物`｜`更新代码地图（.codegraph）`｜`空白 Commit 并 Push`。** Flutter 依赖和清理入口统一由 [JobsFlutterTools](../JobsFlutterTools/README.md) 子菜单提供；宿主保留旧 Flutter 动作标识及配置兼容。

![image-20260628203344107](./assets/image-20260628203344107.png)

`JobsTerminalOpener` 是一个 [**Swift**](https://www.swift.org/) macOS App + Finder Sync Extension 工程。五个现行菜单共用一个扩展，首次安装时可以逐项勾选；App 保留六项配置供旧版本兼容，修改后不需要重新编译。

本工程源码、文档与版本由 [MacOS@Extension](../README.md) 统一管理，工程目录随总仓一起取得，保留独立构建、安装与卸载能力。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 在 Finder 中右键任意一个本地文件或文件夹。
- 点击一级右键菜单里的 `用终端打开`。
- 如果选中项是普通文件夹，会让系统 `Terminal.app` 新开窗口并 `cd` 到该文件夹。
- 如果选中项是文件或包文件，会让系统 `Terminal.app` 新开窗口并 `cd` 到它所在的父目录。
- 当前文件夹同层同时包含普通文件 `Podfile` 和至少一个 `*.xcodeproj` 目录包时，显示 `Pod Install`；点击后直接打开 `Terminal.app`，进入该目录并执行 `pod install`。无需已有 `*.xcworkspace`。
- Flutter 根目录的依赖和清理操作进入 `Flutter开发相关辅助工具`；本扩展不再添加 Flutter 专属顶层项。
- 右键原生工程文件夹时，先识别当前层工程，再显示 `清理iOS/Xcode构建产物`、`清理Android构建产物` 或 `清理鸿蒙构建产物`；Flutter 根目录和未知工程不显示外层清理入口。点击后预览，输入 `CLEAN` 才删除对应产物。
- 右键普通文件夹时，显示 `更新代码地图（.codegraph）`，让 `Terminal.app` 新开窗口，检查 CodeGraph 后更新目标文件夹的地图；缺失组件时，终端等待回车确认后补齐安装链。
- 右键普通文件夹时，显示 `在终端创建空白 Commit 并 Push`；Terminal 会校验 Git、工作树、当前分支、暂存区和推送远程，通过后创建 `chore: empty commit` 空白提交并 Push。
- 依赖操作不会向父目录或子目录递归查找工程；右键位置不是对应工程的标准根目录时，不显示相关入口。
- 当前入口只处理单个选中项；多选时不展示菜单，避免打开结果不明确。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、环境先决条件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 检查项 | 要求 | 说明 |
| --- | --- | --- |
| 系统版本 | macOS `12.0` 及以上 | 工程 `MACOSX_DEPLOYMENT_TARGET` 为 `12.0`，功能依赖 Finder Sync Extension。 |
| 开发工具 | [**Xcode**](https://developer.apple.com/xcode) + `xcodebuild` | 手动运行用 Xcode；根目录批量安装脚本会调用 `xcodebuild` 构建主 App 和扩展。 |
| Finder 扩展 | 系统设置中启用 `用终端打开` | 构建阶段会注册并尝试启用扩展；如果菜单未出现，先确认系统设置里的 Finder 扩展开关。 |
| 终端程序 | 系统 `Terminal.app` | 宿主 App 会请求 Terminal 新开窗口并执行 `cd` 到目标目录；首次使用可能需要允许自动化控制 Terminal。 |
| [**CocoaPods**](https://cocoapods.org/) | 终端环境可执行 `pod install` | 菜单直接使用 Terminal 的现有交互 Shell 环境；工具缺失或安装失败时显示原生错误。 |
| [**Flutter**](https://flutter.dev/) | 终端环境可执行 `flutter` | 只有使用 `flutter pub get` 入口时需要；命令不可用时，Terminal 会直接显示错误。 |
| [**CodeGraph**](https://github.com/colbymchenry/codegraph) | 健康 CLI；需要安装时还检查实际上游依赖 | 健康 CLI 直接复用；缺失时经 [**Homebrew**](https://brew.sh/) 准备 Node/npm，再将官方 npm 包安装到用户独立目录。终端回车确认安装；Homebrew 自身缺失时另选系统或用户目录。 |
| Git 空白推送 | 终端环境可执行 `git` | 当前文件夹必须在 Git 工作树内，当前分支可推送，且暂存区必须为空。 |
| 本地文件目标 | Finder 中只选中一个本地 `file://` 项目 | 多选、网络挂载异常、权限受限目录都可能让菜单不展示或打开失败。 |

建议运行前先做基础自检：

```shell
xcode-select -p
xcodebuild -version
pluginkit -m -p com.apple.FinderSync -A -v | grep JobsTerminalOpener
pod --version
flutter --version
brew --version
node --version
npm --version
codegraph --version
git --version
```

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">3.1、原生 UI 勾选安装 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、双击上级目录的 `../【MacOS】🧩安装Finder扩展.command`。

2、阅读脚本自述并按回车，随后在 macOS 原生复选框窗口中逐项选择右键菜单功能，或点击“全部安装”。

3、`JobsTerminalOpener` 的六项功能会归并为一次工程构建；安装器同时保存这六项的初始选择。

4、需要更换功能组合时，可以重新运行安装脚本，也可以直接在已安装 App 内修改。

### <span id="jobs-toc-heading-6" data-jobs-toc="v2">3.2、App 内查看和修改功能 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、打开 `JobsTerminalOpener` App，窗口中的“可选功能”区域会把六项功能各列一行。

2、复选框会显示当前生效状态；可以逐项勾选，也可以点击“全部选择”或“全部取消”。

3、点击“保存功能选择”。Finder 扩展会在下一次生成右键菜单时读取新配置，关闭当前菜单并重新右键即可生效。

4、项目条件校验仍然有效：例如启用 `pod install` 后，当前目录缺少普通文件 `Podfile` 或 `*.xcodeproj` 目录包时仍不会显示该入口。

### <span id="jobs-toc-heading-7" data-jobs-toc="v2">3.3、Xcode 手动运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、用 [**Xcode**](https://developer.apple.com/xcode) 打开 `JobsTerminalOpener.xcodeproj`。

2、选择 `JobsTerminalOpener` Scheme，直接运行主 App。

3、Xcode 构建阶段会自动注册宿主 App 的 `jobsterminalopener://` URL Scheme，停止旧的宿主 App / Finder Sync 扩展进程，注册并启用 `com.jobs.JobsTerminalOpener.FinderSyncExtension`，成功后会重启 Finder 刷新右键菜单缓存。

4、如果本机还没有保存过功能选择，手动构建默认启用全部六项功能；已有保存记录时继续沿用 App 中的选择。回到 Finder，右键任意文件或文件夹即可使用符合当前目录条件的菜单入口。

5、首次重新安装后，构建阶段可能会等待几十秒，用来等 `pluginkit` 从空状态异步登记到可启用状态。

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">四、实现边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- Finder Sync Extension 可以进入 Finder 右键一级菜单区域，但最终位置由 macOS 决定，不能保证排在系统菜单项前面。
- 六项 Terminal 功能当前共用一个宿主 App 和一个 Finder Sync Extension；安装 UI 与宿主 App 都把它们作为六个独立菜单功能选择。
- `JobsTerminalEnabledFeatures` 提供首次运行的构建默认值；安装器或 App 保存过选择后，Finder 扩展每次生成右键菜单都会优先读取本机配置，因此后续修改不需要重新构建。
- 扩展默认监控 `/`，用于覆盖 Finder 中任意位置的文件和文件夹右键菜单。
- 扩展读取 Finder 传入的本地 `file://` URL 和工程标记文件，以确定菜单资格及工程类型；不执行工程脚本。点击后通过 `jobsterminalopener://open` 把路径和动作类型交给宿主 App 处理。
- Finder 扩展和宿主 App 对 CocoaPods、Flutter 和 CodeGraph 共用目标类型校验；Git 管理状态、暂存区和远程信息则按“所有走终端”的边界，在 Terminal 内执行前现场校验。
- CocoaPods iOS 工程只认当前目录同层的普通文件 `Podfile` 和 `*.xcodeproj` 目录包；不递归补齐，不要求已有 `*.xcworkspace`。Flutter 工程只认当前目录直接存在的 `pubspec.yaml`、`lib/` 和清单中的 `sdk: flutter` 声明。
- CodeGraph 入口只对普通文件夹显示并执行；文件、Finder 包文件和其它非目录目标不显示入口，宿主 App 执行前也会再次拒绝。
- 空白 Commit 入口同样只对普通文件夹显示。是否由 Git 管理不在 Finder 进程中预判；点击后由 Terminal 运行 `git rev-parse --is-inside-work-tree` 校验当前文件夹，非 Git 目录只输出错误并停止。
- 宿主 App 计算目标目录后，通过 `/usr/bin/osascript` 请求 `Terminal.app` 新开窗口；普通入口执行 `cd 目标目录`，Pod 入口直接发送单行 `cd -- <安全引用的目标路径> && pod install`，Flutter 依赖入口执行 `cd 目标目录 && flutter pub get`。
- 空白 Commit 入口会先确认 Git 命令健康、当前目录在工作树内、当前处于正常分支、暂存区为空，并能确定上游或唯一推送远程。然后执行 `git commit --allow-empty -m 'chore: empty commit'` 和 `git push`；无上游时优先使用 `origin`，否则只在存在唯一远程时为当前分支建立上游。Push 失败时空白 Commit 保留在本地，Terminal 会打印提交哈希。
- CodeGraph 入口复用健康 CLI；缺失或损坏时，经用户回车确认，沿 `CodeGraph → npm/Node.js → Homebrew → bash/curl/Command Line Tools` 检查实际安装依赖。Node/npm 不可用时通过 Homebrew 安装或修复 `node@24`；Homebrew 缺失时先强提示选路径：精确输入 `YES` 运行官方系统安装器，其它输入或回车选择用户目录。安装和修复各只尝试一次，复检仍失败立即停止。
- 当前目录已有 `.codegraph/` 时执行 `codegraph sync`，首次执行 `codegraph init --yes`，并用 `codegraph status --json` 验证项目路径、输出路径和索引完成状态；具体范围、确认和日志见下方“代码地图更新与缺失组件安装”。
- 代码地图和空白 Commit 的多行脚本使用每次独立的私有 `.zsh` 载体，Terminal 只接收一条短启动命令，避免源码逐行回显为 `quote>`。载体在脚本结束时清理，不生成自动关闭窗口的 `.command ; exit;`；Pod 入口直接发送单行命令。
- 新窗口由 `Terminal.app` 自己创建并加载用户终端配置。普通“用终端打开”和 `pod install` 会进入目标目录；代码地图和空白 Commit 命令在各自子进程内以目标目录工作，结束后不改父交互 Shell 的目录。
- 不复用正在执行任务的既有 Terminal 窗口；每次点击都会由 Terminal 新开一个窗口执行 `cd`。
- 宿主 App 通过 URL Scheme 被 Finder 扩展唤起时只处理打开目录请求，不再展示主窗口。
- Finder Sync Extension 保留 App Sandbox；本机自用版通过 `com.apple.security.temporary-exception.files.absolute-path.read-only` 给 `/` 增加只读例外。
- 菜单入口只在 Finder 选中单个本地项目时出现。

### <span id="jobs-toc-heading-9" data-jobs-toc="v2">4.1、直接执行 `pod install` <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

菜单和功能复选框统一显示 `Pod Install`，总安装面板中与 `Pod Update` 相邻。保留 URL 动作 `pod-install` 与功能配置 ID `pod_install`，实际终端命令仍为 `pod install`，已有勾选记录继续有效。

Finder 和宿主 App 只校验目标同层同时存在普通文件 `Podfile` 与至少一个 `*.xcodeproj` 目录包。点击后，在 Terminal 的交互 Shell 中直接执行一条命令；实际目标路径由宿主安全引用：

```shell
cd -- '/path/to/iOS project' && pod install
```

入口只负责发送命令，后续选源、输入提示、安装结果和错误均由 `pod` / `Podfile` 原生处理，使用 Terminal 现有环境；已有 Gem 环境也由终端本身处理。需要中止时按 `Ctrl+C`。

传输回归编译真实 Swift 实现，使用注入调度器和交互 zsh 伪终端，验证 Pod 直接发送单行命令、特殊路径与原生交互；代码地图及空白 Commit 继续验证私有载体权限、调度失败与受控中断清理。不会打开真实 Terminal 或执行真实 Pod 操作：

```shell
ruby ./Tests/TerminalRequestTransportTests.rb
```

`./Tests/DependencyProjectValidatorTests.swift` 与共享验证器一起编译，可独立核对 `Podfile` 普通文件与 `*.xcodeproj` 目录包两个条件的存在组合、大小写、类型和同层限制，以及不要求已有 workspace：

```shell
swiftc \
  ./JobsTerminalShared/DependencyProjectValidator.swift \
  ./Tests/DependencyProjectValidatorTests.swift \
  -o "${TMPDIR:-/tmp/}JobsTerminalProjectValidatorTests"
"${TMPDIR:-/tmp/}JobsTerminalProjectValidatorTests"
```

### <span id="jobs-toc-heading-10" data-jobs-toc="v2">4.2、代码地图更新与缺失组件安装 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

菜单与功能开关仍各占一项，保留已有 `codegraph-bootstrap` 标识。点击后在新 Terminal 窗口展示目标和影响范围，回车继续；需要安装时再明确提示“回车确认安装，输入其它内容取消”。

| 当前状态 | 执行动作 |
| --- | --- |
| CodeGraph 健康且目标有有效地图 | 输出完整工具链体检，再对该目标执行 `sync` 并核对 JSON 状态。 |
| CodeGraph 健康且目标没有地图 | 输出完整工具链体检，再执行 `init --yes`，创建其自身 `.codegraph`。 |
| CLI 缺失或损坏 | 用户确认后检查安装链，复用健康组件、修复缺失组件，再次验证 CLI 后才更新地图。 |
| 依赖修复失败、地图属于其它目标或索引未完成 | 停止并给出失败命令与日志，保留现有文件。 |

- 官方现有安装说明提供 standalone / npm，尚无可确认的官方 Homebrew formula；[官方仓库](https://github.com/colbymchenry/codegraph) 和 [Homebrew 支持提案](https://github.com/colbymchenry/codegraph/issues/689) 可核对。因此实际通道为 Homebrew 管理 Node/npm，再由 npm 安装 `@colbymchenry/codegraph@latest`，并在执行前显示来源。
- npm 包安装到当前用户的独立 `jobs-codegraph` 前缀，沿用本机独立安装器的目录约定。只为本次子进程刷新 PATH，不修改 Shell 启动配置；已有健康 CodeGraph、Node/npm 和 Homebrew 直接复用。
- 每次运行均检查 zsh、SQLite、plutil JSON 解析、CodeGraph 版本与所需子命令，以及 bash、curl、Git、Command Line Tools、Homebrew 版本 / 前缀 / 配置 / doctor、Node 实际执行 JavaScript 和 npm 版本 / 前缀 / 全局目录。每层在终端显示健康或异常，命令输出写入本次日志；即使 CLI 已健康，也不跳过安装上游的只读体检。
- 健康独立 CLI 不依赖额外安装上游时，缺失或损坏的上游只报告警告，不强制安装。需要安装 CodeGraph 时，实际上游必须通过检查：系统工具异常就停止，Node/npm 不兼容就经 Homebrew 修复一次，npm Registry 先 `ping` 再安装。Node 兼容范围按官方 `1.6.2` 的 `>=20 <25` 校验，避免把 Node 25/26 判为兼容后才安装失败；修复使用 `node@24`。Homebrew doctor 的无关公式警告会保留诊断，是否可安装仍以实际依赖命令结果判断。
- macOS 与平行 Windows 扩展使用各自系统原生工具链。[Homebrew 官方支持 Windows 的范围是 WSL](https://docs.brew.sh/Installation#linux-or-windows-10-subsystem-for-linux)；Windows 资源管理器入口不会调用 WSL 的 brew 去安装原生 CLI，具体见 [Windows CodeGraph 包说明](../../WindowsOS@Extension/JobsCodeGraphUpdater/README.md)。
- 项目路径作为参数传给内置 zsh 命令，兼容中文、空格及引号；将输出位置固定为目标自身 `.codegraph`，拒绝地图目录及直属条目的符号链接。系统 SQLite 以只读模式前检数据库结构，禁用用户 `.sqliterc`，防止异常地图触发 CLI 回退到上级项目；同步前核对项目身份，同步后核对完整索引状态。
- 本入口仅调用地图相关的 `init` / `sync` / `status`，关闭遥测和 shim 自动下载，避开会自动安装 Git hooks 的禁监听分支；不调用 `install`、`watch` 或 `serve`。
- 日志位于系统临时目录中的 `JobsTerminalOpener-CodeGraph.*`。命令输出与日志同步，安装、地图命令和日志写入失败均返回非零状态。

隔离回归从 Swift 中提取真实命令，用伪终端和临时假工具检查确认、安装链、特殊路径、失败停止及地图状态；不会执行真实安装或给用户项目建图：

```shell
ruby ./Tests/CodeGraphDependencyCommandTests.rb
```

## <span id="jobs-toc-heading-11" data-jobs-toc="v2">五、排查说明 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 右键菜单未出现：
  - 确认 `JobsTerminalFinderSync.entitlements` 保留了 `com.apple.security.app-sandbox`；Finder Sync Extension 去掉 sandbox 后可能无法被 `pluginkit` 登记出来。
  - 确认系统设置中 Finder 扩展已经启用，或点击 App 内的 `重新启用扩展`。
  - 重新打开 Finder 窗口。
  - 重新编译后构建阶段会重新启用扩展，并自动重启 Finder。
  - 也可以执行下面命令确认扩展已启用，输出行前面有 `+` 表示启用：

    ```shell
    pluginkit -m -p com.apple.FinderSync -A -v | grep JobsTerminalOpener
    ```

  - 如果已经注册但没有 `+`，执行下面命令启用：

    ```shell
    pluginkit -e use -i com.jobs.JobsTerminalOpener.FinderSyncExtension
    ```

- 点击后没有打开 Terminal：
  - `pod install` 入口要求同层同时存在普通文件 `Podfile` 与 `*.xcodeproj` 目录包；缺任一项时不会打开 Terminal。
  - 确认 Finder 中只选中了一个本地文件或文件夹。
  - 确认系统存在 `Terminal.app`。
  - 确认 `JobsTerminalFinderSync.entitlements` 里有 `com.apple.security.temporary-exception.files.absolute-path.read-only`，并包含 `/`。
  - 修改 entitlements 后必须重新运行 `JobsTerminalOpener.xcodeproj` 主 App，让扩展重新签名、注册并启用。
  - 确认菜单来自 `JobsTerminalOpener`，不是旧服务或其它同名工具。
  - 如果扩展日志里没有 `request terminal open via`，说明当前点击没有进入新版扩展；重新构建并确认 `pluginkit` 指向最新 `JobsTerminalFinderSync.appex`。
  - 如果扩展日志里已经有 `delegate terminal open request accepted`，但 `/tmp/JobsTerminalOpener.log` 没有 `application open urls=`，说明 URL Scheme 没有被当前宿主 App 接管；重新运行主 App 或重新构建。
  - 如果系统临时目录中的 `JobsTerminalOpener.log` 已经出现 `terminal command exit=0`，但新窗口停在错误目录，优先确认正在运行的是新版构建，并检查 Finder 选中项是否为目标文件或文件夹。
  - 如果新窗口仍显示临时 `.command ; exit;`，说明 Finder 仍在调用旧版构建产物；重新构建、注册并重启 Finder。
  - 重新点击 App 内的 `重新启用扩展`，再重启 Finder。

- 新窗口出现大量 `quote>`：
  - 这是交互 zsh 解析多行引号时的续行提示。新版 Pod 直接发送单行 `cd -- <安全引用的目标路径> && pod install`；代码地图和空白 Commit 发送单行启动命令，由子进程读取私有 `.zsh` 文件。
  - 更新已经安装的 `JobsTerminalOpener` 构建后重新右键启动；代码地图和空白 Commit 的载体会在结束、失败或受控中断时清理，终端窗口保留。

- 依赖操作没有出现在右键菜单：
  - 先打开 `JobsTerminalOpener` App，确认对应功能已勾选并点击“保存功能选择”；也可以重新运行上级安装脚本改变初始组合。
  - `pod install`：确认右键的当前文件夹同层同时包含普通文件 `Podfile` 和至少一个 `*.xcodeproj` 目录包；点击后直接在 Terminal 执行安装。
  - `flutter pub get`：确认右键的当前文件夹直接包含 `pubspec.yaml`、`lib/`，并且 `pubspec.yaml` 中存在有效的 `sdk: flutter` 声明。
  - Finder 菜单打开后才补齐文件不会实时刷新当前菜单；关闭菜单后重新右键。

- CodeGraph 操作没有出现在右键菜单：
  - 确认右键目标是普通文件夹，不是文件、`*.xcodeproj` 等 Finder 包文件或多选目标。
  - 首次缺失 CLI 时会先等待回车确认安装，再检查并补齐所需 Node/npm 和 Homebrew；如果新装 Homebrew，还会询问安装路径，精确输入 `YES` 选择系统目录，其它输入或回车选择用户目录。
  - `/bin/bash` 或系统 `curl` 属于自动引导的最上游条件；它们不可用时，Terminal 会打印具体错误并停止，不会继续初始化项目。
  - 查看 `JobsTerminalOpener-CodeGraph.*` 日志。安装失败或修复后仍不健康时停止地图操作；已有健康工具直接使用，菜单不主动执行全局升级。

- `pod install` 失败或等待输入：
  - 查看 Terminal 中 `pod` / `Podfile` 的原生提示，按目标项目要求处理环境、来源或网络问题；需要中止时按 `Ctrl+C`。
  - 如果仍出现旧版确认、升级或自检界面，重新构建并安装 `JobsTerminalOpener`，再重新右键启动；已打开的旧终端任务不会自动更新。

- 空白 Commit 并 Push 失败：
  - 确认右键目标是普通文件夹，且当前文件夹位于 Git 工作树内。
  - 暂存区有内容时会主动停止，避免把文件变更带入空白 Commit；先处理或取消暂存内容后再执行。
  - detached HEAD、无上游且远程不唯一、Git 用户信息未配置或网络鉴权失败都会保留明确的 Terminal 输出。
  - Commit 已创建但 Push 失败时，不自动回滚本地历史；根据 Terminal 打印的哈希修复远程或鉴权后重新 Push。

- 查看扩展调试日志：

  ```shell
  log stream --predicate 'process == "JobsTerminalFinderSync"' --style compact
  ```

  ```shell
  tail -n 200 "$HOME/Library/Containers/com.jobs.JobsTerminalOpener.FinderSyncExtension/Data/Library/Application Support/JobsTerminalFinderSync/FinderSync.log"
  ```

  ```shell
  tail -n 200 "/tmp/JobsTerminalOpener.log"
  ```

  扩展日志重点看 `action=`、`request terminal open via` 和 `delegate terminal open request accepted`；宿主 App 日志重点看 `application open urls=`、`terminal action=`、`terminal command exit=` 和 `terminal activate attempt=`。

## 六、<span id="install-uninstall">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

两个入口都是工程根目录下裸露的双击脚本，独立于总仓安装器；本工程可单独拷走安装，不依赖其它工程源码。

### <span id="jobs-toc-heading-13" data-jobs-toc="v2">[【MacOS】安装用终端打开Finder扩展.command](./【MacOS】安装用终端打开Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 独立构建、注册并启用本工程的“用终端打开”等六项功能Finder 扩展。

- 先决条件是完整 [**Xcode**](https://developer.apple.com/xcode)：脚本体检 `xcodebuild`、macOS SDK、`pluginkit` 等系统命令与工具链健康，缺失时明确停止，不自动改 `xcode-select`。
- 直接回车安装，输入任意字符（包括空格）后回车跳过；构建产物固定在 `./work/DerivedData/Build/Products/Debug/`，注册后打开宿主 App 并重启 Finder。
- 六项功能的勾选默认值由宿主 App 提供，可在其主窗口调整后即时生效。日志为系统临时目录中的 `JobsTerminalOpenerInstall.log`。

### <span id="jobs-toc-heading-14" data-jobs-toc="v2">[【MacOS】卸载用终端打开Finder扩展.command](./【MacOS】卸载用终端打开Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 卸载 JobsTerminalOpener 的 Finder 扩展，移除对应右键菜单入口并保留工程源码。

- 阅读自述并回车，检查系统工具，显示当前扩展注册状态与待处理路径。
- 停用扩展，停止宿主 APP 和扩展进程，再注销相应 Finder Sync 注册；必须输入 `YES` 才继续。
- 清理对应构建 APP、运行标记、旧日志及 Automator 服务残留；源码目录保留，结束时重启 Finder。
- 日志为系统临时目录中的 `【MacOS】卸载用终端打开Finder扩展.command.log`。

## 七、<span id="repository-layout-and-entrypoints">本仓目录与脚本入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下为本工程源码与维护入口；依赖环境、Git 元数据、构建缓存和生成产物略去。

```text
.
├── 【MacOS】安装用终端打开Finder扩展.command
├── 【MacOS】卸载用终端打开Finder扩展.command
├── assets/
├── icon.png
├── JobsTerminalFinderSync/
│   ├── FinderSync.swift
│   ├── Info.plist
│   ├── JobsTerminalFinderSync.entitlements
│   └── TerminalOpener.swift
├── JobsTerminalOpener/
│   ├── AppDelegate.swift
│   ├── Info.plist
│   ├── JobsTerminalOpener.entitlements
│   ├── main.swift
│   └── MainViewController.swift
├── JobsTerminalOpener.xcodeproj/
├── JobsTerminalShared/
│   ├── DependencyProjectValidator.swift
│   └── FinderMenuFeatureConfiguration.swift
├── README.md
├── Tests/
│   ├── DependencyProjectValidatorTests.swift
│   ├── CodeGraphDependencyCommandTests.rb
│   ├── TerminalRequestTransportFixture.swift
│   └── TerminalRequestTransportTests.rb
└── Scripts/
    └── EnableFinderExtension.zsh
```

* `JobsTerminalOpener/` 保存宿主 APP；`JobsTerminalFinderSync/` 保存 Finder 扩展与菜单逻辑；`JobsTerminalOpener.xcodeproj/` 保存工程和构建阶段配置。
* `JobsTerminalShared/` 保存六项功能选择与依赖项目识别的共享实现。
* `Scripts/` 保存构建后自动注册入口；工程根的裸露双击脚本提供独立安装与卸载入口。

### <span id="jobs-toc-heading-16" data-jobs-toc="v2">[EnableFinderExtension.zsh](./Scripts/EnableFinderExtension.zsh)</span><!-- jobs-toc:heading-end -->

> **目的：** 在 Xcode 构建后注册、启用 JobsTerminalOpener 扩展并刷新 Finder。

* 由 Xcode Build Phase 传入构建目录和 APP 名称后自动调用，日志写入系统临时目录。
  * 外层安装器设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1`：跳过，由外层统一处理。
* 读取扩展状态并停止旧宿主进程，定位本次构建 APP 内的扩展。
  * 扩展目录缺失：保留刷新标记，交给后续 APP 启动处理。
* 注册并请求启用扩展，轮询系统状态；成功后重启 Finder 并清理标记。
  * 未确认启用：保留标记和日志；该构建阶段入口最终返回成功，不把它视作菜单已生效的证明。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

<a id="build-artifacts"></a>
### <span id="jobs-toc-heading-17" data-jobs-toc="v2">清理构建产物</span><!-- jobs-toc:heading-end -->

总安装器中勾选“清理构建产物（按工程类型显示）”；已安装用户需重新构建 / 安装本工程，再在宿主中启用该功能。沿用 `clean_build_artifacts` 安装标识与 `clean-build-artifacts` 功能 / URL 动作标识，不改动已有勾选记录。Finder 仅在选中单个、已识别的原生工程文件夹时显示对应标题；Flutter 根目录、未知目录、文件、目录包、多选及空白处都不显示清理入口。Flutter 使用 `Flutter开发相关辅助工具 → Flutter清理维护工具 → 清理当前项目构建产物`，无需 Flutter/FVM 即可按原白名单清理。安装和菜单识别本身不会清理工程。

#### <span id="jobs-toc-heading-18" data-jobs-toc="v2">菜单标题与工程识别</span><!-- jobs-toc:heading-end -->

Finder 与宿主使用共享的 `buildArtifactProjectKind(at:)` 识别，终端脚本执行时再次检测。只以所选目录为根，不向父目录借用工程标记，也不会把包含多个项目的普通父目录当成批量清理入口。识别优先级为 **Flutter → 鸿蒙 → Android → iOS/Xcode**；Finder 遇到 Flutter 类型即隐藏通用清理，不回退到原生类型：

| Finder 标题 | 当前目录的识别依据 |
| --- | --- |
| 隐藏外层清理，转入 Flutter 子菜单 | 当前层普通 `pubspec.yaml` 的 `dependencies.flutter.sdk` 声明 Flutter；支持常见块映射、单行 flow 与引号，不要求已经创建 `lib/`。即使同层存在原生工程标记，也由 Flutter 子菜单负责整个工程的已识别平台产物。 |
| `清理鸿蒙构建产物` | Hvigor 工程或模块：同时有 `hvigorfile.ts` / `hvigorfile.js`、`build-profile.json5`、`oh-package.json5`，以及 `AppScope/app.json5` 或 `src/main/module.json5`。覆盖鸿蒙原生工程，以及单独选中的 Flutter `ohos/` 平台工程。仅文件夹名叫 `ohos` 不算识别成功。 |
| `清理Android构建产物` | 当前层有 Gradle 构建或 settings 文件，且本构建内有 Android 插件声明或带 Gradle 配置的模块 `src/main/AndroidManifest.xml`。 |
| `清理iOS/Xcode构建产物` | 同层 `*.xcodeproj/project.pbxproj` 中有 iOS SDK、iOS 部署目标或 iPhone 平台配置。当前仅支持 iOS Xcode 工程，不代表所有 Xcode 平台。 |

#### <span id="jobs-toc-heading-19" data-jobs-toc="v2">清理范围</span><!-- jobs-toc:heading-end -->

| 工程 | 清理白名单 |
| --- | --- |
| Flutter | `build/`（包含 `build/ohos/`）、`.dart_tool/`；经单独识别的 `android/`、`ios/`、`ohos/` 平台构建产物；桌面平台 Flutter ephemeral 目录。 |
| 鸿蒙 | 当前根目录 `build/`、`.hvigor/`；本工程内同时有 `build-profile.json5` 和 `src/main/module.json5` 的模块，其 `build/`、`.hvigor/`。包括默认构建目录内的 HAP / APP / HAR 等产物，不按扩展名扫描删除其它位置的包。 |
| Android | 当前 Gradle 根目录 `build/`、`.gradle/`、`.kotlin/`；本构建内有 Gradle 配置的模块 `build/`、`.cxx/`、`.externalNativeBuild/`。 |
| iOS/Xcode | 当前工程 `build/`、`DerivedData/`；Xcode 默认 DerivedData 中，只有 `info.plist` 的 `WorkspacePath` 精确指向当前层工程 / 工作区的 `Build/` 才会清理；Flutter iOS 还清理 `Flutter/ephemeral/`。 |

选中 Flutter 根目录时，统一子菜单的 `清理当前项目构建产物` 包含已识别的鸿蒙平台产物；只选中 `ohos/` 时，`清理鸿蒙构建产物` 的范围限于该目录，不向上删除 Flutter 根目录的 `build/`、`.dart_tool/`。若要完整清理 Flutter 鸿蒙构建结果，应选中 Flutter 根目录。

执行前列出识别类型、工程路径和实际存在的产物，输入 `CLEAN` 才删除；其它输入取消。请先停止构建。保留源码、锁文件、Pods、`oh_modules`、`node_modules`、`entry/libs/flutter.har` 等依赖包、Gradle / Hvigor 工具配置、FVM SDK、签名、其它工程的 DerivedData 和全局共享缓存。自定义输出路径不推断、不删除；扫描模块时不进入依赖目录及嵌套独立 Gradle / Git / Flutter / 鸿蒙应用工程。清理目标或父路径是链接时停止，产物内部的符号链接只移除链接本身。

可单独运行 `zsh Scripts/CleanBuildArtifacts.zsh /工程路径 --detect` 获取工程类型（未知类型返回非零退出码）；`--dry-run` 只预览；省略选项进入确认；`--yes` 供明确授权的无人值守调用。无需安装 Flutter / Gradle / CocoaPods / DevEco Studio，不执行项目提供的脚本。

鸿蒙工程标记参考华为的[工程级 build-profile.json5](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-hmos-hvigor-build-profile-app)，构建命令与目录边界参考 [Hvigor 命令行](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-commandline)。本功能使用保守目录白名单，不调用 Hvigor。

#### <span id="jobs-toc-heading-20" data-jobs-toc="v2">为未来工程类型保留的扩展接口</span><!-- jobs-toc:heading-end -->

当前只支持上面四类；普通 Dart、Java Gradle、纯 macOS Xcode、旧式鸿蒙 Gradle 或无法识别的目录均不显示入口，也不做通用 `build/` 删除。新增工程支持应按以下接口接入，不能只新增一个菜单标题：

1. 在 `JobsTerminalShared/DependencyProjectValidator.swift` 的 `BuildArtifactProjectKind` 增加类型和 `menuTitle`，在 `buildArtifactProjectKind(at:)` 增加只读识别规则，明确当前层标记和识别优先级。该接口返回 `nil` 即隐藏入口，同时让宿主拒绝执行。
2. 在 `Scripts/CleanBuildArtifacts.zsh` 增加对应 `jobs_clean_<类型>` 检测与候选目录收集函数，接入 `jobs_clean_main` 的类型分支和删除前复检。候选路径统一进入 `candidates`，继续使用 `jobs_clean_validate`、预览和 `CLEAN` 确认；禁止未知类型兜底和猜测全局缓存归属。`--detect` 返回值必须与 Swift 类型的 `rawValue` 一致。
3. 补充菜单标题、检测一致性、清理范围、依赖保留、嵌套工程和符号链接测试，再更新此处识别依据及白名单。若新增 Flutter 平台，还需说明“Flutter 根目录整体清理”和“平台目录单独清理”的区别。

回归：`ruby Tests/BuildArtifactCleanerTests.rb`（包含真实 Swift 检测器与脚本的一致性检查）、`ruby Tests/TerminalRequestTransportTests.rb`，以及仓库根目录的 `ruby Tests/DesktopFinderMenuTests.rb`。测试只操作临时夹具，覆盖三类原生工程标题、Flutter 根目录隐藏外层清理、鸿蒙原生 / Flutter 鸿蒙、多模块、类型优先级、未知工程隐藏、iOS 归属、取消、特殊路径、链接保护和重复执行。清理脚本仍支持四类工程，Flutter 副本打包到统一工具内。
