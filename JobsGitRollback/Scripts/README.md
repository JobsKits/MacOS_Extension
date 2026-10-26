# `JobsGitRollback/Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、脚本与边界](#jobs-toc-heading-2)
- [二、隔离检查](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录包含完整 Git 提交回退核心和独立调试工程的构建后登记脚本，归 [MacOS@Extension](../../README.md) 管理。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、脚本与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[RollbackGitRepository.zsh](./RollbackGitRepository.zsh) 是用户指定 SourceTree 同名业务的完整打包副本，常规 Finder 入口在交互终端展示自述、回车后选择六种 soft / hard 模式。历史、tag 和 reflog 使用固定提交号；hard 必须精确 `YES`。工作树、索引、子模块与恢复限制见[功能说明](../README.md#operation)。该脚本运行不读取 SourceTree 文件或外部 README，不自动安装 Git / fzf。

[EnableFinderExtension.zsh](./EnableFinderExtension.zsh) 只在本独立工程构建上下文登记和启用对应扩展，可能刷新 Finder；普通安装使用 JobsProjectTools。隔离构建需设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过注册，不能用真实注册流程代替语法测试。登记日志位于系统临时目录中的 `JobsGitRollbackBuildPhase.log`。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、隔离检查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```shell
zsh -n ./RollbackGitRepository.zsh
zsh -n ./EnableFinderExtension.zsh
ruby ../Tests/GitRollbackCommandTests.rb
```

业务回归只在临时仓库中执行回退。Swift 回归将 `GitRollbackMenuContext.swift`、`GitRollbackRequest.swift`、`GitRollbackTerminalLauncher.swift` 和 `Tests/GitRollbackTransportTests.swift` 一起编译后运行；它不启动 Terminal、不修改真实仓库。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
