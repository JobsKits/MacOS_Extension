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

`InspectFlutterSdkVersion.zsh` 是 Finder“查看当前 Flutter SDK 版本”的终端业务入口。先确认指定文件夹自身是 [**Flutter**](https://flutter.dev/) 项目，再判定 SDK 来源（[**FVM**](https://fvm.app) 项目 SDK 或系统 SDK），实际执行该 SDK 的 `flutter --version --machine`，最后与 `.fvmrc` 配置和 `pubspec.yaml` 的 `environment` 约束核对。全程**只读**：不安装工具、不下载 SDK、不修改任何项目文件。

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
- 中断（`Ctrl+C` / `TERM`）保留日志后按标准退出码退出。
- 验证：`zsh -n` 语法校验；三分支行为验证（系统 SDK、FVM 已链接、非 Flutter 项目拒绝）已用隔离的假 SDK 与假项目目录跑通，不依赖真实 Flutter 安装。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
