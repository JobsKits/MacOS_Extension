# Flutter SDK 版本查询终端脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、目录与调用](#jobs-toc-heading-2)
- [二、项目识别与边界](#jobs-toc-heading-3)
- [三、SDK 来源判定](#jobs-toc-heading-4)
- [四、版本执行与约束核对](#jobs-toc-heading-5)
- [五、日志、故障与验证](#jobs-toc-heading-6)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

**SDK 获取策略：** 必需 SDK 的下载、安装中的网络获取及 Flutter 首次启动补齐 Dart / 引擎组件，默认失败自动持续重试，直到成功或用户按 Ctrl+C / 结束进程；不再询问是否重试，也不设次数或总时长上限。退避默认为 2、4、8、16、30 秒；`JOBS_SDK_RETRY_DELAY` / `JOBS_SDK_RETRY_MAX_DELAY` 可配置。保留工具原生进度与已有缓存，每次获取输出追加保存到原日志旁的 `.attempts.log`；版本选择、真正的许可证 / 权限操作及原始入口确认保留。确定的权限、磁盘、架构、参数或不存在版本错误直接说明原因并停止；项目构建与代码生成失败不整体重放。`--check` / `--help` 继续只读。

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

`InspectFlutterSdkVersion.zsh` 是 Finder“查看当前 Flutter SDK 版本”的终端业务入口。先确认指定文件夹自身是 [**Flutter**](https://flutter.dev/) 项目，再判定 SDK 来源（[**FVM**](https://fvm.app) 项目 SDK 或系统 SDK），实际执行该 SDK 的 `flutter --version --machine`，最后与 `.fvmrc` 配置和 `pubspec.yaml` 的 `environment` 约束核对。不安装或切换 SDK，不改写项目版本配置；实际调用 Flutter 时，缺失的 Dart / 引擎缓存可能由 Flutter 自行补齐，终端同步显示其原始进度。


**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，默认 `build`。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。默认不清理；UI 仅在应用程序安装模式显示清理选项，退出该组合就清空。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、目录与调用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
Scripts/
├── InspectFlutterSdkVersion.zsh   # 查询业务入口（宿主打包为 App 资源）
├── EnableFinderExtension.zsh      # Xcode 构建后注册扩展的挂载脚本
└── README.md
```

终端独立执行：

```zsh
/bin/zsh "./Scripts/InspectFlutterSdkVersion.zsh" \
  --project "/路径/Flutter项目"
```

参数固定为 `--project <绝对目录>`；脚本需要可交互 Terminal，非 TTY 环境直接停止。首屏展示内置自述，回车后才开始；`Ctrl+C` 随时取消。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、项目识别与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 目标必须是普通文件夹：拒绝符号链接、文件系统根目录、应用与工程 package（`app` / `framework` / `xcodeproj` 等）。
- 只读根层 `pubspec.yaml`（≤ 1 MiB 普通文件），不搜索父目录或子目录。
- 通过系统 JavaScript for Automation（`osascript -l JavaScript`）保守解析，必须唯一根级 `dependencies` 且 `dependencies.flutter.sdk: flutter`；Tab 缩进、多文档标记、YAML 锚点与转义 flow 写法直接拒绝，提示人工先改成标准 block。
- `pubspec.yaml` 与 `.fvmrc` 均为普通文件，拒绝符号链接，防止读到其它位置。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、SDK 来源判定 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

判定顺序固定，先 FVM 后系统：

1. **FVM 项目 SDK**：`.fvm/flutter_sdk` 是符号链接且其 `bin/flutter` 可执行 → 采信该链接；链接指向的缓存目录名即链接版本。
2. **FVM 配置未生效**：仅有 `.fvmrc`（或旧版 `.fvm/fvm_config.json`）时，输出配置版本并明确提示“未链接、本次显示系统 SDK”。
3. **系统 Flutter SDK**：按顺序体检候选并取第一个健康者：当前 `PATH`、`~/fvm/default/bin/flutter`、`~/.fvm/default/bin/flutter`、`~/flutter`、`~/development/flutter`、`/opt/homebrew`、`/usr/local`；候选用 `--version --machine` 实际执行验证（25 秒健康超时）。
4. 全部失败时停止并说明排查方向；**不自动安装任何 SDK**。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、版本执行与约束核对 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 版本结论只采信目标 SDK 实际执行的 `flutter --version --machine`：Flutter / Dart 版本、发布渠道、Framework 与 Engine revision、提交时间、SDK 路径（优先取 JSON 的 `flutterRoot`）。
- 执行带 180 秒轮询超时（Flutter 冷启动要生成 kernel snapshot），超时终止本次进程并说明原因；执行前设置 `CI` 抑制类遥测环境变量，仅限本次进程与子进程。
- `.fvmrc` 配置版本与实际版本逐项比对：一致、链接目录与实际不一致、未链接三种结论明确区分。
- `environment.sdk` / `environment.flutter` 约束用 zsh `is-at-least` 判定 `^`、`>=`、`<=`、`>`、`<` 与空格多段；预发布 / build 后缀或超出范围的写法输出“未判定，请人工核对”，不假装满足。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、日志、故障与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 终端输出与纯文本日志同步落盘：`${TMPDIR}/JobsFlutterSdkInspector.XXXXXX/InspectFlutterSdkVersion.log`（umask 077，日志不注入 ANSI）。
- `--version --machine` 的标准输出独立保留供 JSON 解析，终端同时按字节显示输出与错误流；原生回车进度、无换行尾部不会等到查询结束才出现。系统 SDK 候选体检也使用同一路径。
- 中断（`Ctrl+C` / `TERM`）保留日志后按标准退出码退出。
- 验证：`zsh -n` 语法校验；三分支行为验证（系统 SDK、FVM 已链接、非 Flutter 项目拒绝）已用隔离的假 SDK 与假项目目录跑通，不依赖真实 Flutter 安装。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
