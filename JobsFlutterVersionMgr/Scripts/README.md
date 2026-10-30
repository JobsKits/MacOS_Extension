# Flutter 版本管理终端脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、目录与调用](#jobs-toc-heading-2)
- [二、项目识别与边界](#jobs-toc-heading-3)
- [三、工具链体检](#jobs-toc-heading-4)
- [四、版本查询与选择](#jobs-toc-heading-5)
- [五、安装 / 切换与结果](#jobs-toc-heading-6)
- [六、日志、故障与验证](#jobs-toc-heading-7)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

`ManageFlutterVersion.zsh` 是 Finder“安装 / 切换 Flutter SDK（FVM）”的终端业务入口。先确认指定文件夹自身是 [**Flutter**](https://flutter.dev/) 项目，再检查工具链，通过 [**fzf**](https://formulae.brew.sh/formula/fzf) 选择历史或最新 SDK，最后使用 [**FVM**](https://fvm.app) 安装 / 切换精确版本。FVM 是电脑上的工具，每个项目通过自己的 `.fvmrc` 固定 SDK。

```zsh
/bin/zsh ./ManageFlutterVersion.zsh \
  --project "../../../某个 Flutter 项目"
```

| 对象 | 实际行为 |
| --- | --- |
| 项目身份 | 只检查目标同层 `pubspec.yaml` 的 `dependencies.flutter.sdk: flutter`。 |
| 健康工具 | 复用，重复运行不触发工具升级。 |
| 缺失 / 损坏工具 | 来源和目标先展示；终端确认后安装 / 修复一次并复检。 |
| 版本依据 | 优先直查 Google 官方 macOS 发布清单；不可达时依次改用国内镜像（`storage.flutter-io.cn`）和 FVM 内置发布接口，列表保留来源、查询时间与最新 stable 标记。 |
| 安装 / 切换 | 展示“当前 → 目标”和文件影响；直接回车执行，任意非空输入取消。 |
| 依赖解析 | 传入 `--skip-pub-get`；SDK 就绪后可另行运行 `fvm flutter pub get`。 |
| 离线回退 | 三个清单来源都失败时，只列 API 标记已初始化且 Flutter / 内置 Dart 文件可执行的精确版本缓存；最新版本明确未知。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、目录与调用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
./
├── ManageFlutterVersion.zsh    # 唯一业务入口，自包含 JSON / pubspec 解析
├── EnableFinderExtension.zsh   # Xcode 构建后注册固定扩展并刷新 Finder
└── README.md                  # 运行前说明
```

Finder 宿主把脚本复制到每次独立的私有临时载体，由系统 Terminal 启动。脚本使用 macOS 自带 [**zsh**](https://www.zsh.org/) 和 JavaScript for Automation，执行不依赖本目录其它文件，也不要求安装 [**Python**](https://www.python.org) / [**Node.js**](https://nodejs.org) / jq。

Finder 点击先交给后台宿主，再由宿主直接调度 Terminal；项目文件夹与目录空白处右键会各自重新读取点击时的真实目标。宿主不显示管理窗口或 Dock 图标，初始化和所有终端派发完成后退出，业务继续在 Terminal 中运行。单独运行 App 只在后台检查、注册和启用扩展后退出，不打开 Terminal；扩展开关使用系统设置或安装器处理。菜单正常启动后，终端先显示业务自述、目标目录及“已了解用途与影响，按回车继续”的确认；这时按 `Ctrl+C` 可结束，不会进入工具安装或版本切换。

`EnableFinderExtension.zsh` 是独立的构建后挂载入口，仅处理本工程 App / appex 注册与 Finder 刷新，不执行 SDK 管理。总安装器和隔离构建通过 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过该挂载，具体行为见[工程说明](../README.md)。

目录路径作为独立参数传入，兼容空格、中文、引号和换行；不会拼成用户可执行的 Shell 文本。SDK 版本与列表字段严格校验，不把任意输入作为 FVM 参数。缺少交互 TTY 时停止，请从 Terminal 或 Finder 菜单执行。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、项目识别与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

目标必须是普通文件夹；符号链接、Alias、应用 / 工程 package 不接受。`pubspec.yaml` 必须是可读的普通文件，大小不超过 1 MiB。不从父目录借用项目身份，也不递归寻找子项目。

常见 block 写法可以识别：

```yaml
name: demo
dependencies:
  flutter:
    sdk: flutter
```

也支持 `flutter: {sdk: flutter}` 和 `dependencies: {flutter: {sdk: flutter}}` 等单行 flow map。注释中的 Flutter、纯 [**Dart**](https://dart.dev) 项目、只包含 `flutter_test` 的项目均不通过。为避免误识别，YAML 文档分隔标记、缩进 Tab、锚点 / 别名、复杂多行 flow 等无法可靠识别的写法直接停止，保留原文件。

`.fvmrc`、`.fvm`、`.gitignore`、VSCode 配置、旧版 FVM 配置、`.fvm/version`、`.fvm/release`、`.fvm/versions` 容器和目标 `*.code-workspace` 若是符号链接则停止；FVM 自己生成的 SDK 链接属于正常结构。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、工具链体检 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

完整路径为：

```text
项目 FVM 操作 → FVM CLI / 实际 Dart 或 AOT runtime → Homebrew 公式与其运行依赖
版本交互     → fzf                                  → Homebrew
SDK 获取     → Git / curl / bash / Apple Command Line Tools
数据解析     → macOS JavaScript for Automation / Foundation
```

体检执行真实版本 / 只读接口检查，命令路径存在不等于健康。健康组件复用；损坏层只沿实际依赖修复一次，立即刷新当前进程 PATH 并复检；复检失败停止下游操作。

- [**Git**](https://git-scm.com)、curl、bash 和 Apple Command Line Tools 先检查实际可执行性。CLT 缺失时，经终端确认请求 Apple 系统安装，然后停止；安装完成后重新点击入口。系统引导工具无法运行时给出阻塞原因，不继续叠装下游工具。
- [**Homebrew**](https://brew.sh/) 依次发现当前 PATH、Apple Silicon / Intel 标准位置及既有用户前缀，用 `--version`、`--prefix`、`config` 核验。不自动执行 `update`、`upgrade`、`cleanup`。
- fzf 使用 Homebrew core 公式。FVM 新安装同样使用 [Homebrew core 的 fvm 公式](https://formulae.brew.sh/formula/fvm)，其运行依赖由公式管理；已有健康的 Dart Pub、独立发行包或旧 tap FVM 继续复用。
- 既有 FVM 损坏时，先确认它属于哪个已安装 formula；保留该归属执行 `reinstall`。多个归属时停止，不猜测卸载或迁移。实际已安装公式声明依赖 `dartaotruntime` 时，先验证 / 修复该运行时，再判断是否仍需重装 FVM。不能恢复的旧 tap 请依据日志人工处理。

必需组件确认采用既有终端承接方式：**回车确认安装 / 修复，任意非空内容取消整个流程**。每次组件准备前显示来源、目标前缀和动作；包的最终下载地址由 Homebrew 解析并输出。

Homebrew 缺失时还有独立的安装路径选择：

| 输入 | 安装方式 |
| --- | --- |
| 精确大写 `YES` | 使用 [官方系统安装器](https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)，Apple Silicon 为 `/opt/homebrew`，Intel 为 `/usr/local`；安装器可能要求管理员密码并验证权限。 |
| 其它输入 / 直接回车 | 从 [官方 Homebrew 仓库](https://github.com/Homebrew/brew) 查询最新稳定 tag，安装到当前用户的 `.local/homebrew`；不使用 sudo。可通过当前进程 `JOBS_HOMEBREW_INSTALL_PREFIX` 指定 HOME 下的兼容路径。 |

用户前缀必须位于当前 HOME 下且不含空白 / 冒号，不覆盖已存在目录。非标准前缀可能需要源码构建，速度与 bottle 可用性由 Homebrew 决定；选定路径失败即停止。`Ctrl+C` 取消。脚本不写 Shell 启动配置、不持久修改 PATH、不调整网络代理。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、版本查询与选择 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

版本元数据来自 [Google 官方 macOS 发布清单](https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json)，含历史版本、发布日期、渠道、架构与 `current_release`。依据 [Flutter SDK archive](https://docs.flutter.dev/install/archive) 和 [FVM JSON API](https://fvm.app/documentation/advanced/json-api) 解释这些字段。

清单按三层顺序获取，任一层拿到结构有效且能按当前架构渲染出条目的响应即停止：① 官方 Google 清单，沿用当前终端的代理设置；② 国内镜像 `storage.flutter-io.cn`（忽略代理直连）；③ FVM 内置 `fvm api releases`，转换成官方结构后复用同一套渲染逻辑。第二层命中时，仅在本次进程内把 `FLUTTER_STORAGE_BASE_URL` 指向同一镜像，供后续 SDK 初始化下载使用，不写 Shell 配置，也不覆盖用户已有的资源源。

先用 fzf 选择渠道，`stable` 排首位；还可选择 `beta`、历史 `dev`、全部渠道或仅本机缓存。第二屏单选精确版本，展示版本号、日期、渠道、架构、完整缓存 / 当前配置 / 最新 stable 标记，支持早期 `v` 前缀和 `+hotfix.9` 等合法构建元数据。每个版本按当前 CPU 架构去重；Apple Silicon 在线列表不混入仅有 x64 的早期版本。缓存列表属于本机已有 SDK，选中后先实际执行该 SDK 的 Dart 以排除不兼容 / 损坏缓存。

最新 stable 只能由本次有效响应中的 `current_release` 确认（FVM 来源用其 `active_channel` 标记），不根据列表顺序猜测。连接超时 10 秒，总请求超时 45 秒；三层都失败、空清单、伪 JSON 或缺失最新 stable 对应记录时，显示“最新未知”，仅允许完整缓存回退；无完整缓存就停止。

缓存读取采用 `fvm api list --compress`。列表中的 `stable`、`beta` 别名、自定义 fork / 任意 Git ref 不作为精确版本候选。FVM 的实际有效仓库和缓存目录单独显示；自定义 `flutterUrl` 与官方历史列表不兼容时停止，`cachePath` 须是可安全读取的绝对路径。已有资源镜像环境变量只脱敏展示并继续传给 FVM，不修改网络设置，也不把官方元数据地址描述成实际 SDK 下载地址。

首次未配置项目时，私有临时影子 `.fvmrc` 用于查询目标自身将生效的全局设置，避免只读 FVM API 继承父项目的版本、仓库或缓存；该影子目录不写进业务项目。Git URL 重写只展开已有配置并脱敏展示，不把它视为验证了远端重定向终点或网络出口。

在任一 fzf 界面按 `Esc`，或最终确认输入任意非空内容后回车，都会取消安装 / 切换项目 SDK；之前已经单独确认安装的工具仍保留。最终确认直接回车会执行，不作为取消方式。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、安装 / 切换与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

最终预览列出目标、当前 → 所选版本、版本依据、有效 SDK 源 / 缓存、影响文件和快照目录，并说明目标版本是否已在本机缓存：未缓存时明确提示 FVM 会先下载并初始化 SDK。确认提示为：

```text
👉 直接回车执行安装 / 切换；输入任意内容后回车取消：
```

直接回车执行；任意非空输入（包括空格）取消整个版本操作，项目版本配置保持原状。继续执行后：

1、重新验证项目身份、配置文件和是否在等待期间发生变化。保存已有 `.fvmrc`、旧版配置、`.fvm/version` / `.fvm/release`、`.gitignore`、VSCode settings 和目标 workspace 到本次私有快照。

2、保留原有配置字段，合并目标自身 `.fvmrc` 的精确 `flutter` 版本，并设置 `updateMelosSettings: false`，防止 FVM 向上查找后修改父项目 `melos.yaml`。这也为首次配置建立明确项目边界，避免 `fvm use` 选中父目录已有配置。

3、执行 [FVM use](https://fvm.app/documentation/guides/basic-commands)；缓存入口额外传 `--skip-setup`，避免主动重新初始化已有完整缓存。Flutter 自己的运行检查仍可能请求缺失资源，缓存存在不等于所有后续构建资源都已离线准备。

下列 `3.29.3` 是命令格式示例，应替换为实际选定的精确版本。

```zsh
fvm use 3.29.3 \
  --skip-pub-get
# 选择已初始化缓存时：
fvm use 3.29.3 \
  --skip-pub-get \
  --skip-setup
```

4、先核对 FVM 实际生成的 `.fvmrc` 精确版本，再补回 FVM 序列化时省略的原配置字段；FVM 实际输出值优先，不用预设版本覆盖错误结果。写入前后拒绝符号链接并核对配置是否被并发修改，保留 FVM 原始输出和合并结果；同目录临时文件通过重命名落盘。最后再次核对 `.fvmrc`、`.fvm/flutter_sdk` 是否指向本次有效缓存的对应版本、`fvm flutter --version --machine` 的真实版本，以及 `fvm dart --version` 的运行情况；全部通过才显示完成。

FVM 根据原项目设置还可能更新 `.fvm/fvm_config.json`、项目登记、`.gitignore`、`.vscode/settings.json` 或 `*.code-workspace`。SDK 下载 / 初始化、磁盘空间不足、项目约束或中断可能留下部分结果。写入阶段一旦失败，脚本按项目真实状态对齐 `.fvmrc`：`.fvm/flutter_sdk` 未变则还原运行前配置（运行前没有该文件就删除），已变则把 `.fvmrc` 对齐到链接指向的真实版本，避免留下一份指向未安装 SDK 的配置；无法安全判定（缺少快照或被并发修改）时保留现场，不覆盖 FVM 之后的其它改动，也不宣称完整事务回滚。它不创建 Git 提交，不设置 `fvm global`，不执行 `flutter upgrade`。

日常命令：

```zsh
fvm flutter --version
fvm dart --version
fvm flutter pub get
fvm flutter run
```

建议将 `.fvmrc` 纳入版本管理，将 `.fvm/` 忽略。终端直接运行 `flutter` 仍取决于当前 PATH；[**VSCode**](https://code.visualstudio.com/) / [**Android Studio**](https://developer.android.com/studio?hl=zh-c) 应核对项目 SDK 是否指向 `.fvm/flutter_sdk`。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">六、日志、故障与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

启动链路使用系统 `/tmp` 目录中的固定日志 `JobsFlutterVersionMgr.log`，追加记录后台宿主启动、扩展注册 / 启用、收到的项目请求、“正在请求 Terminal”、交付成功或调度错误，以及派发完成后的退出。Finder 扩展的请求和错误另写系统日志，启动失败会显示警告；可在系统“控制台”按 `JobsFlutterVersionFinderSync` 查找。具体阶段定位见[工程验证与排查](../README.md#verification-troubleshooting)。

每次运行在系统临时目录建立权限收紧的 `JobsFlutterVersionMgr.XXXXXX` 文件夹，内含 `ManageFlutterVersion.log`、本次版本 / 缓存 JSON、机器可读校验输出，以及写入前的 `before/` 配置快照。终端显示具体路径；临时目录可能被系统清理，需要长期保留时请主动复制日志和快照。日志不转储整个环境，来源 URL 的凭据与查询参数脱敏。

业务临时目录和 `ManageFlutterVersion.log` 在首屏确认后才创建。点击菜单后尚未出现终端、或仍停在首个确认时没有业务日志，不能据此判定脚本失败；先核对宿主固定日志与终端首屏。

| 现象 | 排查方向 |
| --- | --- |
| 菜单不显示 / 脚本拒绝目录 | 检查目标同层 pubspec 和真实 `dependencies.flutter.sdk`，避开 package / Alias / 符号链接。 |
| 点击后没有终端 | 查看后台宿主固定日志，区分宿主未启动、未收到请求、项目复检失败及 Terminal 自动化失败；无管理窗口或 Dock 图标属正常行为。 |
| CLT 安装请求后停止 | 先完成 Apple 系统安装，核对 `xcode-select` 选择目录，再重新运行。 |
| 旧 tap / FVM runtime 损坏 | 查看日志中的 formula 归属、失败命令与退出码；修复一次仍失败则人工排查原安装来源。 |
| 官方清单获取失败 | 脚本会自动改用国内镜像和 FVM 内置接口，日志会写明实际来源；三层都失败时才会只列本机缓存。核对 `storage.googleapis.com` 是否被 DNS 解析到 `127.0.0.1`，以及终端 `HTTP(S)_PROXY` 是否可用。 |
| SDK 下载失败 | 看 `fvm` 输出里的实际下载地址与退出码；镜像来源下脚本只在本次进程注入 `FLUTTER_STORAGE_BASE_URL`，请在同一终端重试，不要把该变量写进 Shell 配置。 |
| 自定义仓库被拒绝 | 官方版本列表只适用于官方 Flutter 仓库；自定义 fork 应使用该项目原有流程。 |
| SDK 实际版本 / 链接不一致 | 失败时脚本已按链接真实状态对齐 `.fvmrc`；仍不一致说明缺少快照或被并发修改，按日志核对 `.fvmrc`、缓存路径、链接与 SDK 完整性，再参考 `before/` 快照决定恢复哪些配置。 |

静态检查：

```zsh
/bin/zsh -n ./ManageFlutterVersion.zsh
```

自动化验证应使用隔离临时目录、假命令与版本清单夹具，覆盖健康复用、逐层缺失、安装失败、修复后复检失败、取消、架构去重、父配置保护和失败后的配置对齐。不得为普通验证执行真实 Homebrew 安装 / SDK 下载，或修改用户 Flutter 项目。构建和隔离测试之外，还须确认单独运行 App 只后台初始化后退出，并分别验证 Finder 冷启动、后台仍在派发时接收的 URL 请求均到达 Terminal 首个确认；到此可按 `Ctrl+C` 退出，单独确认菜单至终端的链路。宿主全程不出现管理窗口和 Dock 图标，退出不影响已派发业务。真实 fzf、网络安装和目标项目兼容性需在实际使用环境继续验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
