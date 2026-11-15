# 桌面菜单安装管理

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、参数](#arguments)
- [二、业务资源](#resources)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录的 [ManagementPanel.swift](./ManagementPanel.swift) 与 [FinderManagerGUI.zsh](./FinderManagerGUI.zsh) 负责随包面板和编译缓存。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中和执行中不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。状态图标与活动指示器共用固定列并垂直居中，状态文字始终从同一位置开始；安装成功以独立绿色对勾图标和绿色“安装成功”文字显示。切换操作会显示该操作已有的耗时。支持独立复制时须连同上级 App、启动脚本、源码及资源整体保留。

日志区上方的分隔条可上下拖动，窗口也可调整大小；功能列表与日志分别滚动，并保留操作按钮。日志右键提供“全选”，也可用 `⌘A` 全选后 `⌘C` 复制；拖动不会清空日志或改变功能勾选。

`ManageDesktopTools.zsh` 接收 `install|uninstall` 和明确的叶功能 ID，统一管理六个桌面菜单。完整功能、配置、事务、日志和验证见[聚合包说明](../README.md)。


**面板与状态：** 主标题为“自定义Finder右键菜单”（繁体：自定義Finder右鍵菜單；英文：Customize Finder Context Menu）。安装 / 更新与卸载之间切换保留当前全部功能勾选；状态图标与活动指示器居中共用固定列，状态文字保持同一左边界。 功能分组支持按住标题拖动排序及跨列移动，布局保存在当前用户偏好中；默认右列仅放 Flutter，其余分组在左列。拖动和切换主题、语言或操作模式保留功能勾选、执行状态和日志；窄窗按布局顺序显示为单列。

**主题与语言：** 面板右上角可选择“黑夜 / 白天 / 跟随系统”和“简体中文 / 繁体中文 / 藏文 / 英文 / 日文 / 法文 / 西班牙文 / 德文 / 俄罗斯文 / 韩文 / 跟随系统”，默认均为“跟随系统”。主题和语言下拉入口紧凑显示，当前文字居中；窄窗无法与标题同排时，工具组移至标题下一行并保持右对齐。选择后即时更新并保存，下次打开自动恢复；总面板、随包面板及联合 App 内置面板共用当前用户设置。切换保留勾选、安装 / 卸载任务、进度与日志；界面功能名称、状态和对话框按所选语言显示，后台工具原始日志保留原文。系统主题变化随原生外观更新，跟随系统语言在系统区域通知或窗口重新激活时重新读取。 偏好保存在当前用户的 `com.jobs.finderextensions.managementpanel.preferences` 域：`theme` 为 `system` / `dark` / `light`，`language` 为 `system` / `zh-Hans` / `zh-Hant` / `bo` / `en` / `ja` / `fr` / `es` / `de` / `ru` / `ko`；不会写入工程或修改系统主题与语言。

**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，非交互调用默认 `build`。GUI 首次打开默认使用应用程序中的联合 App，并勾选安装成功后清理；显式参数或环境设置优先，用户可在面板手动取消。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。非交互 worker 默认不清理；GUI 首次打开默认勾选应用程序路线与安装成功后清理，用户可手动取消。UI 仅在应用程序安装模式显示自动清理选项，切换到卸载时隐藏但保留当前清理选择，返回安装时恢复；切换至构建目录才清空，切回应用程序路线不恢复旧勾选。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置与安装后自动清理两个复选框紧邻排列，窄窗按需换行；红色“🧹 清除构建产物”按钮位于底部主操作按钮右侧，安装 / 更新和卸载两种模式保持一致。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。“安装成功后清除此轮构建产物”复选框仅在应用程序安装模式出现，首次打开默认勾选，可手动取消。构建目录路线隐藏并清空自动清理复选框，独立清理按钮保持显示但禁用，避免清除正在使用的产物。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## 一、<span id="arguments">参数</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

支持 `ios-simulator-create`、`android-simulator-create`、`harmony-simulator-create`、`android-simulator-repair`、`harmony-simulator-repair` 和 `hidden-files-toggle`。可一次传多个 ID；空选、未知项和错误操作在构建或写配置前停止。

`--non-interactive` 表示调用方已经确认安装范围；`--install`／`--uninstall` 为旧入口兼容参数。`--skip-finder-restart` 只跳过本层 Finder 刷新，不跳过构建、签名和登记核对。未显式授权无交互运行时，必须从交互终端阅读说明后回车确认。

## 二、<span id="resources">业务资源</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

管理器不会执行 `Resource/` 中的模拟器脚本，不会打开宿主 URL。安装完成后，用户点击菜单才由宿主调用本包业务；五份脚本的来源与摘要见 [SourceManifest.json](../SourceManifest.json)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
