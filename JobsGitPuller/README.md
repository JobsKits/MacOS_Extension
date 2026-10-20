# `JobsGitPuller`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装与运行](#install)
  - [【MacOS】安装Git拉取Finder扩展.command](#jobs-toc-heading-3)
  - [【MacOS】卸载Git拉取Finder扩展.command](#jobs-toc-heading-4)
  - [PullGitRepository.zsh](#jobs-toc-heading-5)
- [二、工作区与恢复边界](#safety)
- [三、目录与验证](#files-tests)

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

本工程是 [MacOS@Extension](../README.md) 中的普通源码目录，源码、文档与版本由总仓统一管理。取得总仓即可获得本工程，无需单独远端或子模块下载；工程仍可独立构建、安装与卸载。Windows 对应独立包位于[平行仓库](../../WindowsOS@Extension/JobsGitPuller/README.md)，两端均独立安装。

本地文档保留 `[toc]`，由总仓根目录的 [目录过滤器](../.jobs-markdown-toc/README.md) 统一管理；新克隆后在总仓根目录安装一次，整文件暂存时生成远端折叠目录。

## 一、<span id="install">安装与运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

要求 macOS 12+、[**Xcode**](https://developer.apple.com/xcode/) 和健康 Git。已有 Git 直接复用，不安装依赖，不改变网络代理、全局 Git 配置或分支 upstream。分支没有 upstream、游离 HEAD、尚无提交、稀疏检出、特殊索引、已有 merge / rebase 等事务时停止。

### <span id="jobs-toc-heading-3" data-jobs-toc="v2">[【MacOS】安装Git拉取Finder扩展.command](./【MacOS】安装Git拉取Finder扩展.command/【MacOS】安装Git拉取Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 构建并注册本项 Finder 扩展。

- 阅读自述并回车，核对 Xcode 工具与本工程。
- 构建独立 App，注册并启用扩展，刷新 Finder；安装过程不会拉取任何目标仓库。
- 回到 Finder，单选文件夹或右键目录背景，点击“拉取 Git 到最新”。也可使用[总仓统一安装器](../【MacOS】🧩安装Finder扩展.command)仅勾选本项。

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">[【MacOS】卸载Git拉取Finder扩展.command](./【MacOS】卸载Git拉取Finder扩展.command/【MacOS】卸载Git拉取Finder扩展.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 停用并注销本项扩展，清理本工程安装产物。

- 阅读自述并回车确认，停止本项宿主和扩展。
- 注销并清理构建产物，刷新 Finder；不删除源码、目标项目或目标仓库的恢复快照。

### <span id="jobs-toc-heading-5" data-jobs-toc="v2">[PullGitRepository.zsh](./Scripts/PullGitRepository.zsh)</span><!-- jobs-toc:heading-end -->

> **目的：** 在交互终端执行 Git 保护、拉取和冲突三选一。

- 自述回车后检查分支和 upstream；非 Git 目录不写日志、不修改文件。
- 未提交内容另行回车确认，展示脱敏来源，先 fetch 成功，再保存 HEAD 和含未跟踪文件的 stash 快照。
- 合并本次取得的固定上游提交，恢复本地改动；合并或改动恢复冲突时进入三选一。
- 原有 stash 不删除，快照与恢复说明保留；成功核对上游提交确实已成为 HEAD 的祖先。

在本目录执行：

```shell
/bin/zsh ./Scripts/PullGitRepository.zsh \
  '/实际/项目目录'
```

## 二、<span id="safety">工作区与恢复边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 仅当前工作树，当前分支配置的单个远端 upstream；子目录会显示所属仓库根。保留本地提交，不强制对齐远端，不 push、不自动选择其他 remote。
- 不递归更新子模块。存在子模块脏状态或检出变化时先停止；远端修改 gitlink 后，子模块实际检出仍保持原样，需要单独同步。
- 快照包含 tracked 的暂存 / 未暂存状态及非 ignored 的 untracked。ignored 内容、嵌套独立仓库和子模块内容不属于“放弃”的范围；发现未忽略的嵌套仓库会停止。合并明确禁止覆盖 ignored 文件。
- 冲突菜单的 `2` 必须精确输入 `YES`。初始改动仍保留在恢复引用中；菜单里的“放弃”表示不再恢复到当前工作区。三项都不自动改写已有本地历史。
- 操作期间停止其它 Git 客户端、文件编辑及后台生成任务。本工具对共用 Git 元数据加锁，并在等待输入后复检状态；检测到变化会保留现场。该锁无法阻止外部 Git 客户端。
- `Ctrl+C` / 信号中断保留现场和恢复引用，不冒险自动 reset。按终端显示的 `recovery.txt` 检查、另存新增内容后人工恢复；确认旧进程结束后才处理遗留锁。
- 标准 Git hooks、签名与提交身份仍然生效。第三项提交失败时保留文件和快照，不继续拉取。它提交原有全部非忽略改动，不只提交原暂存内容。

每次日志与 `recovery.txt` 保存于当前工作树实际 Git 元数据目录的 `jobs-git-pull/<运行编号>/`。`refs/jobs-git-pull/<运行编号>/head` 保存原 HEAD，`snapshot` 保存原 stash，`upstream` 保存本次远端提交，`committed`（若有）保存第三项新提交。链接工作树的锁使用共用 Git 目录；快照不自动过期，确认不再需要后由使用者处理。

Git 官方说明提醒：带未提交改动直接 merge 后，abort 未必能恢复，因此这里先创建 stash 再合并；恢复使用 `apply --index`，不 pop / drop 既有 stash。参见 [merge 文档](https://git-scm.com/docs/git-merge)、[stash 文档](https://git-scm.com/docs/git-stash)。

## 三、<span id="files-tests">目录与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

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
