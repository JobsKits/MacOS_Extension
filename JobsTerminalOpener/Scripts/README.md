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
