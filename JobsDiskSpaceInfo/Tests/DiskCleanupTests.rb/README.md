# DiskCleanupTests：隔离清理回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、运行](#run)
- [二、验证范围](#coverage)

</details>
<!-- jobs-toc:end -->

---

## 一、<span id="run">运行</span>

在本目录运行：

```shell
ruby ./DiskCleanupTests.rb
```

仅使用临时 HOME、临时文件与命令替身；不执行真实主 clean，不读取／删除用户真实缓存，不调用真实 simctl、Homebrew、Spotlight 或 LaunchServices 清理。

## 二、<span id="coverage">验证范围</span>

覆盖只读帮助／非交互拒绝、PTY 中仅空回车确认、非空／空格取消门禁、历史与缓存链接保护、隐藏项和特殊字符路径、用户目录外与父级链接构建 App 保留、原六类不越界清理 Developer 中 Xcode roots、模拟器查询取消传播。失败重试使用真实 PTY 配合命令替身，覆盖回车多轮缩减失败队列、成功步骤不重跑、非空／空格停止、EOF与无终端取消、取消码传递及重试 App 变更后的列表刷新；缓存夹具核对新生成／同名重建项保留、原失败候选替换保护，以及首次枚举失败后不扩大清单。源码加载时去除唯一主入口，测试不提供可在生产中绕过确认的运行参数。

底层命令诊断使用只输出 `Permission denied`／`Resource busy` 的命令替身，核对终端和日志均有具体原因、失败与取消退出码不会被日志转发覆盖、成功无新增错误，以及重试仅追加当前尝试而不回放旧日志；同时检查日志函数执行后计数、数组和清理状态仍留在当前 Shell。缓存删除夹具额外核对真实业务入口能显示并记录替身报错；机器输出用例核对 stderr 诊断不污染 JSON／NUL 快照，Xcode 日志增量及阶段接线用例核对失败／取消 action 只显示本次新增内容且不重复落盘。

同一日志文件同时承接 stdout／stderr 时，核对两个命令诊断入口及原生日志函数不会重复写入；彩色文本落盘去除控制码，无尾换行的命令输出保持原状。

初始化夹具保留真实 `mktemp`，仅写私有临时目录；核对确认前不建日志、宽松父进程 umask 下日志仍为 `0600`、先后与并发运行不覆盖日志、旧模板同名文件／链接保持原样，以及临时目录不可用时报错并在常规清理之前停止。并发夹具只验证日志独立，不将锁在完整清理期间持续持有记为已验。

只运行常规重试相关用例：

```shell
ruby ./DiskCleanupTests.rb --name '/retry|failure|return_retries|successful_run/'
```

只运行底层诊断相关用例：

```shell
ruby ./DiskCleanupTests.rb --name '/logged_command|logged_external|logged_retry|cache_delete_failure_cause|logged_stderr|same_log_redirection|log_delta|xcode_failed_and_cancelled/'
```

只运行日志初始化用例：

```shell
ruby ./DiskCleanupTests.rb --name '/runtime_/'
```

诊断和失败重试筛选支持以 `JOBS_CLEAN_TEST_SCRIPT` 显式指定终端 clean 源码，核对共用行为；日志初始化筛选和完整测试仍以本目录默认的右键脚本为目标，帮助参数与日志初始化保留各自入口差异，常规确认统一为仅空回车继续、非空／输入结束取消。

测试与[脚本说明](../../Scripts/【MacOS】清理磁盘空间.command/README.md)同步；通过不代表真实磁盘清理或完整 Finder→Terminal 验收。
