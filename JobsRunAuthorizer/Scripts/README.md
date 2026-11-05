# `JobsRunAuthorizer` 脚本说明

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、目录与入口](#entrypoints)
- [二、授权流程与边界](#authorization)
- [三、构建后注册与安装入口](#registration)
- [四、日志、依赖与验证](#logging)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录的 [ManagementPanel.swift](./ManagementPanel.swift) 与 [FinderManagerGUI.zsh](./FinderManagerGUI.zsh) 负责随包面板和编译缓存。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中和执行中不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。切换操作会显示该操作已有的耗时。支持独立复制时须连同上级 App、启动脚本、源码及资源整体保留。

日志区上方的分隔条可上下拖动，窗口也可调整大小；功能列表与日志分别滚动，并保留操作按钮。日志右键提供“全选”，也可用 `⌘A` 全选后 `⌘C` 复制；拖动不会清空日志或改变功能勾选。

`AuthorizeRun.zsh` 是 Finder“运行授权”的终端业务入口，保持原工具 `chmod +x` 的语义，只处理明确指定的一个普通文件。`EnableFinderExtension.zsh` 是本工程 Xcode Build Phase 的注册入口，两者职责独立。


**主题与语言：** 面板右上角可选择“黑夜 / 白天 / 跟随系统”和“简体中文 / 繁体中文 / 英文 / 跟随系统”，默认均为“跟随系统”。窄窗无法与标题同排时，工具组移至标题下一行并保持右对齐。选择后即时更新并保存，下次打开自动恢复；总面板、随包面板及联合 App 内置面板共用当前用户设置。切换保留勾选、安装 / 卸载任务、进度与日志；界面功能名称、状态和对话框按所选语言显示，后台工具原始日志保留原文。系统主题变化随原生外观更新，跟随系统语言在系统区域通知或窗口重新激活时重新读取。 偏好保存在当前用户的 `com.jobs.finderextensions.managementpanel.preferences` 域：`theme` 为 `system` / `dark` / `light`，`language` 为 `system` / `zh-Hans` / `zh-Hant` / `en`；不会写入工程或修改系统主题与语言。

**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，默认 `build`。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。默认不清理；UI 仅在应用程序安装模式显示清理选项，退出该组合就清空。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## 一、<span id="entrypoints">目录与入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 调用者与作用 |
| --- | --- |
| [AuthorizeRun.zsh](./AuthorizeRun.zsh) | 打包为宿主 App 资源，由 Terminal 执行；可独立终端调用。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | Xcode 构建后注册、启用当前精确路径的 Finder 扩展并刷新 Finder。 |

以下命令以当前 `Scripts/` 目录为基准：

```shell
/bin/zsh ./AuthorizeRun.zsh \
  --file "/目标目录/脚本.command"
```

只读检查和帮助：

```shell
/bin/zsh ./AuthorizeRun.zsh \
  --check \
  --file "/目标目录/脚本.command"

/bin/zsh ./AuthorizeRun.zsh --help
```

`--file` 必须紧跟一个绝对路径；拒绝多余参数、多个文件、目录、应用包与符号链接。路径按数据传递，空格、中文、引号、换行和 Shell 特殊字符不作为命令执行。

## 二、<span id="authorization">授权流程与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、首先显示写在脚本中的自述，检查参数和目标文件，记录设备号与 inode；目标不符合单文件要求时停止。

2、普通授权入口必须有可交互终端。核对显示路径后，直接回车继续；任何非空输入（包括空格）、`Ctrl+C` 或 EOF 均取消。取消前不创建业务日志，不改变权限。

3、确认后重新核验类型与身份，创建独立私有日志目录；执行前再次核验，目标被替换时停止。

4、只执行 `/bin/chmod +x` 并显示授权前后权限。保持调用时的 `umask`，不改成 `u+x` 或 `a+x`，不递归、不运行目标、不修改内容或隔离属性，也不调用 `sudo`。

5、授权失败显示原始错误和真实退出码；成功与失败日志均保留。`--check` 只读检查目标并显示当前权限、`umask`，不创建日志或改变权限；`--help` 显示用法。

增加执行权限不会保证文件可信、格式可执行或依赖齐全；本入口仅完成权限修改。当前用户不能修改的目标直接失败，不自动提权。配对的[解除运行授权](../../JobsRunAuthorizationRevoker/README.md)通过独立菜单清除全部执行位，不更改此脚本的 `chmod +x` 与 `umask` 语义。

## 三、<span id="registration">构建后注册与安装入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

`EnableFinderExtension.zsh` 仅接受 `JobsRunAuthorizer.app` 的有效 Xcode 构建上下文，固定注册 `com.jobs.JobsRunAuthorizer.FinderSyncExtension`。轮询只匹配当前构建扩展的完整路径，旧副本显示已启用不能作为成功依据；注册、启用或 Finder 刷新失败时保留重试标记。

外层安装入口负责旧副本与宿主 URL 登记清理，构建时设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 避免重复注册；隔离构建也使用该开关。这个开关只跳过本脚本，Xcode 自身仍可能自动登记产物，即使设置 `REGISTER_APP_WITH_LAUNCH_SERVICES=NO` 也需检查并精确注销本次临时路径。缺少 Xcode 上下文时脚本拒绝执行，不能把它当成手动安装入口。完整安装与卸载请使用[工程根目录入口](../README.md#installation)。

## 四、<span id="logging">日志、依赖与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

业务依赖系统 zsh、`stat`、`chmod`、`mktemp`，不安装第三方工具。确认后在系统临时目录创建 `JobsRunAuthorizer.XXXXXXXX/run.log`，目录为私有目录、日志只允许当前用户读写；终端输出与纯文本日志同步，不写入 ANSI 转义。目标路径和权限会写入本次日志，清理时按终端显示的精确目录处理。

构建后日志为系统临时目录中的 `JobsRunAuthorizerBuildPhase.log`，重试标记为 `JobsRunAuthorizerNeedsFinderRestart`。它们只记录扩展注册与刷新状态，与单次文件授权结果分别保存。

使用 `zsh -n` 检查语法，隔离测试使用临时普通文件、目录、符号链接及系统命令替身；不触碰真实业务文件或系统扩展。真实 Finder 单文件菜单和 Terminal 首次自动化权限需在安装后单独验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
