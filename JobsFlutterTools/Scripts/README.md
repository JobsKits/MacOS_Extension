# Flutter 菜单实现

Finder 直属分组为“拉取Flutter项目工程相关依赖”“提取Flutter项目工程依赖”“导入Flutter项目工程依赖”“安装/切换Flutter运行环境”“Flutter 资源与构建依赖”；只改变显示层级，45 个可执行动作和逐项开关保持各自职责。`native-dependencies` 显示为资源与构建依赖组内的“准备原生库与构建依赖（组合操作）”；`sdk-version` 位于“Flutter项目体检”首项。环境组含 Flutter SDK、Flutter@OpenHarmony SDK、Java SDK；资源与构建依赖组按“下载Gradled分发与构建插件”“下载Flutter平台资源”“准备原生库与构建依赖（组合操作）”顺序显示。菜单树及 FAQ 见[功能说明](../README.md#dependency-faq)。

`import-dependencies` 调用 `Tools/ImportFlutterDependencies.zsh`：终端输入或拖入完整导出目录，先由 `ImportFlutterDependencies.dart --validate-only` 只读验证并显示计划，通过后精确输入 `YES` 才写入项目本地依赖与 `pubspec_overrides.yaml`。原覆盖文件备份后保留；目标 pubspec 原始覆盖区与快照完整原文一致时可恢复为本地依赖，其它同名覆盖冲突停止；不自动 `pub get`。引擎复用同目录 `ExtractFlutterDependencies.dart` 的解析器，两个 Dart 文件必须一并打包。使用边界与恢复方法见[导入说明](../README.md#dependency-import)。

安装器的子功能清单位于当前用户应用支持目录 `JobsFinderExtensions/flutter-tools-features.conf`：总管理器安装只增加所选动作、卸载只减去所选动作；本包管理入口通过 `--features` 指定动作，省略时处理全部 45 项（2026-10-30，按共享 `FlutterToolsAction` 的可执行叶动作计数）。各类依赖分别勾选，仍有动作时保留共享 App 与配置，最后一项才注销并清除清单。脚本资源仍统一打包到 App，禁用动作由 Finder 与宿主在派发前拦截。

`project-setup` 通过 `Tools/OpenSetupWindow.zsh` 启动原生窗口。Xcode宿主在复制Tools后、最终签名前，由 [BuildSetupWindow.zsh](./BuildSetupWindow.zsh) 按目标架构与最低系统编译 `SetupProjectWindow.swift`，成品写到构建产物 `Resources/Tools/JobsFlutterSetup`，不写源码目录或跟踪Git；图形入口优先复用该随包可执行文件，本身不要求目标电脑有CLT或Swift编译器。仅独立源码入口缺少binary时才用本机工具编译，缺CLT会提示本人安装或使用完整构建包。现有跳过Finder登记的构建环境变量仍只控制原登记阶段。宿主先复制私有 Tools 载体，窗口通过 `forkpty` 在真实终端中运行 `SetupFlutterProject.zsh`。中间区使用上下 `NSSplitView` 和显式拖柄，默认上区212点，任务线最小144点、终端最小180点；没有固定高度约束。分隔条改变WebKit布局后，xterm Fit将新行列通过PTY `TIOCSWINSZ` 传回业务进程。下半部 WebKit 只加载随包 `SetupGUIAssets/terminal.html`、固定 xterm / Fit 资源，不访问远程网页；按键与 resize 发回 PTY。退出前排空剩余输出，原始 ANSI 日志完整保存在独立私有会话目录。只有此动作使用新窗口，其余动作沿用现有 Terminal 派发。

里程碑通过 `JOBS_FLUTTER_SETUP_EVENTS` 指向本次 `events.jsonl`，每行包含 `id`、`parent`、`title`、`state`、`message`，可选 `version` 为后端实际检测版本（`pe_event` 第六参数）。版本在节点下独立小字展示，限制两行，后续省略版本的状态事件保留最近实测值；完整路径保留在提示中。窗口工具版本及构建号读取唯一随包 `Tools/SetupVersion.json`，不与源码重复写死。顶层为 `flutter/java/gradle/pub/platforms/readiness`，子节点以点分段，例如 `platforms.android.sdk`；状态只接受 `pending/running/succeeded/failed/attention`。显示消息不替代原始终端日志，未知事件不执行命令。GUI 只记录 PTY master 输出，不额外记录键盘输入；密码是否回显仍由真实终端程序控制。

`gradle-download` 在通用 FVM 门禁前交给 `DownloadProjectGradle.zsh`，共享 `ProjectEnvironment.zsh` 读取本机选择并记录日志。`WrapperDistributionCache.zsh` 依据官方 URL 散列计算实际 ZIP / 解压目录，用所选 JDK 的 `javac` 在本次临时目录编译小型缓存助手，通过 Wrapper 同名 `.lck` 的 Java FileLock 原子发布已验 SHA-256 的 ZIP；不会伪造完成标记或替换已有在途文件。随后实际 Wrapper 有界 `--version` 验证本地复用，插件预热才进入 `Gradle help`。完整行为、超时、恢复与平台限制见[配置与下载说明](../README.md#project-setup)。

菜单、FVM 要求、修复范围与安装流程见 [功能说明](../README.md)。已启用的鸿蒙打包入口对所有合法 Flutter 根目录可见；点击后检查 `ohos/` 及两份清单，未适配时明确提示并停止。`Tools/DispatchFlutterTools.zsh` 是唯一分发入口；`Tools/FlutterProjectTools.dart` 处理双层体检、两类代码修复与维护；`RepairAndroidSdk.zsh` 复用 `AndroidSdkSupport.zsh` 的组件引导。`RetireLegacyFlutterMenus.zsh` 只在统一扩展已启用后停用旧 Flutter 入口。

`pub-get` 在通用 FVM 门禁前交给 `Tools/InspectFlutterProject.zsh <项目> pub-get`，由业务入口先显示自述并等待终端回车，再检查项目自身 FVM 声明、SDK 文件及实际 Flutter / Dart 运行情况。未就绪时在同一终端调用包内 `Tools/ManageFlutterVersion.zsh --project <项目>`，沿用原安装 / 切换交互；明确完成并复检通过后才继续 `flutter pub get`。取消、准备失败或复检失败不执行依赖拉取，不调用全局 SDK，也不改变其它动作的 FVM 门禁。依赖拉取日志为系统临时目录的 `InspectFlutterProject.log`，SDK 管理日志与快照另存终端提示的 `JobsFlutterVersionMgr.*` 目录。`--check` 仅核对文件和计划，SDK 缺失时说明按需准备路径并返回失败，不启动管理器或调用 SDK。

`android-dependencies`、`pods-dependencies`、`spm-dependencies`、`ohos-dependencies`、`native-dependencies`、`flutter-precache`、`web-dependencies` 同样在通用门禁前交给 [FetchProjectDependencies.zsh](./Tools/FetchProjectDependencies.zsh)，固定映射到 `--kind android|pods|spm|ohos|native|precache|web`，复用 [ProjectDependencies.zsh](./Tools/ProjectDependencies.zsh) 的目标依赖内核。确认后可按需准备本项目 SDK / Pub / 平台工具；本机环境记录失效时停止并提示重新配置。单项入口支持 `--project`、`--kind`、可选 `--platform` 与 `--check`；只读检查不启动 SDK、下载、工程构建或创建日志。独立安装 / 卸载按动作过滤菜单，不新增顶层 Flutter 组或额外 App。

独立 `flutter-precache` / `native-dependencies` 首屏在回车确认前逐行说明命令、制品示例、平台包与实际构建边界，子项缩进；自述不启动下载。资源与组合步骤见 [FAQ](../README.md#dependency-faq)。

一键配置在 Pub 之后调用同一内核：Android 解析可解析的 Maven 配置，Apple 处理 Pods / SPM，OpenHarmony 同步 OHPM / Hvigor，Web 处理存在的锁定 JS 工程，再以当前启动配置实际 `flutter build` 触发原生库与延迟下载。该构建不安装或启动 App，后续运行验收单独执行。`flutter-precache` 只缓存同套 Flutter 的平台资源，不等于 Android SDK / NDK / CMake 等系统工具，也不代替原生依赖；完整能力矩阵和编译、宿主、离线边界见[分层依赖说明](../README.md#dependency-layers)。

`extract` 使用包内 `Tools/ExtractFlutterDependencies.zsh` 与同目录 Dart 引擎，只读提取已解析的 Pub 源码。排除 `.plugin_symlinks` 和包内、嵌套示例中的 `linux/flutter/ephemeral`、`windows/flutter/ephemeral`、`macos/Flutter/ephemeral` 生成目录，其余平台源码保留；失效、包外或循环链接跳过，终端及 `manifest.json` 的 `warnings` 记录包名、相对路径和原因，真实包根或普通源码缺失仍报错。详细范围见 [依赖提取说明](../../JobsFlutterDependencyExtractor/README.md)。在目标 Mac 取得当前源码后，通过管理入口重新“安装 / 更新”以载入 App 资源，再从 Finder 发起新请求；旧临时目录的 `launch.zsh` 不会刷新资源。

Pub 的 `extract` / `import-dependencies` 仍只处理原格式的包源码、许可证和清单。平台缓存另由 `export-{kind}-dependencies` / `import-{kind}-dependencies` 配对动作处理，`kind` 为 `gradle|pods|spm|ohos|native|precache|web`；export 动作位于“提取Flutter项目工程依赖”，import 动作位于“导入Flutter项目工程依赖”，逐项开关由同一共享包管理。分发给 `Tools/ArchiveProjectDependencies.zsh --mode export|import --kind <类别> --project <项目>`，复用包内 `NativeDependencyArchive.dart`；不执行归档内脚本、不自动联网补齐。导入先完整校验宿主、工具版本、工程锁指纹、逐文件 hash 与冲突，再精确 `YES` 确认并复检；同名不同内容拒绝覆盖。范围、共享缓存与跨机边界见[平台快照说明](../README.md#dependency-archives)。

`ohos-sdk-manage` 在 FVM 门禁前交给 `Tools/ManageHarmonyFlutterVersion.zsh --project <目录>`，从 CPF-Flutter 源查询发布标签，下载到独立缓存后固定项目 FVM；`java-manage` 同样在门禁前交给 `Tools/ManageProjectJava.zsh --project <目录>`，管理 jEnv 与 `.java-version`。两个脚本均支持 `--check` 只读模式，安装后使用 App 内自包含资源。存在项目 Java 声明时，分发器通过 `pj_bind_project_java` 为普通工具注入本次 `JAVA_HOME`、`PATH` 和 Gradle daemon 参数，失败即停止；静态清理、静态 import 修复和版本管理不依赖 Java 绑定。

打包子菜单用 `package-ios` / `package-android` / `package-ohos` 固定动作传递平台，分发为 `PackageFlutter.zsh --project <目录> --platform ios|android|ohos`。其中 `package-ohos` 对应“📦 打包鸿蒙（HAP + APP）”，清空本次子进程的 `FLAVOR`，固定追加 `--ohos-target all --mode release`，一次构建并核对两种产物；仅已具备普通 `ohos/` 及两清单的 Flutter 项目可执行，不再弹包型选择。原 `package` 动作保留兼容旧请求。`--platform` 跳过平台选择；fzf 仅在还需选择平台或产物时检查。

`Flutter清理维护工具` 下的 `clean-build-artifacts` 动作在 FVM 门禁前分发：用包内 `CleanBuildArtifacts.zsh --detect` 再次确认 Flutter 根目录，然后进入该脚本的路径预览和 `CLEAN` 确认。包内脚本与 `JobsTerminalOpener/Scripts/CleanBuildArtifacts.zsh` 保持逐字节一致，通过 `Tools` 文件夹资源随 App 打包；不要求安装 Terminal 包或存在源码仓库。静态清理不运行 `flutter clean` / `pub get`，也不删除共享缓存。

清理脚本用系统 Perl 及其标准模块 `Encode` / `JSON::PP` 保守解析 `dependencies.flutter.sdk`：支持常见缩进块、单行 flow、单双引号和 UTF-8 BOM；拒绝重复依赖段、重复 Flutter/SDK 键，以及环境、开发依赖或说明正文里的误导声明。静态清理与统一菜单一样只要求合法 Flutter 依赖声明，不要求存在 `lib/`；其余旧动作保留原有目录检查。清单仅按 UTF-8 文本读取，最大 1 MiB；不执行 YAML 标签、工程脚本或安装额外解释器。

同级的“依赖与缓存维护”继续使用旧 `maintenance` 动作，保留项目 FVM 检查，再交给 `FlutterProjectTools.dart` 的原编号菜单。`Tests/BuildArtifactDispatchTests.py` 使用独立资源副本与临时目录验证两条路径的权限边界；`Tests/MenuTransportTests.py` 验证真实菜单层级和动作传输。

`Flutter项目修复` 下的 `repair-package-imports` 动作同样在 FVM 门禁前执行：先用 `CleanBuildArtifacts.zsh --detect` 核验当前层 Flutter 声明，再把选中的绝对路径作为 `--project` 参数传给包内 `RepairPackageImports.zsh`。该脚本仅使用系统 zsh / Perl，按引用文件位置解析到本项目 `lib/` 的相对 import，预览并确认后备份和写入，不调用 Flutter / Dart / FVM。与 `JobsCommand@Flutter/MacOS/小工具/【MacOS】⚙️import =＞package💣.command/` 的主脚本保持逐字节一致；`Tools` 为 Xcode 文件夹资源，新脚本自动随 App 打包。原 `repair-imports` 动作及 Dart 引擎继续处理中文 URI 编码，两项互不替代。

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录的 [ManagementPanel.swift](./ManagementPanel.swift) 与 [FinderManagerGUI.zsh](./FinderManagerGUI.zsh) 负责随包面板和编译缓存。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中和执行中不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。切换操作会显示该操作已有的耗时。支持独立复制时须连同上级 App、启动脚本、源码及资源整体保留。

验证入口：`ruby ../Tests/WrapperDistributionCacheTests.rb` 使用临时缓存、真实 Java FileLock 和假 Wrapper 验证布局、并发与零覆盖；`ruby ../Tests/SetupWindowTests.rb` 编译真实窗口，在 WKWebView 的 PTY 中运行真实 fzf，验证按键、字面输入、resize、父子状态与完整私有日志。测试业务均为临时脚本，不安装 SDK 或运行用户项目；真实平台安装、签名与 App 启动须单独验收。

`ruby ../Tests/ProjectDependencyTests.rb` 在临时工程中验证各包源的真实命令结构、工程工作目录、锁文件不升级、单项取消、失败传播和原生编译不安装 / 启动；只读入口不执行假工具也不写日志。菜单与安装选择回归覆盖 Mac 的七个依赖叶，Windows 对应五项及 Apple 专属项拒绝由平行仓测试覆盖。

`ruby ../Tests/SetupWindowLauncherTests.rb` 验证随包binary在无编译器夹具中直接启动、构建阶段顺序与登记跳过变量不变，以及真实双架构编译/合并/签名仅写临时Xcode产物。

私库配对动作 `export-private-dependencies` / `import-private-dependencies` 复用现有 zsh 包装器的 `--private-only` 模式与 Dart 引擎。范围及迁移步骤见[私库迁移](../README.md#private-dependency-migration)。
