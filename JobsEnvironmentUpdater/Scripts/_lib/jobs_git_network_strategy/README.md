# [**Git**](https://git-scm.com/) 动态网络策略

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、行为速览](#behavior)
- [二、文件职责](#layout)
- [三、代理回退流程与边界](#fallback)
- [四、部署与普通命令入口](#setup)
- [五、日志与备份](#logs)
- [六、卸载恢复与临时旁路](#restore)
- [七、隔离验证与验收范围](#validation)

</details>
<!-- jobs-toc:end -->

[行为速览](#behavior) · [接入方式](#setup) · [日志](#logs) · [恢复原状](#restore) · [验证](#validation)

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

> 为终端普通 Git 命令和 [**Sourcetree**](https://www.sourcetreeapp.com/) 的克隆、拉取、推送提供同一套网络策略：HTTP / HTTPS 的 `clone`、`fetch`、`pull`、`ls-remote`、`push` 默认优先使用当前系统中可达的代理；VPN 关闭、没有启用代理或候选代理不可达时，再短时探测直连。选定线路后，原始 Git 命令最多执行一次；实际业务失败不重放。代理地址每次按当前系统设置读取，不固定端口，也不持久写入 `http.proxy`。

## 一、<span id="behavior">行为速览</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 情况 | 实际处理 |
| --- | --- |
| 可识别的单目标 HTTP / HTTPS 网络命令，系统代理可达 | 直接选择该代理，仅为本次 Git 的目标站点注入；不先探测直连。 |
| VPN 关闭、没有启用系统代理或候选代理均不可达 | 短时探测直连；可达后按原参数执行 Git 一次。 |
| 未找到可用线路 | 返回网络失败与退出码 `128`；不先运行真实克隆或推送，不循环重试。 |
| 已设置 Git 或环境变量代理，包括显式空值 | 尊重已有选择，原样交给 Git，不自动换成系统代理。 |
| 命中 `NO_PROXY` / `no_proxy` 或系统旁路规则 | 保持直连，不强制代理；直连预检明确失败时返回 `128`。 |
| 认证、权限、非快进拒绝、分支冲突、证书错误 | 保留原始 Git 的校验与结果，不因这些错误重放命令。 |
| 代理预检遇到 TLS / 证书差异 | 选定该候选，交给原始 Git 按其 CA / 客户端证书配置验证一次；不继续换路。 |
| 显式选择 `JOBS_GIT_ROUTE_PRIORITY=direct` | 先探测直连；仅明确的 DNS / 连接故障或超时才读取当前系统代理。 |
| SSH、本地路径、未知参数、多目标或递归子模块形式，或 `status` 等本地命令 | 保守透传给原生 Git，不猜测目标或改变执行方式。 |

自动选路的直连及每个代理候选均默认连接超时 2 秒、总超时 4 秒；最多探测三个不同候选，默认完整探测预算最多约 16 秒，不含实际 Git 传输。实际传输仍沿用 Git 与既有配置的超时。探测成功仅说明目标站点可达，实际凭据、仓库权限及命令结果仍由 Git 校验。显式代理或不能可靠识别的调用保留原生行为，也保留其等待时间。

| 环境变量 | 默认值 | 允许值 |
| --- | --- | --- |
| `JOBS_GIT_ROUTE_PRIORITY` | `system` | `system` 优先系统代理、不可达再直连；`direct` 优先直连、连接失败再查代理；无效值提示后使用 `system`。 |
| `JOBS_GIT_CONNECT_TIMEOUT` | `2` 秒 | `1` 至 `60` 的整数，控制单次探测连接超时。 |
| `JOBS_GIT_PROBE_TIMEOUT` | `4` 秒 | `1` 至 `120` 的整数，控制单次探测总超时。 |

需要单次改为直连优先时，在普通终端命令前设置环境变量；不修改持久配置：

```zsh
JOBS_GIT_ROUTE_PRIORITY=direct git ls-remote 'https://github.com/JobsKits/JobsGenesis.git' HEAD
```

“代理失败再直连”指代理预检阶段没有可用候选，再选择直连；原始 Git 开始后不会因失败切换线路或重放推送。动态回退会在代理不可用时保留直连能力；如果当前网络本身无法直连 [**GitHub**](https://github.com)，又没有可用代理，模块会报告失败，不能保证关闭 VPN 后仍能访问 GitHub。

## 二、<span id="layout">文件职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
jobs_git_network_strategy/
├── README.md            # 使用、边界与恢复说明
├── bin/git              # Git 命令入口，内部固定调用 /usr/bin/git
├── 【MacOS】rollback.command/【MacOS】rollback.command     # 恢复本次挂载和 Sourcetree Git 选择
└── tests/
    ├── 【MacOS】run.zsh/【MacOS】run.zsh          # 路由与真实本地集成的统一验证入口
    ├── 【MacOS】routes.zsh/【MacOS】routes.zsh       # 动态选路、单次执行与透传边界回归
    ├── 【MacOS】integration.zsh/【MacOS】integration.zsh  # 真实系统 Git 元数据与本地 HTTP 集成
    └── http_fixture.pl/http_fixture.pl  # 仅监听回环地址的 Git HTTP / 代理夹具
```

本菜单源码位于 `Scripts/_lib/`，构建后位于 App 的 `Resources/Scripts/_lib/`。Git 的 [`http.proxy`](https://git-scm.com/docs/git-config#Documentation/git-config.txt-httpproxy) 配置用于指定代理，不负责探测或自动回退；本模块用独立命令入口完成传输前选路。入口固定执行 `/usr/bin/git`，避免经 `PATH` 再次调用自己形成递归。

终端现有的中文路径修正函数仍由 `zsh/custom/【MacOS】git_behavior.zsh/【MacOS】git_behavior.zsh` 维护；该文件只增加网络策略入口的 `PATH` 挂载，不复制网络处理代码。Sourcetree 直接使用相同的 `bin/git`，不依赖交互式终端函数。

## 三、<span id="fallback">代理回退流程与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 识别 `clone`、`fetch`、`pull`、`ls-remote`、`push` 的单个 HTTP / HTTPS 目标，先检查显式代理和旁路设置。
  - 显式代理和空代理优先；SSH、本地路径、未知选项、多目标形式及不能可靠判断的调用直接透传，不扩大自动选路范围。
  - `fetch --all`、`fetch --multiple`、无显式仓库目标且启用了 `fetch.all` 的 fetch / pull，以及递归子模块形式可能连接多个目标，保守透传；不把外层 URL 的线路强加给其它远端。
  - fetch / pull 会核对生效的递归配置及已跟踪的子模块；即使没有显式递归参数，默认 `on-demand` 可能连接其它仓库时也透传。明确使用 `--no-recurse-submodules` 或 `fetch.recurseSubmodules=false` 关闭递归时，可进入单目标选路。push 同样保留配置驱动的递归边界。
  - 帮助、版本和 `ls-remote --get-url` 等无需网络的调用直接透传；`ls-remote -h URL` 按分支查询正常选路。clone 的命令内 `--config`、递归子模块及 `--bundle-uri` 形式保守透传。
  - URL 展开复用 Git 的只读解析，并保留 `insteadOf` / `pushInsteadOf` 重写。clone 的元数据查询只读取系统、用户级及显式命令行配置，避免所在父仓的 local 代理或重写规则影响新克隆。
- 默认使用 `system` 优先级，通过 [**macOS**](https://www.apple.com/macos/) 的 `scutil --proxy` 实时读取当前已启用的 HTTPS、HTTP、SOCKS 代理，并按此顺序去重形成候选；不先让真实 Git 尝试直连。
  - 同时遵守 `ExceptionsList` 和 `ExcludeSimpleHostnames`，不绕过已有 `NO_PROXY` / `no_proxy`；系统例外支持域名、通配与 IPv4 CIDR，IPv6 CIDR 无法精确判断时保守保持旁路。
- 使用 [**curl**](https://curl.se/docs/manpage.html) 对目标站点根地址发起无凭据 HEAD 探测，检查代理到站点的连接与 TLS；只监听本地代理端口不足以判定可用。每个候选默认连接超时 2 秒、总超时 4 秒，最多三个候选。
  - 取首个可达候选，不继续探测其它候选；探测不携带 Git 凭据，不证明仓库可写。
  - 候选返回 `407` 表示需要代理认证，不视为目标站点已可达，继续检查其它候选。
  - 代理预检出现 TLS / 证书差异时，不继续换其它代理；选定该候选，交给原始 Git 使用其 CA / 客户端证书配置验证一次。保留证书验证，不因独立 curl 的证书配置差异提前拦住 Git。
  - 没有启用代理、候选均不可达或目标命中旁路规则时，转入直连预检；不把 Git 强制发往失效端口。
- 对目标站点做一次无凭据直连探测；直连可达时，按原参数执行原始 Git 一次，保留标准输出、错误输出和退出状态。
  - 任意 HTTP 响应，包括 `401` / `403`，均视为网络可达，后续认证与权限由原始 Git 校验。
  - 直连预检出现 TLS / 证书等其它错误时，交给原始 Git 执行一次，以保留 Git 自身的证书配置；不因预检与 Git 的配置差异直接阻断业务。
  - 代理和直连均出现明确连接故障、没有可用线路时，返回 `128` 并说明失败，业务命令不执行。
- 可选 `direct` 优先级先做同样的直连预检；直连可达便执行 Git，仅 DNS / 连接失败或超时且尚未收到 HTTP 响应时才读取系统代理，复用相同候选与旁路规则。此模式也不会重放实际 Git 业务。
- 将选中的代理以目标站点范围的 `http.<url>.proxy` 仅注入本次 Git 子进程，不把代理强加给其它站点；按原参数执行原始命令一次，最终返回该命令的退出状态。预检阶段不运行真实克隆、拉取或推送，避免失败克隆留下目标目录，以及远端已接收后重放推送。

模块不修改操作系统代理、Shell 启动环境中的代理变量、全局 Git 代理或仓库配置。关闭代理软件或更改系统代理后，下一次操作重新判断；无需手动切换模式或修改脚本中的固定地址。默认每次读取当前系统代理，失效时自动回到可达直连；显式设置的代理与旁路仍优先保留。

## 四、<span id="setup">部署与普通命令入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

本目录是 [JobsEnvironmentUpdater](../../../README.md) 随包私有依赖。Finder 管理器构建时把完整模块装入 App 的 `Resources/Scripts/_lib/`；宿主打开更新终端前复制到本轮私有快照，以保持原目录关系。此菜单包不安装 `git` 全局转发器，不修改 Sourcetree 设置或用户 Shell 启动文件。

`update` 的 Homebrew 网络适配从本模块取得当前系统代理策略，仅交给本次已确认的维护子流程。代理范围、旁路和脱敏日志继续遵循上文；模块代码与原终端环境源码同源，更新菜单包后须重新安装／更新该项。

终端与 Sourcetree 的全局挂载、配置同步和恢复属于原环境仓，详见[原模块说明](../../../../../../JobsConfigOS/🌍JobsMacEnvVarConfigs/scripts/_lib/jobs_git_network_strategy/README.md)。此链接只供开发维护查阅，不是本 App 的运行依赖；不要把原仓的环境部署命令当作菜单安装步骤。

## 五、<span id="logs">日志与备份</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 网络策略审计保存在用户 `Library/Logs/JobsGitNetworkStrategy/` 下的 `push.log`，文件名为兼容既有入口保留，权限为 `0600`；只记录 UTC 时间、模式、主机、端口和退出码，不记录完整参数、凭据或 Git 输出。
  - 常见模式包括 `direct-probe`、`proxy-probe`、`direct`、`proxy`、`skip-explicit-proxy` 和 `network-unavailable`，分别用于区分探测、最终选路、显式配置透传及无可用线路。
- 原终端环境挂载的接入备份保存在用户 `Library/Application Support/JobsGitNetworkStrategy/` 下以日期和随机值区分的目录，安装 / 恢复审计为同目录 `audit.log`。
- 原终端环境恢复入口依据运行包内的本次备份指向读取快照；保留运行包及备份，便于准确识别本次挂载，避免误删后续修改。

## 六、<span id="restore">卸载恢复与临时旁路</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

本菜单功能只在 `update` 子流程加载策略，不写入原终端或 Sourcetree 的挂载配置，因此卸载菜单无需执行本目录的全局恢复工具；菜单卸载由本功能管理面板处理。

若另行安装过原终端环境的 Git 全局挂载，其检查、精确恢复和备份依据见[原模块恢复说明](../../../../../../JobsConfigOS/🌍JobsMacEnvVarConfigs/scripts/_lib/jobs_git_network_strategy/README.md#restore)。这属于原环境部署，不是本菜单的安装或卸载步骤；不要用它回退本功能。

## 七、<span id="validation">隔离验证与验收范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本模块目录执行统一验证入口；它依次运行动态路由和真实本地集成，两套都通过才返回成功：

```zsh
/bin/zsh ./tests/【MacOS】run.zsh/【MacOS】run.zsh
```

也可以按需要单独运行两套验证：

| 套件 | 范围 |
| --- | --- |
| `tests/【MacOS】routes.zsh/【MacOS】routes.zsh` | 从正式 `main` 验证五类网络命令、Sourcetree 参数、默认系统代理优先、代理不可用后的直连、可选直连优先、单次执行、显式及空代理、旁路、TLS 交由原生校验、未知参数与多目标透传；外部 Git / curl 使用隔离夹具。 |
| `tests/【MacOS】integration.zsh/【MacOS】integration.zsh` | 使用真实系统 Git / curl，验证非仓库目录 URL 解析、clone 父仓 local 配置隔离、用户级 URL 重写、递归配置边界，以及回环 HTTP 中的 `ls-remote`、clone、fetch 和 push 传输。 |

```zsh
/bin/zsh ./tests/【MacOS】routes.zsh/【MacOS】routes.zsh
/bin/zsh ./tests/【MacOS】integration.zsh/【MacOS】integration.zsh
```

测试使用独立的临时用户目录、临时配置和仓库；HTTP / 代理夹具仅监听回环地址，不访问公网，不修改用户 Git 或系统代理，退出时清理专属夹具。真实 push 用例校验 `receive-pack` 请求仅发生一次，并确认代理参数没有写入克隆仓库。通过隔离验证不代表真实公网仓库已完成克隆或推送，实际结果须由普通命令或 Sourcetree 输出确认。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

公开 `bin/git` 保持 PATH 协议，只转发至 [`bin/【MacOS】git.zsh/【MacOS】git.zsh`](<./bin/【MacOS】git.zsh/【MacOS】git.zsh>)；完整实现与独立说明同名包装。公开转发器为固定命令路径例外，不重复实现策略或接管配色。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
