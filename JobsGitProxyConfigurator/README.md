# `JobsGitProxyConfigurator` 配置 [**Git**](https://git-scm.com/) 动态代理

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、安装与卸载](#install)
- [二、配置流程与恢复范围](#usage)
- [三、标识与结构](#structure)
- [四、验证与排查](#verify)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**系统桌面空白处右键 → 配置 Git 动态代理 → 终端交互。** 在 [**Terminal**](https://support.apple.com/guide/terminal/welcome/mac) 中回车安装、输入 C 检查或输入 R 恢复。本模块由 Jobs 维护，包含独立 App、[**Finder Sync**](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html) 扩展与完整业务脚本，不依赖原脚本仓库仍在本机。核对日期：**2026-10-22**。

| 操作 | 实际行为 |
| --- | --- |
| 安装本 Finder 扩展 | 构建并注册桌面菜单，打开宿主完成扩展初始化；不运行 Git 配置脚本。 |
| 系统桌面空白右键 | 显示“配置 Git 动态代理”，点击后在 Terminal 进入完整脚本交互。 |
| 普通文件夹背景、选中文件或目录 | 不显示本菜单；点击时再次验证桌面背景上下文。 |
| Terminal 直接回车 | 安装用户级动态 Git 入口；已启用且可达的系统代理优先，不可用时探测直连。 |
| Terminal 输入 C / R | C 只读检查；R 确认后按快照恢复。 |
| 卸载本 Finder 扩展 | 移除菜单与核验过的 App，保留已安装的 Git 配置及其恢复快照。 |

业务规范源是[独立双击脚本](../../../JobsCommand@Gits/【MacOS】🌐双击配置Git动态代理.command/README.md)。完整自包含副本位于 [Scripts/ConfigureGitDynamicProxy.command](./Scripts/ConfigureGitDynamicProxy.command)，随 App 资源打包；回归在规范源可用时通过 `cmp` 对账整文件。复制本模块到其它目录后仍可独立构建和运行。

## 一、<span id="install">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

两个裸露入口与本 README 平级：

- [【MacOS】安装Git动态代理Finder扩展.command](./【MacOS】安装Git动态代理Finder扩展.command)：显示源码、产物、范围和日志后，**直接回车安装；任意非空输入跳过**。要求完整 [**Xcode**](https://developer.apple.com/xcode/)、[**macOS**](https://www.apple.com/macos/) SDK 和系统 `pluginkit`；不自动安装或升级工具。
- [【MacOS】卸载Git动态代理Finder扩展.command](./【MacOS】卸载Git动态代理Finder扩展.command)：先回车查看注册路径，再输入精确 `YES`，仅注销固定 Bundle ID 并删除身份匹配的 App。用户的 Git 动态入口、Shell 挂载、Sourcetree 选择和快照保留。

总入口或明确授权的命令行可使用：

```shell
/bin/zsh ./【MacOS】安装Git动态代理Finder扩展.command --install --skip-finder-restart
/bin/zsh ./【MacOS】卸载Git动态代理Finder扩展.command --uninstall --skip-finder-restart
```

两个显式动作参数代表同范围无交互授权；`--skip-finder-restart` 或 `JOBS_SKIP_FINDER_RESTART=1` 将 Finder 刷新交给调用方。默认独立安装 / 卸载会刷新 Finder；多功能安装应由总入口统一刷新。宿主的 `--initialize-finder-extension` 只初始化菜单，不打开配置终端，也不自行重启 Finder。

独立安装产物位于 `./work/DerivedData/Build/Products/Debug/JobsGitProxyConfigurator.app`；总入口使用父仓 `work/JobsGitProxyConfiguratorDerivedData/`。系统直接从登记位置启动 App 和 appex，使用期间保留产物目录；两种方式使用同一 Bundle ID，不维持多份有效注册副本。

## 二、<span id="usage">配置流程与恢复范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

右键只转交固定动作，不能携带任意脚本、命令、路径或参数。后台宿主同次运行只接受一次有效请求；两个系统 URL 回调交错或重入时也不会重复打开 Terminal。业务复制到权限 `0700` 的本次私有目录，以 `0600` 文件执行；退出后精确清理。

Terminal 中保留独立脚本的所有安装、C 检查与 R 恢复交互。安装只管理用户 Application Support 中的专用 `JobsGitNetworkStrategy/runtime/bin/git`、用户 `.zshrc` 末尾受控 PATH 块和已安装 [**Sourcetree**](https://www.sourcetreeapp.com/) 的两个 Git 选择键。不会修改 `.gitconfig`、系统代理、VPN、项目远端或提交。

动态入口默认系统代理优先，关闭 VPN 或所有代理候选不可达时短探测直连；HTTP(S) `clone`、`fetch`、`pull`、`ls-remote`、`push` 选路后原始 Git 命令最多执行一次。显式代理、空代理和旁路规则保留；递归或多目标的保守边界、超时与证书处理沿用完整业务脚本的说明。

业务审计与私有快照保存在用户 Application Support 的 `JobsGitNetworkStrategy/installer` 下；R 恢复只撤回本次受控项，保留后续无关 Shell 编辑，遇到运行文件、挂载或偏好冲突时停止。升级后可恢复到上一版，重复恢复不会继续卸载更早版本。**卸载菜单不等于恢复 Git 配置**；恢复应在卸载前从桌面菜单进入 R，或直接运行完整业务副本选择 R。

## 三、<span id="structure">标识与结构</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 标识 | 值 |
| --- | --- |
| 工程 / Scheme / App | `JobsGitProxyConfigurator` |
| Finder 扩展 | `JobsGitProxyFinderSync.appex` |
| 宿主 Bundle ID | `com.jobs.gitproxyconfigurator` |
| 扩展 Bundle ID | `com.jobs.gitproxyconfigurator.findersync` |
| 总安装面板功能 ID | `git-proxy-configure` |
| 固定请求 | `jobsgitproxyconfigurator://git/configure` |

```text
./
├── JobsGitProxyConfigurator.xcodeproj/
├── JobsGitProxyConfigurator/          # 后台宿主与单次 Terminal 派发
├── JobsGitProxyFinderSync/            # 仅桌面背景菜单
├── JobsGitProxyShared/                # 固定请求与真实桌面白名单
├── Scripts/                          # 完整业务副本与构建后启用脚本
├── Tests/                            # 隔离原生协议、派发与注册回归
├── 【MacOS】安装Git动态代理Finder扩展.command
└── 【MacOS】卸载Git动态代理Finder扩展.command
```

桌面定位复用已验收的目录服务方案：`getpwuid_r(getuid())` 获取真实 Home/Desktop，保留系统桌面别名；监控根目录 `/` 以收到真实桌面回调，菜单按规范化路径白名单严格过滤，不依赖沙盒中的桌面元数据读取成功。Finder Sync 注册机制见 [**Apple 文档**](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html)。

## 四、<span id="verify">验证与排查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

隔离回归不打开 Terminal、不注册扩展、不刷新 Finder，也不安装真实 Git 配置：

```shell
/bin/zsh ./Tests/run.zsh
```

仅构建并跳过自定义构建后启用：

```shell
JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 xcodebuild \
  -project ./JobsGitProxyConfigurator.xcodeproj \
  -scheme JobsGitProxyConfigurator \
  -configuration Debug \
  -derivedDataPath ./work/VerificationDerivedData \
  build
```

该开关阻止本工程的 `pluginkit` 启用与 Finder 刷新，**不保证 Xcode 自带的 Launch Services 宿主登记被跳过**。本机完整构建实测即使传入 `REGISTER_APP_WITH_LAUNCH_SERVICES=NO`，Xcode 仍执行该登记步骤；隔离验证后只可精确注销确认由验证新增的宿主路径，不清理其它安装副本。

2026-10-22 隔离验证：原生协议、桌面路径与私有载体 **67 条断言**，真实 AppDelegate 单次派发 **26 条断言**，安装 / 卸载命令替身 **12 项 / 76 条断言**全部通过；包内业务资源与独立规范源逐字节一致。arm64 Debug 双 target 构建、App 深度严格签名和实际打包资源字节检查通过。上述结果不表示已安装真实用户 Git 配置。

菜单安装日志为系统临时目录中的 `JobsGitProxyConfiguratorInstall.log`，卸载日志为 `【MacOS】卸载Git动态代理Finder扩展.log`，宿主派发日志为 `JobsGitProxyConfigurator.log`，构建后启用日志为 `JobsGitProxyConfiguratorBuildPhase.log`。业务脚本另有自己的私有安装审计和 Git 选路日志，不把凭据写入菜单日志。

- 菜单没出现：确认当前是真实系统桌面空白处，在系统设置中启用该 Finder 扩展，检查登记产物仍存在，再重新打开右键菜单。
- 普通目录看不到：这是桌面专用入口，不在普通目录背景或选中项目菜单显示。
- Terminal 未打开：在系统设置“隐私与安全性 → 自动化”允许宿主控制 Terminal；不自动改 TCC 数据库。
- 安装菜单后 Git 尚未变化：菜单安装只注册入口，必须点击菜单并在 Terminal 确认业务安装。
- Sourcetree 正在运行：业务脚本不会杀进程或重启应用；保存工作后自行重启并使用 C 检查结果。
- 未运行真实业务：编译、签名和隔离回归不能代替目标机器的 Finder 菜单与 Terminal 自动化授权验收；本模块不会为验证静默安装或恢复 Git 配置。

脚本职责与开发边界见 [Scripts/README.md](./Scripts/README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
