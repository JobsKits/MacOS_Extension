# `JobsProjectTools Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、输入与调用](#jobs-toc-heading-2)
- [二、功能与输出](#jobs-toc-heading-3)
- [三、依赖、副作用与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录的 [ManagementPanel.swift](./ManagementPanel.swift) 与 [FinderManagerGUI.zsh](./FinderManagerGUI.zsh) 负责随包面板和编译缓存。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中和执行中不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。切换操作会显示该操作已有的耗时。支持独立复制时须连同上级 App、启动脚本、源码及资源整体保留。

日志区上方的分隔条可上下拖动，窗口也可调整大小；功能列表与日志分别滚动，并保留操作按钮。日志右键提供“全选”，也可用 `⌘A` 全选后 `⌘C` 复制；拖动不会清空日志或改变功能勾选。

[ManageProjectTools.zsh](./ManageProjectTools.zsh) 由上级图形管理器调用，负责九项 IDE / Git 功能的统一构建、注册与逐项状态管理；三个 IDE 保留一级入口，Git 六项集中在“Git操作”子菜单。“用 [**Sourcetree**](https://www.sourcetreeapp.com/) 打开”已从菜单与管理选择中移除。本脚本不是 Finder 点击后的任意命令执行器。


**主题与语言：** 面板右上角可选择“黑夜 / 白天 / 跟随系统”和“简体中文 / 繁体中文 / 英文 / 跟随系统”，默认均为“跟随系统”。窄窗无法与标题同排时，工具组移至标题下一行并保持右对齐。选择后即时更新并保存，下次打开自动恢复；总面板、随包面板及联合 App 内置面板共用当前用户设置。切换保留勾选、安装 / 卸载任务、进度与日志；界面功能名称、状态和对话框按所选语言显示，后台工具原始日志保留原文。系统主题变化随原生外观更新，跟随系统语言在系统区域通知或窗口重新激活时重新读取。 偏好保存在当前用户的 `com.jobs.finderextensions.managementpanel.preferences` 域：`theme` 为 `system` / `dark` / `light`，`language` 为 `system` / `zh-Hans` / `zh-Hant` / `en`；不会写入工程或修改系统主题与语言。

**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，默认 `build`。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。默认不清理；UI 仅在应用程序安装模式显示清理选项，退出该组合就清空。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、输入与调用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

第一个参数必须为 `install` 或 `uninstall`，后面至少一个功能 ID：`android_studio_opener`、`vscode_opener`、`xcode_opener`、`git-pull`、`git-rollback`、`git_remote`、`git_remote_copier`、`git-proxy-configure`、`git_empty_commit_push`；未知 ID 停止。用户使用[功能 README 中的上级入口](../README.md)在 GUI 选择功能并点击按钮确认，内部脚本不再重复询问。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、功能与输出 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 安装读取已有功能状态；首次无配置时也保留已启用的对应单项，合并指定选择。
- 旧 `git-sourcetree` 仅兼容 `uninstall`，不能重新安装；执行 `ManageProjectTools.zsh uninstall git-sourcetree` 可清除旧配置并保留其它功能。
- Git 归并独立迁移一次：只读取明确启用的旧动态代理及 Terminal 空白提交选择，成功保存后记录迁移标记，后续安装不重新打开已关闭项。旧代理扩展停用后不再保留桌面独立菜单，但用户业务配置和快照继续保留。
- 提交回退菜单独立迁移一次：只合并系统明确启用的旧 `JobsGitRollback` 扩展；统一扩展成功后精确停用旧回退宿主和扩展，后续安装不重新打开已关闭项。
- 使用完整 Xcode 构建到上级 `./work/DerivedData/`，注册并等待当前精确扩展路径启用成功，再原子保存 `EnabledFeatures.txt`，停用对应独立扩展。
- 卸载只删选择的功能配置与启用状态；最后一项关闭后注销统一扩展，保留源码和构建缓存。
- 配置在当前用户 Application Support 的 JobsProjectTools 目录中；两种模式最后刷新 Finder。终端显示状态与错误，没有单独业务日志文件。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、依赖、副作用与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要 macOS、系统 zsh、完整 Xcode / macOS SDK、PlugInKit、LaunchServices 与可用签名；不安装这些依赖。安装和卸载会停止本功能宿主 / 扩展，写用户配置和系统登记并刷新 Finder。构建或启用验证失败时停止，不先关闭仍可用的独立菜单；不执行 Git 回退、拉取、提交、推送、代理配置或打开 IDE。

本目录属于 [JobsProjectTools](../README.md) 的普通源码目录，无独立 Git。安装、迁移与卸载使用隔离替身验证；没有修改真实用户配置、登记扩展或刷新 Finder。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
