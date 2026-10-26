# `JobsRunAuthorizationRevoker` 脚本说明

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件与入口](#files)
- [二、交互、结果与限制](#behavior)
- [三、依赖、日志与登记](#runtime)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录自包含“解除运行授权”的业务脚本和构建后登记脚本，由 Jobs 维护。业务只清除一个普通文件的全部执行位，安装菜单本身不修改文件权限。

## 一、<span id="files">文件与入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| [RevokeRun.zsh](./RevokeRun.zsh) | 随 App 打包，通过 Terminal 核对并确认单文件 `chmod a-x`；支持独立调用。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | 仅供有效 Xcode 构建上下文登记、启用当前精确 appex 路径并刷新 Finder。 |

从本目录调用：

```shell
/bin/zsh ./RevokeRun.zsh \
  --file "/目标目录/脚本.command"

/bin/zsh ./RevokeRun.zsh \
  --check \
  --file "/目标目录/脚本.command"

/bin/zsh ./RevokeRun.zsh --help
```

## 二、<span id="behavior">交互、结果与限制</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `--file` 后必须只有一个普通文件的绝对路径；拒绝目录、链接、多文件及额外参数。
- 自述先展示用途、路径、日志策略和影响范围，普通操作必须有可交互终端。回车继续，任意非空输入（含空格）、Ctrl+C、EOF 取消；确认前不写日志和权限。
- 以设备号 / inode 复检选择对象，确认后才创建私有日志，执行 `/bin/chmod a-x`，复读当前权限并确认所有执行位已清零；失败非零退出。
- `a-x` 显式指定所有者、组和其它用户，因此严格 `umask` 也不会留下执行位。读写位保留；不改 ACL、隔离属性和内容，不递归、不运行目标、不提权。
- 不能阻止解释器读取可读脚本，也不恢复某次授权前的完整模式。菜单对应的“运行授权”由独立包提供。
- `--check` 和 `--help` 不需要交互，不创建日志、不修改权限。只读检查显示当前权限和 `umask`。

## 三、<span id="runtime">依赖、日志与登记</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

业务只依赖系统 zsh、`stat`、`chmod`、`mktemp`，不下载组件。业务日志位于系统临时目录 `JobsRunAuthorizationRevoker.XXXXXXXX/run.log`，目录 `700`、日志 `600`，纯文本与终端同步；载体清理不删除结果日志。

登记脚本固定标识 `com.jobs.JobsRunAuthorizationRevoker.FinderSyncExtension`，日志 `JobsRunAuthorizationRevokerBuildPhase.log` 与重试标记 `JobsRunAuthorizationRevokerNeedsFinderRestart` 均在系统临时目录。它要求当前 App 的真实构建上下文；不能当作手动安装入口。隔离构建设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过它，但仍需单独检查 Xcode 自动登记。

完整安装 / 卸载入口位于[工程根目录](../README.md#installation)。用 `zsh -n` 做语法检查，临时文件 / 菜单 / 注册替身回归在 `../Tests/`；真实菜单与 Terminal 首次自动化权限需安装后另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
