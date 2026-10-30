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

**有效 Git 文件夹右键 → Git操作 → 配置 Git 动态代理 → 终端交互。** 在 [**Terminal**](https://support.apple.com/guide/terminal/welcome/mac) 中回车安装、输入 C 检查或输入 R 恢复。常规菜单由 [JobsProjectTools](../JobsProjectTools/README.md) 提供；本目录由 Jobs 维护，保留旧独立 App、[**Finder Sync**](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html) 扩展与完整业务脚本。管理入口只转交统一包的代理单项，需保留完整仓库；旧桌面代理菜单迁移后停用。

| 操作 | 实际行为 |
| --- | --- |
| 安装本菜单 | 构建并注册统一项目工具包，启用代理单项；不运行 Git 配置脚本。 |
| Git 普通文件夹 / 内部空白处右键 | 在“Git操作”子菜单显示本项，点击后在 Terminal 进入完整脚本交互。支持有效仓库根、子目录、worktree 与子模块。 |
| 普通非 Git 目录、文件、多选或系统桌面空白 | 隐藏 Git 子菜单；点击与宿主派发时再次核验目标。 |
| Terminal 直接回车 | 安装用户级动态 Git 入口；已启用且可达的系统代理优先，不可用时探测直连。 |
| Terminal 输入 C / R | C 只读检查；R 确认后按快照恢复。 |
| 卸载本菜单 | 关闭统一包代理单项，保留其它功能、已安装的 Git 配置及恢复快照。 |

业务规范源是[独立双击脚本](../../../JobsCommand@Gits/MacOS/【MacOS】🌐双击配置Git动态代理.command/README.md)。完整自包含副本位于 [Scripts/ConfigureGitDynamicProxy.command](./Scripts/ConfigureGitDynamicProxy.command)，随统一 App 资源打包；回归在规范源可用时通过 `cmp` 对账整文件。菜单运行只读取已打包资源，不要求原脚本仓库仍在本机。

## 一、<span id="install">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

菜单安装与卸载统一使用 [图形管理入口](./【MacOS】管理Git动态代理Finder扩展.app)。直接打开面板，选择“安装 / 更新”或“卸载”并勾选当前范围内的功能；默认空选，点击操作按钮即确认。每项显示等待、正在安装 / 卸载、成功或失败；底部日志实时滚动，可选择复制或复制全部。运行中锁定选择和关闭入口，结束后保留结果与日志。首次打开或面板源码更新后会在后台编译，失败以桌面提示和启动日志说明。

原同名 `.command` 入口保留，终端只负责唤起独立 GUI，随后结束启动脚本；本次启动任务结束后自动关闭对应终端页，安装 / 卸载、进度与实时日志均由 GUI 后台处理。已有交互 Shell 中手工调用时保留原工作会话。内部实现为 `Scripts/ManageExtension.zsh`；完整仓内单功能入口使用总面板的受限范围。可独立复制的包须整体保留 `.command`、`.app`、Scripts、工程源码和资源。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

本入口转交 [JobsProjectTools](../JobsProjectTools/README.md)，只管理 `git-proxy-configure`，需要保留同仓聚合工程源码。旧宿主、扩展与 Xcode 工程仍供实现参考和隔离验证；常规菜单安装不再注册本目录的旧独立扩展。

需要 macOS 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 与 macOS SDK。安装成功后启用本入口对应功能并保留其它已装选择；卸载仅减去对应功能，仍有其它项时保留共享 App 和登记，最后一项才停用聚合扩展。源码、用户工程、SDK、模拟器、业务数据和既有业务配置保留；安装与卸载只管理菜单，不执行菜单业务。操作完成后刷新 Finder，请先结束 Finder 文件搬移。

诊断保留在终端；聚合工程的构建、配置与登记边界见包说明。

也可从 [总管理面板](../【MacOS】🧩管理Finder扩展.command) 选择一个或多个功能，在同一面板切换安装 / 更新或卸载。

## 二、<span id="usage">配置流程与恢复范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

右键只转交固定动作，不能携带任意脚本、命令、路径或参数。后台宿主同次运行只接受一次有效请求；两个系统 URL 回调交错或重入时也不会重复打开 Terminal。业务复制到权限 `0700` 的本次私有目录，以 `0600` 文件执行；退出后精确清理。

Terminal 中保留独立脚本的所有安装、C 检查与 R 恢复交互。安装只管理用户 Application Support 中的专用 `JobsGitNetworkStrategy/runtime/bin/git`、用户 `.zshrc` 末尾受控 PATH 块和已安装 [**Sourcetree**](https://www.sourcetreeapp.com/) 的两个 Git 选择键。不会修改 `.gitconfig`、系统代理、VPN、项目远端或提交。

动态入口默认系统代理优先，关闭 VPN 或所有代理候选不可达时短探测直连；HTTP(S) `clone`、`fetch`、`pull`、`ls-remote`、`push` 选路后原始 Git 命令最多执行一次。显式代理、空代理和旁路规则保留；递归或多目标的保守边界、超时与证书处理沿用完整业务脚本的说明。

业务审计与私有快照保存在用户 Application Support 的 `JobsGitNetworkStrategy/installer` 下；R 恢复只撤回本次受控项，保留后续无关 Shell 编辑，遇到运行文件、挂载或偏好冲突时停止。升级后可恢复到上一版，重复恢复不会继续卸载更早版本。**卸载菜单不等于恢复 Git 配置**；恢复应在卸载前从 Git 子菜单进入 R，或直接运行完整业务副本选择 R。

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
└── 【MacOS】管理Git动态代理Finder扩展.command
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

- 菜单没出现：确认目标为有效 Git 普通文件夹，已在统一包启用代理单项，并在系统设置中启用 JobsProjectTools；检查登记产物仍存在，再重新打开右键菜单。
- 普通非 Git 目录或桌面看不到：当前入口要求有效 Git 工作树，系统桌面空白不显示。
- Terminal 未打开：在系统设置“隐私与安全性 → 自动化”允许宿主控制 Terminal；不自动改 TCC 数据库。
- 安装菜单后 Git 尚未变化：菜单安装只注册入口，必须点击菜单并在 Terminal 确认业务安装。
- Sourcetree 正在运行：业务脚本不会杀进程或重启应用；保存工作后自行重启并使用 C 检查结果。
- 未运行真实业务：编译、签名和隔离回归不能代替目标机器的 Finder 菜单与 Terminal 自动化授权验收；本模块不会为验证静默安装或恢复 Git 配置。

脚本职责与开发边界见 [Scripts/README.md](./Scripts/README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
