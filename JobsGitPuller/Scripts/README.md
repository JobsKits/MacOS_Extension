# `JobsGitPuller/Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、脚本用途](#jobs-toc-heading-2)
  - [PullGitRepository.zsh](#jobs-toc-heading-3)
  - [EnableFinderExtension.zsh](#jobs-toc-heading-4)
- [二、验证](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录包含 [**Git**](https://git-scm.com/) 拉取业务与 [**Finder**](https://support.apple.com/zh-cn/102339) 扩展构建后注册脚本，随本工程归 MacOS@Extension 统一管理，无独立 Git 根。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、脚本用途 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-3" data-jobs-toc="v2">[PullGitRepository.zsh](./PullGitRepository.zsh)</span><!-- jobs-toc:heading-end -->

> **目的：** 拉取所属工作树当前分支的 upstream，保护本地状态并处理冲突。

- 在交互终端接收一个文件夹参数；无参数使用当前目录。非 Git 目录静默退出。
- 自述和未提交内容确认通过后，显示实际来源并 fetch，再保存 HEAD / stash 快照。
- 合并并恢复改动；冲突提供回滚、`YES` 放弃、输入信息提交后三项处理，空 commit 信息允许直接回车。
- 操作范围、恢复锚点、日志和中断处理见[工程说明](../README.md#safety)。

### <span id="jobs-toc-heading-4" data-jobs-toc="v2">[EnableFinderExtension.zsh](./EnableFinderExtension.zsh)</span><!-- jobs-toc:heading-end -->

> **目的：** 在本工程 Xcode Build Phase 注册并启用构建出的扩展。

- 展示固定自述，检查本工程构建上下文。
- `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 时跳过注册；父安装器和隔离验证使用该开关。
- 正常构建时调用系统注册工具并刷新 Finder；该脚本不执行 Git 拉取。构建日志位于系统临时目录中的 `JobsGitPullerBuildPhase.log`。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">二、验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从本目录运行语法检查：

```shell
zsh -n ./PullGitRepository.zsh
zsh -n ./EnableFinderExtension.zsh
ruby ../Tests/GitPullCommandTests.rb
```

业务仅依赖原生 zsh、系统工具和健康 Git，不自动安装依赖或改写全局配置。真实安装使用[工程安装入口](../README.md#install)，不要用完整注册流程代替语法测试。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
