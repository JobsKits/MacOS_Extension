> 本功能的右键入口已迁入 [JobsFlutterTools](../JobsFlutterTools/README.md)。以下保留旧独立工程的实现说明；新安装使用统一菜单与项目 FVM。原“Flutter项目体检”在新菜单中称为“原生Flutter项目体检”。

# JobsFlutterDependencyExtractor

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、使用速览](#jobs-toc-heading-2)
- [二、安装与卸载](#jobs-toc-heading-3)
- [三、使用方式](#jobs-toc-heading-4)
- [四、能力边界与保护](#jobs-toc-heading-5)
- [五、项目配置支持](#jobs-toc-heading-6)
- [六、日志与验证](#jobs-toc-heading-7)
- [七、脚本入口概述](#jobs-toc-heading-8)
  - [【MacOS】提取Flutter第三方依赖.command](#jobs-toc-heading-9)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

**菜单范围：桌面空白处不显示本功能；文件夹与项目菜单仍按下文条件显示。桌面上选中的项目文件夹不受此空白菜单规则影响。**

> 独立 [**macOS**](https://www.apple.com/macos/) Finder 右键功能：**提取 Flutter 第三方依赖**。只处理所选 [**Flutter**](https://flutter.dev/) 项目自身，打开 Terminal 输入或拖入输出父目录，直接回车默认系统桌面。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、使用速览 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 项目 | 行为 |
| --- | --- |
| 菜单 | 提取 Flutter 第三方依赖 |
| 输出 | 在用户指定父目录中创建唯一命名的提取目录；不覆盖已有目录 |
| 内容 | 本机已解析的 Pub 直接、间接、开发依赖源码、包内平台源码、资源、许可证和清单 |
| 需要 | 有效 `pubspec.yaml`、对应 `pubspec.lock`、`.dart_tool/package_config.json` 和本地依赖源码，以及可运行的 Dart |
| 安装 / 卸载 | 双击 `./【MacOS】管理Flutter依赖提取Finder扩展.app`，在面板选择操作、勾选后点击执行；逐项状态和实时可复制日志显示在同一窗口 |

```text
JobsFlutterDependencyExtractor/
├── JobsFlutterDependencyExtractor.xcodeproj/
├── JobsFlutterDependencyExtractor/       # 无窗口后台宿主
├── JobsFlutterDependencyFinderSync/      # Finder 菜单扩展
├── JobsFlutterDependencyShared/          # 项目判定与严格 URL 请求
├── Scripts/                             # 提取入口、Dart 引擎与构建后注册
├── Tests/                               # 不启动 Terminal 的隔离验证
├── 【MacOS】提取Flutter第三方依赖.command/  # 可整体拷走的桌面脚本包
├── 【MacOS】管理Flutter依赖提取Finder扩展.app
└── 【MacOS】管理Flutter依赖提取Finder扩展.command
```

本工程是 [MacOS@Extension](../README.md) 中的普通源码目录，源码、文档与版本由总仓统一管理。当前管理入口转交统一 `JobsFlutterTools` 的依赖提取叶子，安装菜单需要保留完整总仓。独立提取业务脚本包仍可整体复制使用，不依赖 Finder 安装。

本地文档保留 `[toc]`，由总仓根目录的 [目录过滤器](../.jobs-markdown-toc/README.md) 统一管理；新克隆后在总仓根目录安装一次，整文件暂存时生成远端折叠目录。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、安装与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[原管理脚本](./【MacOS】管理Flutter依赖提取Finder扩展.command)与[同名 App](./【MacOS】管理Flutter依赖提取Finder扩展.app)均保留。终端只负责唤起独立 GUI，启动脚本结束后关闭本次完成页；安装 / 卸载、状态和实时日志全部留在 GUI。面板仅展示依赖提取选项，默认空选；切换操作后重新勾选，点击按钮直接执行，不要求终端回车或 `YES`。内部管理实现位于 `Scripts/ManageExtension.zsh`。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

安装需要完整 [**Xcode**](https://developer.apple.com/xcode/) 和 macOS SDK，在统一包构建缓存生成产物、登记启用菜单并刷新 Finder。安装保留已有 Flutter 选项，卸载只减去依赖提取叶子，统一包最后一项移除后才卸载 App；源码、项目和已提取目录保留。执行期间在面板显示等待 / 执行中 / 成功 / 失败及底部可复制实时日志，完整日志通过面板“日志文件”定位。运行中须等待任务结束后关闭，勿直接删除系统仍引用的构建产物。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、使用方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、在 Finder 中右键单个 Flutter 项目文件夹，或打开该项目后右键窗口空白处，选择“提取 Flutter 第三方依赖”。多选、普通文件、符号链接、包目录和非项目根不显示菜单。

2、Terminal 首屏显示提取范围，确认后输入或拖入输出父文件夹；直接回车使用系统桌面。不要把提取目标放到源项目或待复制包内部。`Ctrl+C` 可取消。

3、结束后查看新目录中的 `packages/`、`manifest.json`、原始 `pubspec.yaml` 和 `pubspec.lock`。分享前检查清单及原始配置中的本地路径、私有仓库地址与第三方许可证。

无需先安装扩展时，可直接使用 [独立桌面脚本包](./【MacOS】提取Flutter第三方依赖.command/README.md)。同名文件夹内包含 `.command`、`ExtractFlutterDependencies.dart` 和 `README.md`，整体复制到桌面即可双击运行；项目和目标均可输入或拖入，目标直接回车仍使用系统桌面。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、能力边界与保护 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 提取基于本地已经解析并下载的 Pub 依赖；缺少锁文件、包配置、包源码或版本不一致时停止，提示先在目标项目正常完成依赖解析。不会自行执行 `pub get`、升级工具或安装 SDK。
- Flutter / Dart SDK 自带包不作为第三方源码复制；普通项目包含开发依赖和传递依赖。Pub workspace 必须由祖先或嵌套 workspace 明确声明所选成员，再按该成员的直接、开发与传递依赖闭包提取，避免复制其它成员无关依赖。成员列表支持标准块列表、单行 flow 列表及相对路径模式 `*`、`**`、`?`；复杂 YAML、未声明成员或失效解析记录明确停止。
- 复制包目录内的 Android / iOS / macOS / Windows 等原有平台源码，保留已有许可证；不会打包整个 Flutter SDK，也不会收集 CocoaPods、Gradle、Maven 等平台工具单独下载的二进制缓存。
- 输出为源码归档，不自动改写项目依赖、生成离线覆盖配置或保证跨机器一键构建。忽略 `.git`、`node_modules`、`Pods`、`.dart_tool`、`build`、`DerivedData` 等环境与构建目录；包内有效符号链接物化为普通文件或目录；无法解析、包外、循环或指向排除目录的链接跳过，并在终端及 `manifest.json` 的 `warnings` 记录包名、相对路径和原因。真实包根、普通源码读取或复制错误及特殊文件仍明确失败，不报告为完整成功。
- Finder 与宿主都重新校验目标根 `dependencies.flutter.sdk: flutter`。URL 只接受一个绝对路径参数，Shell 使用数据引用，不执行路径中的命令字符。
- 每次启动使用 0700 私有目录，载体、业务脚本和 Dart 引擎为 0600；Terminal 只收到物理单行启动命令。正常退出和受控信号精确清理本次私有文件，不清理其他请求。

## <span id="jobs-toc-heading-6" data-jobs-toc="v2">五、项目配置支持 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 配置 | 值 |
| --- | --- |
| App / Scheme | `JobsFlutterDependencyExtractor` |
| App Bundle ID | `com.jobs.JobsFlutterDependencyExtractor` |
| 扩展 Bundle ID | `com.jobs.JobsFlutterDependencyExtractor.FinderSync` |
| 扩展产物 | `JobsFlutterDependencyFinderSync.appex` |
| URL | `jobsflutterdependencyextractor://extract?path=...` |
| 上级功能标识 | `flutter-dependency-extract` |

宿主使用 `LSUIElement`，不显示管理窗口和 Dock 图标，等待扩展初始化及所有 Terminal 请求派发完成后自动退出。首次使用可能由 macOS 请求允许自动化控制 Terminal。

[构建后脚本](./Scripts/EnableFinderExtension.zsh) 挂在 App 的 Enable Finder Extension Build Phase，正常 Xcode 构建后会注册、启用扩展并刷新 Finder。设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 时只打印说明并跳过该注册过程。独立安装器构建时设置此开关，随后统一注册。

App Resources 必须包含 `ExtractFlutterDependencies.zsh` 和 `ExtractFlutterDependencies.dart`；宿主逐请求复制两份资源到同一目录后启动 `/bin/zsh`，不能只拷贝外层入口。

## <span id="jobs-toc-heading-7" data-jobs-toc="v2">六、日志与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 宿主派发日志：系统临时目录中的 `JobsFlutterDependencyExtractor.log`。
- 构建后注册日志：系统临时目录中的 `JobsFlutterDependencyExtractorBuildPhase.log`。
- 管理日志：面板“日志文件”定位本次独立会话文本；统一包业务和提取日志另按对应脚本说明保存。
- 提取业务日志：自述确认后在 `${TMPDIR:-/tmp/}` 下创建私有普通文件 `JobsFlutterDependencyExtractor.随机标识`；准确路径显示于 Terminal，成功后同时给出实际输出目录。

在本工程根目录运行以下隔离回归；前两项需要健康的 [**Dart**](https://dart.dev) / [**Ruby**](https://www.ruby-lang.org) 环境，均不注册扩展、不下载依赖、不提取用户项目：

```shell
dart ./Tests/DependencyExtractionTests.dart
ruby ./Tests/ExtractionShellTests.rb
```

`DependencyExtractionTests.dart` 覆盖本地依赖交叉核验、workspace 成员范围、复制与失败边界；`ExtractionShellTests.rb` 覆盖路径输入 / 拖入、自述取消、桌面默认值和引擎失败码传递。原生传输用例保存在 `Tests/FlutterDependencyTransportTests.swift`，需与共享校验、请求和 TerminalLauncher 源码一起编译。

隔离构建示例，仅生成产物，不运行安装器或宿主：

```shell
JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 xcodebuild \
  -project ./JobsFlutterDependencyExtractor.xcodeproj \
  -scheme JobsFlutterDependencyExtractor \
  -configuration Debug \
  -derivedDataPath ./work/DerivedData \
  build
```

原生传输验证在临时目录检查 Flutter 根判定、严格 URL、特殊字符路径、0700 / 0600 权限、Dart 资源复制、退出码和信号清理；不启动真实 Terminal、不注册扩展、不提取用户项目。本轮 Debug 隔离构建与签名检查通过，尚未执行真实扩展安装；源码与隔离构建检查不能代替真实 Finder 菜单和系统授权的实机验收。Windows 平行版本已完成模拟验证，仍待 Windows 设备验收。

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">七、脚本入口概述 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

### <span id="jobs-toc-heading-9" data-jobs-toc="v2">[【MacOS】提取Flutter第三方依赖.command](./【MacOS】提取Flutter第三方依赖.command/【MacOS】提取Flutter第三方依赖.command)</span><!-- jobs-toc:heading-end -->

> **目的：** 不安装扩展，直接归档一个 Flutter 项目已解析的第三方依赖。

- 阅读内置自述，直接回车继续；任意非空输入或 EOF 取消。
- 输入或拖入项目，再输入或拖入输出父目录；目标直接回车为桌面。
- 体检已有原生 Dart，引擎核对本地解析记录后创建独立输出目录，显示结果和日志。

安装与卸载入口见[第二章](#jobs-toc-heading-3)；`Scripts/ExtractFlutterDependencies.zsh` 是 Finder 调用的交互业务入口，`ExtractFlutterDependencies.dart` 是同目录引擎，`EnableFinderExtension.zsh` 仅服务构建后注册；职责和运行边界见 [Scripts 说明](./Scripts/README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
