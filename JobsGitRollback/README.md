# `JobsGitRollback`：Git 提交回退

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、菜单范围与工作树识别](#menu-scope)
- [二、安装与卸载](#install)
- [三、操作、确认与恢复边界](#operation)
- [四、实现与验证](#files-tests)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

在 [**Finder**](https://support.apple.com/guide/mac-help/welcome/mac) 的“Git操作 → Git 提交回退”中打开 [**Terminal**](https://support.apple.com/guide/terminal/welcome/mac)，选择当前 [**Git**](https://git-scm.com/) 工作树的回退模式和目标。macOS 12 或更新系统，安装需要完整 [**Xcode**](https://developer.apple.com/xcode/)，运行需要健康 Git 和 [**fzf**](https://github.com/junegunn/fzf)；不自动安装依赖。

本目录归 [MacOS@Extension](../README.md) 统一管理，无独立 Git 仓库。菜单由 [JobsProjectTools](../JobsProjectTools/README.md) 聚合，本目录唯一管理入口只启停 `git-rollback` 单项；Windows 对应包见[双端目录](../../WindowsOS@Extension/JobsGitRollback/README.md)。

| 模式 | 目标与效果 |
| --- | --- |
| soft 回退到 upstream | 使用本地远端跟踪快照，撤回目标之后的本地提交，保留索引和工作区。多条快照可明确选择；没有自动 fetch。 |
| 选择提交 soft 回退 | 从最多 200 条本地历史记录中选择完整提交号；目标必须是当前 HEAD 的祖先。 |
| hard 回退到 upstream | 将当前工作树重置到选定快照；列出仓库和固定提交号，精确输入 `YES` 才执行。 |
| 选择提交 hard 回退 | 从最多 200 条历史中选择目标，`YES` 确认后舍弃当前已跟踪改动。 |
| 选择 tag hard 回退 | 按创建时间选择 tag，以完整 `refs/tags/` 解析固定提交，`YES` 后执行。 |
| 选择 reflog hard 回退 | 从最多 200 条 reflog 记录中选择固定提交，`YES` 后执行。 |


**安装 / 卸载位置：** 面板提供“使用「应用程序」文件夹安装 / 卸载”复选框，默认不勾选。不勾选时沿用本地 `work` 内的构建产物；勾选时将所选功能统一安装到 `/Applications/Jobs自定义右键菜单.app`，面板同时显示这个联合 App 的名字。完整宿主及其扩展收在联合 App 内，不再为本轮所选功能生成其它顶层 App。安装到应用程序后，清理仓库构建输出或移走源码不影响已安装功能；构建目录模式仍须保留正在使用的 App。两种方式都保留各功能自身的工具链依赖。

**安装后清理：** 仅在“安装 / 更新”且勾选应用程序路线时，显示默认不勾选的“安装成功后清除此轮构建产物”。明确勾选后，只有当前模块部署、登记和提交全部成功才清理本轮对应的 DerivedData；构建目录路线及卸载模式隐藏并清空该选项。失败安装保留构建产物，清理失败会提示并保留已安装功能；不会整目录清理所有 `work`、其它模块或源码。

卸载按同一复选框选定的位置执行，所选位置没有 App 时保留另一位置及其功能配置；共享宿主仍有未卸载菜单时保留 App，最后一项移除后注销并删除该功能模块；联合 App 的最后一个模块移除后才删除外层 `Jobs自定义右键菜单.app`。切换位置安装会把登记切到新位置，构建目录中的另一份产物保留；所选功能的旧版顶层自有 App 在成功提交后收拢至联合 App，未知 App 不覆盖或删除。完整说明见[App 部署支持库](./Scripts/【MacOS】AppDeployment.zsh/README.md)。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## 一、<span id="menu-scope">菜单范围与工作树识别</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 单选 Git 工作树普通文件夹，或者在该目录空白处右键显示；普通子目录映射到其最近的所属仓库。
- 子模块、嵌套独立 Git 和 linked worktree 均处理其自身工作树，不把请求误交外层父仓。
- 普通非 Git 目录、裸仓库、`.git` 元数据、文件、符号链接、应用包、多选和桌面空白处隐藏。损坏的内层 `.git` 不借外层有效仓库通过。
- 菜单显示与点击再次只读检查元数据，终端中由 Git 再确认实际工作树、HEAD 与事务状态。尚无提交的仓库会显示入口，但终端明确停止；菜单可见不代表已经执行回退。
- 后台宿主与 Terminal 载体执行业务前，分别用 Git 只读核对实际工作树根和 Git 元数据目录，必须对应最近 `.git`。`core.worktree` 指向兄弟目录或派发后绑定改变时停止，避免回退其它工作树。继承的 Git 定位和临时配置变量仅在子进程中隔离，用户环境和持久配置不变。

## 二、<span id="install">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

菜单安装与卸载统一使用 [图形管理入口](./【MacOS】管理Git提交回退Finder扩展.app)。直接打开面板，选择“安装 / 更新”或“卸载”并勾选当前范围内的功能；默认空选，点击操作按钮即确认。每项显示等待、正在安装 / 卸载、成功或失败；底部日志实时滚动，可选择复制或复制全部。运行中锁定选择和关闭入口，结束后保留结果与日志。首次打开或面板源码更新后会在后台编译，失败以桌面提示和启动日志说明。

原同名 `.command` 入口保留，终端只负责唤起独立 GUI，随后结束启动脚本；本次启动任务结束后自动关闭对应终端页，安装 / 卸载、进度与实时日志均由 GUI 后台处理。已有交互 Shell 中手工调用时保留原工作会话。内部实现为 `Scripts/ManageExtension.zsh`；完整仓内单功能入口使用总面板的受限范围。可独立复制的包须整体保留 `.command`、`.app`、Scripts、工程源码和资源。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

本入口转交 [JobsProjectTools](../JobsProjectTools/README.md)，只管理 `git-rollback`，需要保留同仓聚合工程源码。旧宿主、扩展与 Xcode 工程仍供实现参考和隔离验证；常规菜单安装不再注册本目录的旧独立扩展。

需要 macOS 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 与 macOS SDK。安装成功后启用本入口对应功能并保留其它已装选择；卸载仅减去对应功能，仍有其它项时保留共享 App 和登记，最后一项才停用聚合扩展。源码、用户工程、SDK、模拟器、业务数据和既有业务配置保留；安装与卸载只管理菜单，不执行菜单业务。操作完成后刷新 Finder，请先结束 Finder 文件搬移。

诊断保留在终端；聚合工程的构建、配置与登记边界见包说明。

也可从 [总管理面板](../【MacOS】🧩管理Finder扩展.command) 选择一个或多个功能，在同一面板切换安装 / 更新或卸载。

## 三、<span id="operation">操作、确认与恢复边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

点击菜单后先阅读终端内置自述并回车，之后使用 fzf 选择模式，再选目标；回车选择，`←` 返回上一层，`Esc` 或空选取消。缺少 fzf 明确停止，不退回数字输入。`Ctrl+C` 随时终止。

从本目录直接运行完整业务：

```shell
/bin/zsh ./Scripts/RollbackGitRepository.zsh \
  '../../目标项目'
```

可附加 `--upstream refs/remotes/远端/分支` 明确本地快照。默认使用当前分支已配置 upstream；没有配置远端时才尝试 `origin/当前分支`，游离 HEAD 不能选择 upstream。所选快照之间不同会列出让用户明确选择，不自动切换到某条线路；所有回退不联网、不提交、不推送。

soft 只移动 HEAD，保留索引和工作区；空提交或净差异抵消时没有待提交文件属于正常情况。hard 会丢失已跟踪的暂存和未暂存改动，并可能删除挡住目标已跟踪路径的未跟踪内容。**hard 前自行另存重要文件**；本工具不创建完整文件备份。未挡路的未跟踪文件通常保留，不额外执行 clean，不递归 reset 子模块。

父仓的 gitlink 变化不等于子仓源码被回退；本次只操作选定工作树，不修改父仓暂存区。未解决冲突、merge/rebase/cherry-pick 等未完成事务或 index 锁会停止；选择或确认期间仓库、分支、HEAD、远端快照以及 hard 的索引/工作区变化也会停止。执行期间避免其它 Git 客户端或编辑器并发写入。

日志位于系统临时目录，每次按 `RollbackGitRepository.时间.进程号.log` 独立保存。成功结果包含固定目标提交。需要恢复历史时，先另存当前文件，再检查 Git reflog；reflog 能找回提交位置，不能保证找回被 hard 丢弃且从未提交的文件内容。

## 四、<span id="files-tests">实现与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `JobsGitRollbackShared/`：Git 目录验证和严格 URL 数据传递；不在 Finder 回调中调用 Shell。
- `JobsGitRollback/`：后台宿主和 Terminal 私有载体。路径按数据传递，单行命令支持中文、空格、引号和控制字符；临时目录 `0700`，载体与完整业务副本 `0600`，结束保留退出码并精确清理。
- `JobsGitRollbackFinderSync/`：独立工程的备用 Finder 实现，普通安装使用统一包。
- [Scripts](./Scripts/README.md)：随 App 打包的完整回退核心与构建登记脚本；运行不依赖 SourceTree 目录。
- `Tests/`：临时仓库业务回归及 Swift 传输回归，不操作真实仓库或启动 Terminal。

源码语法、临时仓库 soft/hard 门禁与范围、Git 元数据过滤、实际工作树身份、特殊路径、URL 和载体清理可隔离验证。身份回归包含 `core.worktree` 改绑拒绝、有效子目录、嵌套仓库、真实 linked worktree 与继承环境隔离。真实安装后的系统菜单与实际业务分别验收，构建通过不能替代 Finder 菜单验收。

上述隔离验证、统一包本机原路径构建与深度签名均已通过，统一扩展已启用且保留原有功能选择。已在真实 Finder 核对 `JobsGenesis` 大 Git 根文件夹与 `MacOS@Extension` 子 Git 文件夹，两处均显示“Git操作 → Git 提交回退”；未对用户仓库执行真实回退。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
