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

本目录归 [MacOS@Extension](../README.md) 统一管理，无独立 Git 仓库。菜单由 [JobsProjectTools](../JobsProjectTools/README.md) 聚合，本目录两个入口只启停 `git-rollback` 单项；Windows 对应包见[双端目录](../../WindowsOS@Extension/JobsGitRollback/README.md)。

| 模式 | 目标与效果 |
| --- | --- |
| soft 回退到 upstream | 使用本地远端跟踪快照，撤回目标之后的本地提交，保留索引和工作区。多条快照可明确选择；没有自动 fetch。 |
| 选择提交 soft 回退 | 从最多 200 条本地历史记录中选择完整提交号；目标必须是当前 HEAD 的祖先。 |
| hard 回退到 upstream | 将当前工作树重置到选定快照；列出仓库和固定提交号，精确输入 `YES` 才执行。 |
| 选择提交 hard 回退 | 从最多 200 条历史中选择目标，`YES` 确认后舍弃当前已跟踪改动。 |
| 选择 tag hard 回退 | 按创建时间选择 tag，以完整 `refs/tags/` 解析固定提交，`YES` 后执行。 |
| 选择 reflog hard 回退 | 从最多 200 条 reflog 记录中选择固定提交，`YES` 后执行。 |

## 一、<span id="menu-scope">菜单范围与工作树识别</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 单选 Git 工作树普通文件夹，或者在该目录空白处右键显示；普通子目录映射到其最近的所属仓库。
- 子模块、嵌套独立 Git 和 linked worktree 均处理其自身工作树，不把请求误交外层父仓。
- 普通非 Git 目录、裸仓库、`.git` 元数据、文件、符号链接、应用包、多选和桌面空白处隐藏。损坏的内层 `.git` 不借外层有效仓库通过。
- 菜单显示与点击再次只读检查元数据，终端中由 Git 再确认实际工作树、HEAD 与事务状态。尚无提交的仓库会显示入口，但终端明确停止；菜单可见不代表已经执行回退。
- 后台宿主与 Terminal 载体执行业务前，分别用 Git 只读核对实际工作树根和 Git 元数据目录，必须对应最近 `.git`。`core.worktree` 指向兄弟目录或派发后绑定改变时停止，避免回退其它工作树。继承的 Git 定位和临时配置变量仅在子进程中隔离，用户环境和持久配置不变。

## 二、<span id="install">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

双击[安装入口](./【MacOS】安装Git提交回退Finder扩展.command)启用统一菜单里的本项；[卸载入口](./【MacOS】卸载Git提交回退Finder扩展.command)仅关闭本项。也可在[总安装面板](../【MacOS】🧩安装Finder扩展.command)勾选。请保留完整 `MacOS@Extension` 目录，不能只带走本功能目录。

转发入口复用统一安装器内置自述和确认。统一包保留其它已启用项目；最后一项关闭才停用整个统一扩展。安装、卸载均不对任何目标仓库执行 reset。产物与日志位置、扩展登记及 Finder 刷新见[统一包说明](../JobsProjectTools/README.md)的“安装与逐项启停”。本目录的 Xcode 工程可独立构建供调试；正常安装使用统一包，避免重复“Git操作”菜单。

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
