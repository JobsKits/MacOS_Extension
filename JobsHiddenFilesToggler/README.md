# `JobsHiddenFilesToggler` 显示 / 隐藏文件

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装与使用](#usage)
- [二、切换与失败处理](#behavior)
- [三、卸载](#uninstall)
- [四、目录、产物与日志](#layout)
- [五、项目配置支持](#project-support)
- [六、验证与排查](#validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

菜单安装与卸载统一使用 [图形管理入口](./【MacOS】管理显示隐藏文件Finder扩展.app)。直接打开面板，选择“安装 / 更新”或“卸载”并勾选当前范围内的功能；默认空选，点击操作按钮即确认。每项显示等待、正在安装 / 卸载、成功或失败；底部日志实时滚动，可选择复制或复制全部。运行中锁定选择和关闭入口，结束后保留结果与日志。首次打开或面板源码更新后会在后台编译，失败以桌面提示和启动日志说明。

原同名 `.command` 入口保留，终端只负责唤起独立 GUI，随后结束启动脚本；本次启动任务结束后自动关闭对应终端页，安装 / 卸载、进度与实时日志均由 GUI 后台处理。已有交互 Shell 中手工调用时保留原工作会话。内部实现为 `Scripts/ManageExtension.zsh`；完整仓内单功能入口使用总面板的受限范围。可独立复制的包须整体保留 `.command`、`.app`、Scripts、工程源码和资源。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

> 为 [**macOS**](https://www.apple.com/macos/) 的 [**Finder**](https://support.apple.com/guide/mac-help/welcome/mac) 增加按当前全局状态变化的右键菜单：当前隐藏时显示“👁️ 显示文件”，当前显示时显示“🙈 隐藏文件”。仅在系统桌面和任意文件夹的空白处显示；点击后立即反转当前用户的隐藏文件显示偏好，并刷新当前用户 Finder。

| 右键位置 | 是否显示 |
| --- | --- |
| 系统桌面空白处 | 显示 |
| 普通文件夹空白处、已挂载卷目录背景 | 显示 |
| 选中的文件、文件夹、应用包或多个项目 | 不显示 |
| 工具栏、侧边栏 | 不显示 |

菜单位置跟随当前目录，切换效果作用于当前用户的整个 Finder；不会更改文件本身的隐藏标记，也不会删除文件。

当前菜单安装由 [JobsDesktopTools](../JobsDesktopTools/README.md) 统一承载。本目录的管理入口只启停 `hidden-files-toggle` 这一叶；需要同仓 `JobsDesktopTools/` 源码。聚合扩展按固定顺序排列三项新建、两项修复和动态文件显示开关，保留逐叶选择；普通目录背景仅显示文件开关。安装产物统一在 `../JobsDesktopTools/work/DerivedData/Build/Products/Debug/JobsDesktopTools.app`，安装／卸载日志统一为系统临时目录 `JobsDesktopToolsInstall.log`。本目录原工程、旧 Bundle ID、旧 URL 和隔离回归仍保留，后文源码标识用于兼容实现参考，不是当前安装器注册目标。

## 一、<span id="usage">安装与使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、准备 macOS 12 或更新版本，以及可正常使用的完整 [**Xcode**](https://developer.apple.com/xcode) 与 macOS SDK。安装器只检查现有工具，不会自动安装或切换开发目录。

2、双击 [独立管理入口（安装模式）](./【MacOS】管理显示隐藏文件Finder扩展.command)。在面板选择安装 / 更新并勾选功能，点击操作按钮后后台执行。管理器构建并验证聚合 App，只启用本叶；按需刷新当前用户 Finder，安装本身不切换显示偏好。

3、在桌面或任意文件夹空白处右键，点击菜单显示的下一步动作：“👁️ 显示文件”切换为显示，“🙈 隐藏文件”切换为隐藏；每次打开菜单重新读取系统状态，不缓存旧标题。菜单不依赖打开的目录是否可写，不要求开发项目。

4、也可从 [总管理入口](../【MacOS】🧩管理Finder扩展.command) 勾选本功能。源码安装需保留相邻聚合包；已构建聚合 App 内含全部业务资源。

Finder 刷新会短暂关闭并重新打开 Finder 界面。无需打开终端、模拟快捷键、授予辅助功能或 Terminal 自动化权限。受系统保护的部分项目仍可能不显示。

## 二、<span id="behavior">切换与失败处理</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 菜单每次展开实时读取 Finder 全局偏好，图标和文字共同表达下一次点击的动作；偏好同步失败或值非法时显示“⚠️ 隐藏文件状态不可用”并置灰。Finder 扩展仅获准读取 `com.apple.finder` 共享偏好域，实际写入仍由后台宿主完成。
- 后台宿主每次点击都通过 [**CFPreferences**](https://developer.apple.com/documentation/corefoundation/preferences-utilities) 同步读取 `com.apple.finder` 的 `AppleShowAllFiles`，作用域为当前用户、任意主机；没有设置时按隐藏处理。可识别布尔值、数字 `0 / 1` 以及 `true / false / yes / no / 0 / 1` 字符串。
- 写入规范布尔值后，同步并回读校验，再执行固定的 `killall -u <当前真实账户> Finder` 刷新。仅处理当前用户的 Finder，不扩大到其它账户。使用系统命令参数数组，不拼接 Shell 命令。
- 读失败、值异常、同步写入失败或回读不符时停止并显示失败原因，不把旧缓存当成功。若偏好写入已确认但 Finder 刷新失败，弹窗会明确说明新偏好已保存、需要手动重新启动 Finder；再次点击会反转当时的偏好。
- 扩展只接收背景菜单回调，监控根目录以覆盖真实桌面和挂载卷。背景目录没有元数据读取权限时仍可提供全局开关；明确识别出的文件和应用包不提供入口。
- 兼容源码中的 Finder 扩展使用固定 URL `jobshiddenfilestoggler://finder/toggle`；当前聚合入口使用 `jobsdesktoptools://perform/hidden-files-toggle?show=1` 或 `show=0` 表达显式目标。宿主拒绝额外路径、查询参数和其它 URL；两种 URL 回调及退出前的重复事件只派发一次切换，避免一次点击被反转两次。
- 独立打开宿主只接收请求并自动退出；`--initialize-finder-extension` 仅初始化扩展，不触发偏好切换。

## 三、<span id="uninstall">卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

双击 [独立管理入口（卸载模式）](./【MacOS】管理显示隐藏文件Finder扩展.command)，在面板选择卸载并勾选本叶，点击操作按钮后关闭本叶。共享 App、其它菜单、项目源码和当前显示偏好保留。

**卸载保留当前隐藏文件显示偏好。** 若希望隐藏文件重新隐藏，请先使用菜单切换到隐藏，再卸载菜单。卸载脚本不会替用户反转偏好。

内部 `Scripts/ManageExtension.zsh` 供面板或已确认的总管理器调用时支持 `--action install|uninstall --non-interactive [--skip-finder-restart]`。跳过刷新参数只让外层统一刷新，不跳过注册和身份核验。

## 四、<span id="layout">目录、产物与日志</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 路径 | 职责 |
| --- | --- |
| `JobsHiddenFilesToggler/` | 后台 App、偏好切换、当前用户 Finder 刷新与扩展初始化 |
| `JobsHiddenFilesFinderSync/` | 实时读取状态生成背景菜单，打开固定宿主 URL；不在菜单生成时写入偏好 |
| `JobsHiddenFilesShared/` | 共用的菜单范围和固定 URL 校验；偏好读取与布尔规范化源码由两个 target 共享编译 |
| `JobsHiddenFilesToggler.xcodeproj/` | App 与 Finder Sync 两个 target |
| [Scripts](./Scripts/README.md) | Xcode 编译后启用脚本与安全跳过开关 |
| `Tests/` | 偏好读写、派发去重及安装的隔离夹具 |
| `../JobsDesktopTools/work/DerivedData/Build/Products/Debug/JobsDesktopTools.app` | 当前聚合安装产物；菜单使用期间保留 |

宿主 ID 为 `com.jobs.hiddenfilestoggler`，扩展 ID 为 `com.jobs.hiddenfilestoggler.findersync`，扩展产物名为 `JobsHiddenFilesFinderSync.appex`。

兼容宿主诊断至系统临时目录 `JobsHiddenFilesToggler.log`。当前菜单安装和卸载使用 `JobsDesktopToolsInstall.log`；构建后启用日志和待刷新标记见 [Scripts 说明](./Scripts/README.md)。固定宿主日志拒绝跟随同名符号链接。

## 五、<span id="project-support">项目配置支持</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

Xcode 的 `Enable Finder Extension` 编译阶段调用 `Scripts/EnableFinderExtension.zsh`，默认注册、启用当前构建产物并刷新当前用户 Finder。隔离构建或外层安装器应设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1`，避免构建阶段重复注册和重启。

宿主为非沙盒后台 App，只有固定偏好和固定 Finder 刷新职责；Finder Sync 扩展保持沙盒隔离。项目不引入第三方依赖，也不要求 AppleEvents 自动化权限。

## 六、<span id="validation">验证与排查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本功能目录执行隔离回归：

```shell
/bin/zsh ./Tests/run.zsh
ruby ./Tests/HiddenFilesMenuTests.rb
```

测试只运行临时程序、注入偏好接口和系统命令替身，不写真实 Finder 偏好、不注册或启用扩展、不刷新 Finder。覆盖菜单图标 / 文字的两态与失效置灰、规范值、异常值、实时读取、读写失败、回读缺失、刷新失败、桌面无 target、挂载卷目录背景、非背景拒绝、严格 URL、双回调去重及精确安装卸载。

源码隔离回归和两 target Debug 构建、深度签名验证通过。真实菜单显示、系统扩展授权及真实隐藏文件切换，需要安装后在目标机器验收。

菜单没有出现时，先查看安装日志并在系统设置中检查 Finder 扩展是否启用；不要移动或删除仍被注册的产物。切换未完成时优先查看弹窗和宿主日志，区分偏好写入与 Finder 刷新结果。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
