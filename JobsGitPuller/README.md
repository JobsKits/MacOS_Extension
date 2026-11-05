> 安装与卸载由 [JobsProjectTools](../JobsProjectTools/README.md) 统一管理，本项位于“Git操作”子菜单。只有有效 Git 工作树的普通文件夹或内部空白处显示；本目录的管理入口仅启停对应单项，请保留完整仓库。下文保留业务脚本、恢复边界与旧源码工程的说明；常规安装使用统一包，不重新启用旧一级菜单。

# `JobsGitPuller`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装与卸载](#install)
- [二、运行与恢复边界](#safety)
  - [PullGitRepository.zsh](#jobs-toc-heading-4)
- [三、工作区与恢复边界](#workspace-safety)
- [四、目录与验证](#files-tests)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**菜单范围：桌面空白处不显示本功能；文件夹与项目菜单仍按下文条件显示。桌面上选中的项目文件夹不受此空白菜单规则影响。**

**右键功能：拉取 Git 到最新。** [**Finder**](https://support.apple.com/zh-cn/102339) 单选文件夹或右键当前目录背景，打开 [**Terminal**](https://support.apple.com/guide/terminal/welcome/mac)，将所属 [**Git**](https://git-scm.com/) 工作树当前分支的 upstream 拉取并合并。非 Git 文件夹静默退出，不初始化仓库。

| 场景 / 输入 | 实际结果 |
| --- | --- |
| 干净工作区 | 展示来源，fetch 指定 upstream，再合并远端提交。 |
| 已暂存、未暂存或未跟踪内容 | 列出状态；直接回车确认继续，任何非空输入取消。先保存快照，成功后恢复暂存与工作区。 |
| 冲突 → `1` 或回车 | 还原到当前这轮拉取前的 HEAD、暂存区和工作区。 |
| 冲突 → `2` → `YES` | 放弃当前这轮拉取前的未提交内容，再合并上游；保留已有本地提交。 |
| 冲突 → `3` → commit 信息 | 恢复原改动并全部暂存、提交，再合并上游；信息直接回车允许为空。 |
| 第三项提交后再次冲突 | 继续三选一；选 `1` 保留刚确认的新提交，回到第二轮拉取前。再次选 `3` 不制造重复提交，保留新提交并停止供手工解决。 |
| 网络、认证、hook、签名等失败 | 明确停止；有文件冲突才进入冲突处理，不把失败当作成功。 |

本工程是 [MacOS@Extension](../README.md) 中的普通源码目录，源码、文档与版本由总仓统一管理。取得总仓即可获得本工程，无需单独远端或子模块下载；旧源码工程仍可独立构建供调试，菜单由同仓聚合包管理。Windows 对应独立包位于[平行仓库](../../WindowsOS@Extension/JobsGitPuller/README.md)；两端按各自管理入口部署。

本地文档保留 `[toc]`，由总仓的 [外置目录工具](../README.md#external-markdown-toc) 统一管理；本机整文件暂存时生成远端折叠目录，换机后需另行部署外置工具与本地属性。


**安装 / 卸载位置：** 面板提供“使用「应用程序」文件夹安装 / 卸载”复选框，默认不勾选。不勾选时沿用本地 `work` 内的构建产物；勾选时将所选功能统一安装到 `/Applications/Jobs自定义右键菜单.app`，面板同时显示这个联合 App 的名字。完整宿主及其扩展收在联合 App 内，不再为本轮所选功能生成其它顶层 App。安装到应用程序后，清理仓库构建输出或移走源码不影响已安装功能；构建目录模式仍须保留正在使用的 App。两种方式都保留各功能自身的工具链依赖。

**安装后清理：** 仅在“安装 / 更新”且勾选应用程序路线时，显示默认不勾选的“安装成功后清除此轮构建产物”。明确勾选后，只有当前模块部署、登记和提交全部成功才清理本轮对应的 DerivedData；构建目录路线及卸载模式隐藏并清空该选项。失败安装保留构建产物，清理失败会提示并保留已安装功能；不会整目录清理所有 `work`、其它模块或源码。

卸载按同一复选框选定的位置执行，所选位置没有 App 时保留另一位置及其功能配置；共享宿主仍有未卸载菜单时保留 App，最后一项移除后注销并删除该功能模块；联合 App 的最后一个模块移除后才删除外层 `Jobs自定义右键菜单.app`。切换位置安装会把登记切到新位置，构建目录中的另一份产物保留；所选功能的旧版顶层自有 App 在成功提交后收拢至联合 App，未知 App 不覆盖或删除。完整说明见[App 部署支持库](./Scripts/【MacOS】AppDeployment.zsh/README.md)。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## 一、<span id="install">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

菜单安装与卸载统一使用 [图形管理入口](./【MacOS】管理Git拉取Finder扩展.app)。直接打开面板，选择“安装 / 更新”或“卸载”并勾选当前范围内的功能；默认空选，点击操作按钮即确认。每项显示等待、正在安装 / 卸载、成功或失败；底部日志实时滚动，可选择复制或复制全部。运行中锁定选择和关闭入口，结束后保留结果与日志。首次打开或面板源码更新后会在后台编译，失败以桌面提示和启动日志说明。

原同名 `.command` 入口保留，终端只负责唤起独立 GUI，随后结束启动脚本；本次启动任务结束后自动关闭对应终端页，安装 / 卸载、进度与实时日志均由 GUI 后台处理。已有交互 Shell 中手工调用时保留原工作会话。内部实现为 `Scripts/ManageExtension.zsh`；完整仓内单功能入口使用总面板的受限范围。可独立复制的包须整体保留 `.command`、`.app`、Scripts、工程源码和资源。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

本入口转交 [JobsProjectTools](../JobsProjectTools/README.md)，只管理 `git-pull`，需要保留同仓聚合工程源码。旧宿主、扩展与 Xcode 工程仍供实现参考和隔离验证；常规菜单安装不再注册本目录的旧独立扩展。

需要 macOS 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 与 macOS SDK。安装成功后启用本入口对应功能并保留其它已装选择；卸载仅减去对应功能，仍有其它项时保留共享 App 和登记，最后一项才停用聚合扩展。源码、用户工程、SDK、模拟器、业务数据和既有业务配置保留；安装与卸载只管理菜单，不执行菜单业务。操作完成后刷新 Finder，请先结束 Finder 文件搬移。

诊断保留在终端；聚合工程的构建、配置与登记边界见包说明。

也可从 [总管理面板](../【MacOS】🧩管理Finder扩展.command) 选择一个或多个功能，在同一面板切换安装 / 更新或卸载。

## 二、<span id="safety">运行与恢复边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

要求 macOS 12+、[**Xcode**](https://developer.apple.com/xcode/) 和健康 Git。已有 Git 直接复用，不安装依赖，不改变网络代理、全局 Git 配置或分支 upstream。分支没有 upstream、游离 HEAD、尚无提交、稀疏检出、特殊索引、已有 merge / rebase 等事务时停止。

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">[PullGitRepository.zsh](./Scripts/PullGitRepository.zsh)</span><!-- jobs-toc:heading-end -->

> **目的：** 在交互终端执行 Git 保护、拉取和冲突三选一。

- 自述回车后检查分支和 upstream；非 Git 目录不写日志、不修改文件。
- 未提交内容另行回车确认，展示脱敏来源，先 fetch 成功，再保存 HEAD 和含未跟踪文件的 stash 快照。
- 合并本次取得的固定上游提交，恢复本地改动；合并或改动恢复冲突时进入三选一。
- 原有 stash 不删除，快照与恢复说明保留；成功核对上游提交确实已成为 HEAD 的祖先。

在本目录执行：

```shell
/bin/zsh ./Scripts/PullGitRepository.zsh \
  '../../目标项目'
```

## 三、<span id="workspace-safety">工作区与恢复边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 仅当前工作树，当前分支配置的单个远端 upstream；子目录会显示所属仓库根。保留本地提交，不强制对齐远端，不 push、不自动选择其他 remote。
- 不递归更新子模块。存在子模块脏状态或检出变化时先停止；远端修改 gitlink 后，子模块实际检出仍保持原样，需要单独同步。
- 快照包含 tracked 的暂存 / 未暂存状态及非 ignored 的 untracked。ignored 内容、嵌套独立仓库和子模块内容不属于“放弃”的范围；发现未忽略的嵌套仓库会停止。合并明确禁止覆盖 ignored 文件。
- 冲突菜单的 `2` 必须精确输入 `YES`。初始改动仍保留在恢复引用中；菜单里的“放弃”表示不再恢复到当前工作区。三项都不自动改写已有本地历史。
- 操作期间停止其它 Git 客户端、文件编辑及后台生成任务。本工具对共用 Git 元数据加锁，并在等待输入后复检状态；检测到变化会保留现场。该锁无法阻止外部 Git 客户端。
- `Ctrl+C` / 信号中断保留现场和恢复引用，不冒险自动 reset。按终端显示的 `recovery.txt` 检查、另存新增内容后人工恢复；确认旧进程结束后才处理遗留锁。
- 标准 Git hooks、签名与提交身份仍然生效。第三项提交失败时保留文件和快照，不继续拉取。它提交原有全部非忽略改动，不只提交原暂存内容。

每次日志与 `recovery.txt` 保存于当前工作树实际 Git 元数据目录的 `jobs-git-pull/<运行编号>/`。`refs/jobs-git-pull/<运行编号>/head` 保存原 HEAD，`snapshot` 保存原 stash，`upstream` 保存本次远端提交，`committed`（若有）保存第三项新提交。链接工作树的锁使用共用 Git 目录；快照不自动过期，确认不再需要后由使用者处理。

Git 官方说明提醒：带未提交改动直接 merge 后，abort 未必能恢复，因此这里先创建 stash 再合并；恢复使用 `apply --index`，不 pop / drop 既有 stash。参见 [merge 文档](https://git-scm.com/docs/git-merge)、[stash 文档](https://git-scm.com/docs/git-stash)。

## 四、<span id="files-tests">目录与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 路径 | 职责 |
| --- | --- |
| `JobsGitPuller.xcodeproj/` | 独立宿主与扩展 target、Scheme、脚本资源。 |
| `JobsGitPuller/` | 无窗口后台宿主、URL 请求转发、Terminal 私有载体。 |
| `JobsGitPullFinderSync/` | 单目录 / 当前目录菜单，点击时重新读取目标。 |
| `JobsGitPullShared/` | 目录检查与严格请求编码解码。 |
| [Scripts](./Scripts/README.md) | Git 状态机与构建后扩展启用脚本。 |
| `Tests/` | 真实临时 Git 远端及原生 URL / 路径 / 载体回归。 |

```shell
ruby ./Tests/GitPullCommandTests.rb

zsh -n ./Scripts/PullGitRepository.zsh
```

隔离测试不访问真实远端、不改业务仓库、不注册扩展。源码与构建验证不等同于真实 Finder 授权及 Windows 桌面验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
