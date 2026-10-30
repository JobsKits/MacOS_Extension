# `JobsProjectTools`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能与显示条件](#jobs-toc-heading-2)
- [二、安装与逐项启停](#jobs-toc-heading-3)
- [三、实现与验证](#jobs-toc-heading-4)
- [四、输入、状态与副作用](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

一个 [**Finder Sync**](https://developer.apple.com/documentation/findersync) 扩展按固定顺序提供三个 IDE 一级入口和“Git操作”一级子菜单。九项可独立启停；[**Git**](https://git-scm.com/) 的六项功能集中在同一个子菜单中。“用 [**Sourcetree**](https://www.sourcetreeapp.com/) 打开”已移除，已有配置也不会显示此入口。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、功能与显示条件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 顺序 | 操作 | 显示规则 |
| --- | --- | --- |
| 1 | 🧭 用 Android Studio 打开项目 | 非空的 Android 原生、Flutter 官方或 Flutter 鸿蒙项目根目录 |
| 2 | 📝 用 VSCode 打开项目 | 非空、非 iOS 项目的普通文件夹；普通非 iOS 目录、macOS 工程和纯 Swift Package 可用 |
| 3 | 🛠️ 用 Xcode 打开项目 | 非空的 iOS 工程目录或有效 iOS `.xcodeproj` / `.xcworkspace` 工程包 |
| 4 | Git操作 → 拉取 Git 到最新 | 有效 Git 工作树内的普通文件夹，沿用原拉取脚本的复核和交互流程 |
| 5 | Git操作 → Git 提交回退 | 同上；独立 Terminal 中选择远端快照 soft、历史 soft 或历史 hard，hard 必须精确输入 `YES` |
| 6 | Git操作 → 打开 Git 远程地址 | 同上；点击后解析所属仓库并在默认浏览器打开远程网页 |
| 7 | Git操作 → 复制 Git 远程地址 | 同上；复制选定 remote 的原始地址 |
| 8 | Git操作 → 配置 Git 动态代理 | 同上；在 Terminal 安装、只读检查或恢复用户级动态 Git 入口 |
| 9 | Git操作 → 在终端创建空白 Commit 并 Push | 同上；Terminal 再检查分支、暂存区及远程后创建空白提交并推送 |

所有 IDE 入口先验证所选对象是可读取的非空目录；仅含 `.DS_Store`、`Thumbs.db`、`desktop.ini` 时视为空，其余隐藏项（包括 `.git`）仍算内容。普通文件、符号链接、多选、失效路径和不支持的目录包不显示；不把普通文件或无效工程包归一到父目录。菜单生成、点击及宿主派发前共用同一规则，目录被清空或项目类型改变时停止打开，也不先查询 IDE 安装或进入下载页。

Android 原生根目录要求本层存在 `settings.gradle` 或 `settings.gradle.kts`，并在本层 / `app/` 的构建脚本中有 Android 插件声明，或存在本层 / `src/main/` / `app/src/main/` 的 `AndroidManifest.xml`；普通 Gradle 项目不满足。Flutter 官方和 Flutter 鸿蒙根目录均以 `pubspec.yaml` 的有效 `dependencies.flutter.sdk: flutter` 声明识别，并优先于本层原生工程。只检查当前层与明确的 Android 标准路径，不递归向上或向下寻找项目。

iOS 资格要求本层 `.xcodeproj/project.pbxproj` 明确配置 `SDKROOT = iphoneos / iphonesimulator`，或 `SUPPORTED_PLATFORMS` 含 iPhone 平台；`.xcworkspace` 必须通过明确的本地工程引用指向这类项目。纯 macOS 工程、仅有 `Package.swift` 或 `Podfile` 不自动当作 iOS 项目。Flutter 根目录即使包含 `ios/` 子工程仍保留 Android Studio / VSCode；单独进入 `ios/` 才按本层工程判断。

读取 Xcode 元数据时单文件上限为 1 MiB；已存在但不可读、编码 / XML 损坏、超过上限或明确的工程引用无法解析时，按未知类型处理，隐藏 VSCode / Android Studio 项目入口，不把读取失败当作非 iOS。可正常读取的 macOS 工程、SDK 宏以及纯 Swift Package 不因此禁用 VSCode。

Git 子菜单只接受有效 Git 工作树内的普通文件夹及其内部空白处，支持仓库根、子目录、子模块和 worktree；原 Git 身份校验与操作确认保持不变。旧 `git-sourcetree` 配置保留为兼容标识，但菜单和宿主派发均拒绝此动作；不影响其它六项 Git 功能。

识别回归位于 `./Tests/IDEProjectDetectionTests.swift`，菜单 / 点击回归位于 `./Tests/MenuTests.py`；使用临时目录和打开器替身，不启动真实 IDE。

Finder 只控制本扩展内的顺序；整组相对其他扩展的位置由系统决定。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与逐项启停 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

菜单安装与卸载统一使用 [图形管理入口](./【MacOS】管理项目工具Finder扩展.app)。直接打开面板，选择“安装 / 更新”或“卸载”并勾选当前范围内的功能；默认空选，点击操作按钮即确认。每项显示等待、正在安装 / 卸载、成功或失败；底部日志实时滚动，可选择复制或复制全部。运行中锁定选择和关闭入口，结束后保留结果与日志。首次打开或面板源码更新后会在后台编译，失败以桌面提示和启动日志说明。

原同名 `.command` 入口保留，终端只负责唤起独立 GUI，随后结束启动脚本；本次启动任务结束后自动关闭对应终端页，安装 / 卸载、进度与实时日志均由 GUI 后台处理。已有交互 Shell 中手工调用时保留原工作会话。内部实现为 `Scripts/ManageExtension.zsh`；完整仓内单功能入口使用总面板的受限范围。可独立复制的包须整体保留 `.command`、`.app`、Scripts、工程源码和资源。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

每项失败后，点击红色带下划线的“失败，见日志”，会新建 Terminal 会话并用 `cat` 显示本次完整会话日志；现有任务继续，已有终端保留。“日志文件”按钮仍用于在 Finder 中定位原始日志。

保留完整仓库，双击 [管理入口（安装模式）](./【MacOS】管理项目工具Finder扩展.command)，或在根管理器中勾选需要的 IDE / Git 功能。IDE、Git 拉取 / 提交回退、远程地址及动态代理的原单项安装入口也转到此包，并且只增加所选功能。

首次安装读取已经启用的旧 IDE / Git 功能，以及 Terminal 中的空白提交选择，以及已经启用的旧独立提交回退菜单，将它们连同本次选择保存到当前用户 Application Support 下的 `JobsProjectTools/EnabledFeatures.txt`。统一扩展成功启用后，停止对应旧宿主、停用旧独立扩展并刷新 Finder。构建或注册失败不会先关闭旧菜单。以后重新安装会合并功能，保留其他选择；动态代理不再从系统桌面空白处单独显示。

宿主和 Finder 扩展都通过系统账户信息取得真实 Home，读取上述同一份配置；Finder 沙盒的 Home 别名不改变配置位置。配置缺失、空白或不可读时保持全部关闭，不创建容器副本或自动启用功能；读取失败的系统诊断只记录配置路径和错误。

打开 [图形管理入口](./【MacOS】管理项目工具Finder扩展.app)，选择卸载并勾选需要关闭的项；各单功能管理入口及总面板仅关闭所选项。最后一项关闭时注销统一扩展，保留空配置以免下次恢复全部功能。源码和构建缓存保留；关闭代理菜单不撤回业务脚本安装的 Git 配置。

构建输出位于 `work/DerivedData`。普通 [**Xcode**](https://developer.apple.com/xcode/) Build 不运行自动启用脚本；使用安装入口完成注册和功能状态合并。旧独立工程仅保留作实现参考和回归验证，不应再直接构建、运行其宿主来重新启用旧菜单。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、实现与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- `Shared/ProjectMenuAction.swift`：稳定顺序、显示条件、功能配置、URL 请求编解码。
- `Shared/SourcetreeApplication.swift`：保留的历史安装检测实现，仅供兼容回归。
- `JobsProjectTools/SourcetreeProjectOpener.swift`：保留的历史打开实现；当前菜单与宿主门禁不再派发。
- `JobsProjectTools/main.swift`：纯代码宿主显式挂接并强持有 `AppDelegate`，在进入应用主循环前建立启动委托；冷启动和已运行时均由同一 URL 回调接收 Finder 请求。
- `JobsProjectToolsFinderSync/FinderSync.swift`：IDE 一级入口、Git 子菜单和独立 selector；点击时复核上下文。
- `JobsProjectTools/AppDelegate.swift`：宿主再次校验功能与项目条件，执行 IDE、Git 和剪贴板操作。
- Xcode 工程直接引用既有项目检测器、Git 远程解析器、Git 拉取 / 提交回退 / 动态代理 launcher 和 Terminal 动作实现；业务脚本随统一 App 打包，安装后不读取源码目录。
- [Scripts/ManageProjectTools.zsh](./Scripts/README.md)：统一构建、注册、保存功能状态和逐项关闭。

```sh
python3 ./Tests/ConfigurationTests.py
python3 ./Tests/MenuTests.py
python3 ./Tests/HostDispatchTests.py
python3 ./Tests/HostBootstrapTests.py
python3 ./Tests/SourcetreeBehaviorTests.py
python3 ./Tests/InstallerTests.py
xcodebuild \
  -project ./JobsProjectTools.xcodeproj \
  -scheme JobsProjectTools \
  -configuration Debug \
  -derivedDataPath ./work/DerivedData \
  build
```

菜单回归使用真实 NSMenu / selector、临时项目和替身 Finder / 工作区，不实际打开 IDE、拉取仓库或写入系统剪贴板。安装回归模拟系统注册，覆盖旧功能迁移、部分安装 / 卸载、重新启用及失败保留。

宿主启动回归单独验证生产 `main.swift` 的委托挂接与强持有，补齐直接构造 `AppDelegate` 的派发测试无法覆盖的启动链路；真实 Finder 菜单仍须在更新扩展后单独验收。

配置回归调用生产路径计算与读取实现，分别准备真实 Home 和沙盒 Home 下的不同配置，验证外部选择保持、容器副本缺失、缺失 / 空白 / 非 UTF-8 配置，以及未知标识和重复项；不修改当前用户配置。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、输入、状态与副作用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

管理入口省略 `--features` 时，面板显示九项且默认空选；后台编排保留旧标识的卸载兼容；指定逗号分隔的 ID 则仅处理对应项：`android_studio_opener`、`vscode_opener`、`xcode_opener`、`git-pull`、`git-rollback`、`git_remote`、`git_remote_copier`、`git-proxy-configure`、`git_empty_commit_push`。`--action install|uninstall` 可预设操作，普通运行打开 GUI，由面板按钮最终确认；`--non-interactive` 仅属于内部 `Scripts/ManageExtension.zsh` 的已确认编排协议，公开启动器不接受，普通操作始终在 GUI 确认。需要面板逐项或多项勾选时使用 [总管理器](../【MacOS】🧩管理Finder扩展.command)。旧 `git-sourcetree` 不能重新安装；如需清除旧选择，显式执行 `/bin/zsh ./Scripts/ManageProjectTools.zsh uninstall git-sourcetree`，只清除此标识并保留其它选择。

构建输出位于 `./work/DerivedData/`。安装先成功注册并确认统一扩展启用，再保存配置、停用对应单项扩展；其它启用选择保留。卸载移除所选功能，全部关闭后注销统一扩展，保留源码、构建缓存和空配置。两种模式均刷新 Finder，会影响当前 Finder 窗口；脚本没有单独文件日志，诊断保留在终端。

代理配置的安装 / C 检查 / R 恢复及精确快照边界见[业务说明](../JobsGitProxyConfigurator/README.md#usage)。空白提交执行 `git commit --allow-empty -m 'chore: empty commit'` 后 Push，暂存区必须为空；Push 失败保留本地提交并打印哈希，详见[Terminal 动作说明](../JobsTerminalOpener/README.md)。提交回退只读取已有本地远端跟踪快照，不 Fetch、不 Push；目标和模式由终端内 fzf 选择，非根选择按 `←` 返回上一层，`Esc` 取消。soft 保持索引及工作区，hard 舍弃选定工作树的已跟踪改动并保留子仓工作区；行为和限制见[提交回退说明](../JobsGitRollback/README.md)。安装或注册菜单不会自动执行回退、代理配置、拉取或推送。隔离回归不替代真实 Finder、Terminal 自动化权限和网络业务验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
