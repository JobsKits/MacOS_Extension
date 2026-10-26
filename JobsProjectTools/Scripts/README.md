# `JobsProjectTools Scripts`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、输入与调用](#jobs-toc-heading-2)
- [二、功能与输出](#jobs-toc-heading-3)
- [三、依赖、副作用与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ManageProjectTools.zsh](./ManageProjectTools.zsh) 由上级成对安装 / 卸载入口调用，负责九项 IDE / Git 功能的统一构建、注册与逐项状态管理；三个 IDE 保留一级入口，Git 六项集中在“Git操作”子菜单。本脚本不是 Finder 点击后的任意命令执行器。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、输入与调用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

第一个参数必须为 `install` 或 `uninstall`，后面至少一个功能 ID：`android_studio_opener`、`vscode_opener`、`xcode_opener`、`git-pull`、`git-rollback`、`git_remote`、`git_remote_copier`、`git-proxy-configure`、`git_empty_commit_push`；未知 ID 停止。用户使用[功能 README 中的上级入口](../README.md)完成阅读与回车确认，内部脚本不再重复询问。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、功能与输出 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 安装读取已有功能状态；首次无配置时也保留已启用的对应单项，合并指定选择。
- Git 归并独立迁移一次：只读取明确启用的旧动态代理及 Terminal 空白提交选择，成功保存后记录迁移标记，后续安装不重新打开已关闭项。旧代理扩展停用后不再保留桌面独立菜单，但用户业务配置和快照继续保留。
- 提交回退菜单独立迁移一次：只合并系统明确启用的旧 `JobsGitRollback` 扩展；统一扩展成功后精确停用旧回退宿主和扩展，后续安装不重新打开已关闭项。
- 使用完整 Xcode 构建到上级 `./work/DerivedData/`，注册并等待当前精确扩展路径启用成功，再原子保存 `EnabledFeatures.txt`，停用对应独立扩展。
- 卸载只删选择的功能配置与启用状态；最后一项关闭后注销统一扩展，保留源码和构建缓存。
- 配置在当前用户 Application Support 的 JobsProjectTools 目录中；两种模式最后刷新 Finder。终端显示状态与错误，没有单独业务日志文件。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、依赖、副作用与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

需要 macOS、系统 zsh、完整 Xcode / macOS SDK、PlugInKit、LaunchServices 与可用签名；不安装这些依赖。安装和卸载会停止本功能宿主 / 扩展，写用户配置和系统登记并刷新 Finder。构建或启用验证失败时停止，不先关闭仍可用的独立菜单；不执行 Git 回退、拉取、提交、推送、代理配置或打开 IDE。

本目录属于 [JobsProjectTools](../README.md) 的普通源码目录，无独立 Git。安装、迁移与卸载使用隔离替身验证；没有修改真实用户配置、登记扩展或刷新 Finder。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
