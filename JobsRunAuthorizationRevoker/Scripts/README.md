# `JobsRunAuthorizationRevoker` 脚本说明

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与入口](#files)
- [二、交互、结果与限制](#behavior)
- [三、依赖、日志与登记](#runtime)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录的 [ManagementPanel.swift](./ManagementPanel.swift) 与 [FinderManagerGUI.zsh](./FinderManagerGUI.zsh) 负责随包面板和编译缓存。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中和执行中不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。切换操作会显示该操作已有的耗时。支持独立复制时须连同上级 App、启动脚本、源码及资源整体保留。

日志区上方的分隔条可上下拖动，窗口也可调整大小；功能列表与日志分别滚动，并保留操作按钮。日志右键提供“全选”，也可用 `⌘A` 全选后 `⌘C` 复制；拖动不会清空日志或改变功能勾选。

本目录自包含“解除运行授权”的业务脚本和构建后登记脚本，由 Jobs 维护。业务只清除一个普通文件的全部执行位，安装菜单本身不修改文件权限。


**主题与语言：** 面板右上角可选择“黑夜 / 白天 / 跟随系统”和“简体中文 / 繁体中文 / 英文 / 跟随系统”，默认均为“跟随系统”。窄窗无法与标题同排时，工具组移至标题下一行并保持右对齐。选择后即时更新并保存，下次打开自动恢复；总面板、随包面板及联合 App 内置面板共用当前用户设置。切换保留勾选、安装 / 卸载任务、进度与日志；界面功能名称、状态和对话框按所选语言显示，后台工具原始日志保留原文。系统主题变化随原生外观更新，跟随系统语言在系统区域通知或窗口重新激活时重新读取。 偏好保存在当前用户的 `com.jobs.finderextensions.managementpanel.preferences` 域：`theme` 为 `system` / `dark` / `light`，`language` 为 `system` / `zh-Hans` / `zh-Hant` / `en`；不会写入工程或修改系统主题与语言。

**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，默认 `build`。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。默认不清理；UI 仅在应用程序安装模式显示清理选项，退出该组合就清空。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## 一、<span id="files">文件与入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| [RevokeRun.zsh](./RevokeRun.zsh) | 随 App 打包，通过 Terminal 核对并确认单文件 `chmod a-x`；支持独立调用。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | 仅供有效 Xcode 构建上下文登记、启用当前精确 appex 路径并刷新 Finder。 |

从本目录调用：

```shell
/bin/zsh ./RevokeRun.zsh \
  --file "/目标目录/脚本.command"

/bin/zsh ./RevokeRun.zsh \
  --check \
  --file "/目标目录/脚本.command"

/bin/zsh ./RevokeRun.zsh --help
```

## 二、<span id="behavior">交互、结果与限制</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `--file` 后必须只有一个普通文件的绝对路径；拒绝目录、链接、多文件及额外参数。
- 自述先展示用途、路径、日志策略和影响范围，普通操作必须有可交互终端。回车继续，任意非空输入（含空格）、Ctrl+C、EOF 取消；确认前不写日志和权限。
- 以设备号 / inode 复检选择对象，确认后才创建私有日志，执行 `/bin/chmod a-x`，复读当前权限并确认所有执行位已清零；失败非零退出。
- `a-x` 显式指定所有者、组和其它用户，因此严格 `umask` 也不会留下执行位。读写位保留；不改 ACL、隔离属性和内容，不递归、不运行目标、不提权。
- 不能阻止解释器读取可读脚本，也不恢复某次授权前的完整模式。菜单对应的“运行授权”由独立包提供。
- `--check` 和 `--help` 不需要交互，不创建日志、不修改权限。只读检查显示当前权限和 `umask`。

## 三、<span id="runtime">依赖、日志与登记</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

业务只依赖系统 zsh、`stat`、`chmod`、`mktemp`，不下载组件。业务日志位于系统临时目录 `JobsRunAuthorizationRevoker.XXXXXXXX/run.log`，目录 `700`、日志 `600`，纯文本与终端同步；载体清理不删除结果日志。

登记脚本固定标识 `com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension`，日志 `JobsRunAuthorizationRevokerBuildPhase.log` 与重试标记 `JobsRunAuthorizationRevokerNeedsFinderRestart` 均在系统临时目录。它要求当前 App 的真实构建上下文；不能当作手动安装入口。隔离构建设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过它，但仍需单独检查 Xcode 自动登记。

完整安装 / 卸载入口位于[工程根目录](../README.md#installation)。用 `zsh -n` 做语法检查，临时文件 / 菜单 / 注册替身回归在 `../Tests/`；真实菜单与 Terminal 首次自动化权限需安装后另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
