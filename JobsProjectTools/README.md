# `JobsProjectTools`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

一个 [**Finder Sync**](https://developer.apple.com/documentation/findersync) 扩展按固定顺序提供三个 IDE 一级入口和“Git操作”一级子菜单。八项可独立启停；[**Git**](https://git-scm.com/) 的五项功能集中在同一个子菜单中。

## 一、功能与显示条件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 顺序 | 操作 | 显示规则 |
| --- | --- | --- |
| 1 | 用 Android Studio 打开项目 | 非 Xcode 项目 |
| 2 | 用 VSCode 打开项目 | 非 Xcode 项目 |
| 3 | 用 Xcode 打开项目 | 当前目录包含有效 `.xcworkspace`、`.xcodeproj` 或 `Package.swift`，也支持直接选择工程包 |
| 4 | Git操作 → 拉取 Git 到最新 | 有效 Git 工作树内的普通文件夹，沿用原拉取脚本的复核和交互流程 |
| 5 | Git操作 → 打开 Git 远程地址 | 同上；点击后解析所属仓库并在默认浏览器打开远程网页 |
| 6 | Git操作 → 复制 Git 远程地址 | 同上；复制选定 remote 的原始地址 |
| 7 | Git操作 → 配置 Git 动态代理 | 同上；在 Terminal 安装、只读检查或恢复用户级动态 Git 入口 |
| 8 | Git操作 → 在终端创建空白 Commit 并 Push | 同上；Terminal 再检查分支、暂存区及远程后创建空白提交并推送 |

Flutter 根目录仍优先交给 Android Studio / VSCode；其 `ios` 子目录按本层 Xcode 工程判断。保留原有 Swift Package 支持。选择文件时按所在目录判断 IDE；Git 子菜单只接受普通文件夹及其内部空白处，支持仓库根、仓库子目录、子模块和 worktree。普通非 Git 目录、文件、目录包、符号链接、多选、工具栏和真实桌面空白处不显示 Git 子菜单；五项均未启用时也不显示空菜单。菜单打开后目标发生变化，点击和宿主仍会重新核验。

Finder 只控制本扩展内的顺序；整组相对其他扩展的位置由系统决定。

## 二、安装与逐项启停 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

保留完整仓库，双击 [安装入口](./【MacOS】安装项目工具Finder扩展.command)，或在根安装器中勾选需要的 IDE / Git 功能。IDE、Git 拉取、远程地址及动态代理的原单项安装入口也转到此包，并且只增加所选功能。

首次安装读取已经启用的旧 IDE / Git 功能，以及 Terminal 中的空白提交选择，将它们连同本次选择保存到当前用户 Application Support 下的 `JobsProjectTools/EnabledFeatures.txt`。统一扩展成功启用后，停止对应旧宿主、停用旧独立扩展并刷新 Finder。构建或注册失败不会先关闭旧菜单。以后重新安装会合并功能，保留其他选择；动态代理不再从系统桌面空白处单独显示。

双击 [卸载入口](./【MacOS】卸载项目工具Finder扩展.command)关闭八项；原单项卸载入口及根卸载器仅关闭选中项。最后一项关闭时注销统一扩展，保留空配置以免下次恢复全部功能。源码和构建缓存保留；关闭代理菜单不撤回业务脚本安装的 Git 配置。

构建输出位于 `work/DerivedData`。普通 [**Xcode**](https://developer.apple.com/xcode/) Build 不运行自动启用脚本；使用安装入口完成注册和功能状态合并。旧独立工程仅保留作实现参考和回归验证，不应再直接构建、运行其宿主来重新启用旧菜单。

## 三、实现与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `Shared/ProjectMenuAction.swift`：稳定顺序、显示条件、功能配置、URL 请求编解码。
- `JobsProjectToolsFinderSync/FinderSync.swift`：IDE 一级入口、Git 子菜单和独立 selector；点击时复核上下文。
- `JobsProjectTools/AppDelegate.swift`：宿主再次校验功能与项目条件，执行 IDE、Git 和剪贴板操作。
- Xcode 工程直接引用既有项目检测器、Git 远程解析器、Git 拉取 / 动态代理 launcher 和 Terminal 动作实现；业务脚本随统一 App 打包，安装后不读取源码目录。
- [Scripts/ManageProjectTools.zsh](./Scripts/README.md)：统一构建、注册、保存功能状态和逐项关闭。

```sh
python3 ./Tests/MenuTests.py
python3 ./Tests/InstallerTests.py
xcodebuild \
  -project ./JobsProjectTools.xcodeproj \
  -scheme JobsProjectTools \
  -configuration Debug \
  -derivedDataPath ./work/DerivedData \
  build
```

菜单回归使用真实 NSMenu / selector、临时项目和替身 Finder / 工作区，不实际打开 IDE、拉取仓库或写入系统剪贴板。安装回归模拟系统注册，覆盖旧功能迁移、部分安装 / 卸载、重新启用及失败保留。

## 四、输入、状态与副作用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

安装 / 卸载入口不传参数时处理全部八项；传入功能 ID 时只处理指定项：`android_studio_opener`、`vscode_opener`、`xcode_opener`、`git-pull`、`git_remote`、`git_remote_copier`、`git-proxy-configure`、`git_empty_commit_push`。两种入口均要求交互终端，回车执行、任意非空输入跳过；没有额外 YES 步骤。

构建输出位于 `./work/DerivedData/`。安装先成功注册并确认统一扩展启用，再保存配置、停用对应单项扩展；其它启用选择保留。卸载移除所选功能，全部关闭后注销统一扩展，保留源码、构建缓存和空配置。两种模式均刷新 Finder，会影响当前 Finder 窗口；脚本没有单独文件日志，诊断保留在终端。

代理配置的安装 / C 检查 / R 恢复及精确快照边界见[业务说明](../JobsGitProxyConfigurator/README.md#usage)。空白提交执行 `git commit --allow-empty -m 'chore: empty commit'` 后 Push，暂存区必须为空；Push 失败保留本地提交并打印哈希，详见[Terminal 动作说明](../JobsTerminalOpener/README.md)。安装或注册菜单不会自动执行代理配置、拉取或推送。隔离回归不替代真实 Finder、Terminal 自动化权限和网络业务验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
