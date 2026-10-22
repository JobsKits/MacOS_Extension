# [**Git**](https://git-scm.com/) 动态代理桌面入口脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与验证](#run)
- [二、日志与卸载边界](#logging)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录由 Jobs 维护，只服务 [JobsGitProxyConfigurator](../README.md)。**扩展安装与用户 Git 配置是两层独立动作**：前者注册菜单，后者必须在 [**Terminal**](https://support.apple.com/guide/terminal/welcome/mac) 由用户确认。

| 文件 | 职责与边界 |
| --- | --- |
| [ConfigureGitDynamicProxy.command](./ConfigureGitDynamicProxy.command) | 完整自包含的规范源副本，随 App 打包；无参数保留回车安装、C 检查、R 恢复，`--check` 只读。菜单不会传入 `--install` 绕过确认。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | [**Xcode**](https://developer.apple.com/xcode/) 构建后可注册、启用本扩展并刷新 [**Finder**](https://support.apple.com/guide/mac-help/welcome/mac)；外层安装器或隔离构建通过 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过。该开关只控制本脚本，Xcode 仍可能通过自带步骤登记宿主 URL。 |

业务副本与[独立入口](../../../../JobsCommand@Gits/【MacOS】🌐双击配置Git动态代理.command/README.md)保持整文件字节一致。宿主把资源复制到独立私有临时目录，再通过安全单行命令交给 Terminal；不从源仓库路径运行，不接受外部脚本或路径参数。临时副本完成后清理，用户安装生成的 Git 入口和快照保留。

## 一、<span id="run">运行与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录手动使用业务副本：

```shell
/bin/zsh ./ConfigureGitDynamicProxy.command
/bin/zsh ./ConfigureGitDynamicProxy.command --check
```

默认入口必须有可交互终端。`--install` 是独立脚本提供的明确无交互安装授权，**桌面右键不使用该参数**；R / `--restore` 按精确快照恢复，遇到后续冲突停止。业务影响范围和日志详见完整脚本的运行时自述。

从工程目录运行隔离回归：

```shell
/bin/zsh ../Tests/run.zsh
```

测试验证资源一致性、固定 URL、真实 Home/Desktop、普通目录与选中项拒绝、两种 URL 回调去重、Shell 特殊字符往返、私有文件权限、标准退出码与清理，以及固定 Bundle ID 注册与卸载。系统注册、Terminal 和 Finder 刷新使用替身，不动真实 Git 配置。

## 二、<span id="logging">日志与卸载边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

构建后启用日志是系统临时目录中的 `JobsGitProxyConfiguratorBuildPhase.log`；宿主派发日志是 `JobsGitProxyConfigurator.log`。用户 Git 配置快照与脱敏审计由完整业务脚本保存在用户 Application Support 的专用目录。菜单卸载只移除固定扩展和核验 App，不能删除业务配置或代替业务恢复。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
