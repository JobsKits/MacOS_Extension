# <span id="前言">Terminal 扩展支持脚本</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、脚本职责](#files)
- [二、产物清理](#clean)
- [三、验证与日志](#verify)

</details>
<!-- jobs-toc:end -->

---

本目录提供工程产物清理和构建后的扩展注册支持。菜单与安装入口见[工程说明](../README.md)。Android / OpenHarmony 两平台清理支持 Flutter、Android 和 OpenHarmony 根目录；完整 Flutter 清理由 [Flutter 统一工具](../../JobsFlutterTools/README.md) 使用同一自包含核心提供。

分卷工具 `FileVolumes.zsh` 在终端确认后运行。拆分上限用 fzf 选择 50 / 100 / 1900 MiB 或自定义整数 MiB；自定义空行回到上层，取消不启动业务。输出目录为完整原文件名加 `.chunks`，兼容已有 `@序号of总数` 格式与补零编号。合并不扫描目录，只处理明确传入的一组完整分卷。系统 JXA 调用 Darwin 独占重命名，文件系统不支持时停止并保留候选，不回退到可能覆盖的移动。日志为系统临时目录 `JobsFileVolumes.log.*`。

单文件查看由 `ViewFileContent.zsh` 负责：默认超过 `1 MiB` 先在终端显示大小并询问，精确 `YES` 继续，回车 / EOF 取消；`JOBS_FILE_VIEWER_MAX_BYTES` 可配置正整数字节阈值。只读分块显示 ASCII / UTF-8，控制字符转义，二进制或未知编码再次确认后显示十六进制；不执行原文件、不写原文件，也不保存正文日志。

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录的 [ManagementPanel.swift](./ManagementPanel.swift) 与 [FinderManagerGUI.zsh](./FinderManagerGUI.zsh) 负责随包面板和编译缓存。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中和执行中不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。切换操作会显示该操作已有的耗时。支持独立复制时须连同上级 App、启动脚本、源码及资源整体保留。

日志区上方的分隔条可上下拖动，窗口也可调整大小；功能列表与日志分别滚动，并保留操作按钮。日志右键提供“全选”，也可用 `⌘A` 全选后 `⌘C` 复制；拖动不会清空日志或改变功能勾选。


**主题与语言：** 面板右上角可选择“黑夜 / 白天 / 跟随系统”和“简体中文 / 繁体中文 / 英文 / 跟随系统”，默认均为“跟随系统”。窄窗无法与标题同排时，工具组移至标题下一行并保持右对齐。选择后即时更新并保存，下次打开自动恢复；总面板、随包面板及联合 App 内置面板共用当前用户设置。切换保留勾选、安装 / 卸载任务、进度与日志；界面功能名称、状态和对话框按所选语言显示，后台工具原始日志保留原文。系统主题变化随原生外观更新，跟随系统语言在系统区域通知或窗口重新激活时重新读取。 偏好保存在当前用户的 `com.jobs.finderextensions.managementpanel.preferences` 域：`theme` 为 `system` / `dark` / `light`，`language` 为 `system` / `zh-Hans` / `zh-Hant` / `en`；不会写入工程或修改系统主题与语言。

**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，默认 `build`。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。默认不清理；UI 仅在应用程序安装模式显示清理选项，退出该组合就清空。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## 一、<span id="files">脚本职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 用途与边界 |
| --- | --- |
| [FileVolumes.zsh](./FileVolumes.zsh) | 单文件拆分或精确所选完整分卷合并；流式大小及 SHA-256 校验，原文件状态复核后通过 Darwin `RENAME_EXCL` 无覆盖发布，源文件 / 分卷始终保留。支持 `split <绝对文件路径> [--limit-bytes 正整数字节]` 或 `merge <全部分卷绝对路径...>`。 |
| [ViewFileContent.zsh](./ViewFileContent.zsh) | 仅接受一个普通文件绝对路径；拒绝链接、目录和特殊文件，系统 [**Perl**](https://www.perl.org/) 安全打开后先检查大小，再最多采样 8 KiB，输出不超过打开时的文件长度。无需安装第三方依赖。 |
| [CleanBuildArtifacts.zsh](./CleanBuildArtifacts.zsh) | 识别当前 Flutter、OpenHarmony、Android、iOS/Xcode 工程，仅删除白名单构建产物；`--android-openharmony` 限定两平台范围。系统 zsh、Perl 和 macOS 原生工具即可运行；不要求安装对应 SDK，不执行工程脚本。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | 由 Xcode Build Phase 提供构建环境后调用，停止旧宿主和扩展进程、注册当前 App/appex、请求启用并刷新 Finder。外层安装器设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 时跳过，由调用方接管登记；无需手动执行。 |

## 二、<span id="clean">产物清理</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录执行，路径替换为实际工程；以下命令只预览，不删除：

```shell
/bin/zsh ./CleanBuildArtifacts.zsh \
  "/实际工程路径" \
  --dry-run
```

`--detect` 只输出工程类型；不传选项时先展示路径，精确输入 `CLEAN` 才删除，回车取消，输入结束停止。`--yes` 只供已明确授权的无人值守调用。请先停止构建。清单解析支持常见块映射、单行 flow 与引号；拒绝重复依赖键、损坏或超限清单，Flutter 声明不依赖 `lib/` 是否已创建。

追加 `--android-openharmony` 可与上述模式组合，Finder 两平台入口始终传入此范围。Flutter 只清已识别的 `android/`、`ohos/` 及对应 `build/app/`、`build/ohos/`，保留 iOS、桌面平台、共享 `.dart_tool/` 和无法明确归属的平台输出；没有对应平台时提示没有可清理产物。原生 iOS 目标在此范围下被拒绝。默认模式继续支持 Flutter 完整工程和 iOS 的原白名单。

保留源码、锁文件、Pods、FVM SDK、签名、共享缓存和其它工程产物；自定义输出不推断。具体平台白名单和符号链接保护见[清理范围](../README.md#build-artifacts)。与 `../../JobsFlutterTools/Scripts/Tools/CleanBuildArtifacts.zsh` 保持逐字节一致。

## 三、<span id="verify">验证与日志</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行隔离回归，测试只处理临时夹具：

```shell
ruby ../Tests/BuildArtifactCleanerTests.rb
ruby ../Tests/FileContentViewerTests.rb
ruby ../Tests/FileVolumesTests.rb
```

清理结果显示在当前终端；脚本不单独写日志。由宿主创建的私有请求载体在退出时清理。扩展注册日志在系统临时目录的 `JobsTerminalOpenerBuildPhase.log`，待刷新标记为 `JobsTerminalOpenerNeedsFinderRestart`；注册阶段返回成功不能代替精确路径启用及真实菜单验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
