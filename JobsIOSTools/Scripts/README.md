# Jobs iOS 辅助工具脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、职责与入口](#jobs-toc-heading-1)
- [二、使用与日志](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

本目录只服务本独立扩展，不依赖其它 Finder 功能包。

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录的 [ManagementPanel.swift](./ManagementPanel.swift) 与 [FinderManagerGUI.zsh](./FinderManagerGUI.zsh) 负责随包面板和编译缓存。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中和执行中不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。切换操作会显示该操作已有的耗时。支持独立复制时须连同上级 App、启动脚本、源码及资源整体保留。

日志区上方的分隔条可上下拖动，窗口也可调整大小；功能列表与日志分别滚动，并保留操作按钮。日志右键提供“全选”，也可用 `⌘A` 全选后 `⌘C` 复制；拖动不会清空日志或改变功能勾选。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、职责与入口</span><!-- jobs-toc:heading-end -->

| 入口 | 用途 | 执行时机与影响 |
| --- | --- | --- |
| `EnableFinderExtension.zsh` | 构建后启用固定 Finder 扩展 | Xcode 的宿主 Build Phase 调用，注册本 App 内扩展并请求刷新 Finder；安装器或隔离构建设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过注册。缺少有效构建上下文停止。 |
| `Tools/DispatchIOSTools.zsh` | 目录校验及固定动作分发 | Terminal 私有载体调用；普通运行保留原业务交互，`--plan` 只读检查不执行实际业务；旧 `ios-clean-cache` 标识映射到 `ios-clean-build-artifacts`，只保留一个产物清理入口。Pod Install 由 Swift launcher 直接向现有交互 Shell 发送安全引用的单行命令，不经过此分发器。 |
| `Tools/CleanBuildArtifacts.zsh` | iOS 工程白名单产物清理 | 复用 Terminal 工程的完整清理核心；先检测和预览，输入 `CLEAN` 才删除，不处理共享缓存、Pods、锁文件或源码。 |
| `Tools/SourceManifest.json` | 来源和打包校验清单 | 维护时核对原始脚本与路径适配副本 SHA-256；不在运行时读取原仓库。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">二、使用与日志</span><!-- jobs-toc:heading-end -->

完整能力、安装 / 卸载参数、产物和风险见[上级 README](../README.md)。随包脚本及逐项适配见[Tools 说明](./Tools/README.md)。构建阶段日志位于系统临时目录的 `JobsIOSToolsBuildPhase.log`；业务日志继续使用原脚本约定。
