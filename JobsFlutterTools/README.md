# Flutter 开发、体检、修复与维护

`JobsFlutterTools` 是 Flutter 工程右键菜单的统一入口。只有同层 `pubspec.yaml` 声明 Flutter SDK 的工程文件夹才展示菜单；支持选中文件夹或工程内空白处。菜单由单个扩展创建，子菜单顺序固定，不再由多个独立扩展竞争排列。其他软件提供的菜单相对于本组的位置由操作系统决定。

## 固定菜单结构

```text
Flutter开发相关辅助工具
├─ 运行Flutter项目
├─ 拉取Flutter第三方依赖
├─ 提取Flutter第三方依赖
├─ 查看当前Flutter项目的SDK版本
├─ 安装/切换Flutter SDK版本
├─ 安装/切换 Flutter@OpenHarmony SDK
├─ 安装/切换Java环境
├─ Flutter打包
│  ├─ iOS
│  ├─ Android
│  └─ 鸿蒙
├─ Flutter自动化生产代码
├─ Flutter项目体检
│  ├─ 原生Flutter项目体检
│  └─ 鸿蒙Flutter环境体检
├─ Flutter项目修复
│  ├─ 修复 Android SDK / platforms 缺失
│  ├─ 修复 Flutter 项目中文路径
│  ├─ 修复 Flutter 插件 namespace
│  └─ 修复 Dart 相对 import 为 package 引用
└─ Flutter清理维护工具
   ├─ 清理当前项目构建产物
   └─ 依赖与缓存维护
```

后续 Flutter 动作应增加到本包的固定动作表和对应分组，不再新增独立的顶层扩展。修复组位于开发辅助组内，排在体检之后、清理维护之前；Finder 顶层只显示一个开发辅助入口。

## 项目 SDK 与 Java 版本管理

“安装/切换 Flutter@OpenHarmony SDK”使用 [CPF-Flutter 适配仓库](https://gitcode.com/CPF-Flutter/flutter_flutter) 的实际发布标签，先选择版本，再确认下载及项目绑定；不使用原生 Flutter 发布清单。SDK 按远端标签对应的 commit 放入独立 FVM 缓存，并通过当前项目 `.fvmrc` / `.fvm/flutter_sdk` 使用。切换失败恢复原项目绑定，不执行 `pub get`、不设置 `fvm global`。同名入口同时提供在 [Windows 包](../../WindowsOS@Extension/JobsFlutterTools/README.md) 中。

原生 SDK 和 OpenHarmony SDK 是两个明确的选择入口；一个项目同一时刻使用一套 FVM 绑定。切换入口会更改当前项目所选 SDK，不能把两个入口理解为同时绑定两套。需要并行开发时可使用不同工作目录。OpenHarmony 原生构建还需要配套 DevEco / OHOS SDK 和插件适配；此入口只安装及切换 Flutter SDK。iOS / Android 建议使用上游 Flutter，鸿蒙使用对应适配版本，见[适配方升级说明](<https://gitcode.com/CPF-Flutter/flutter_samples/blob/master/ohos/docs/10_appendix/Flutter-OH版本升级指导.md>)。

“安装/切换Java环境”通过 [jEnv](https://github.com/jenv/jenv) 管理当前项目 `.java-version`，支持复用已安装 JDK，或安装指定主版本后绑定。jEnv 负责版本切换；缺失 JDK 使用现有 Homebrew 安装，不主动升级健康组件。首次确认前说明来源与影响，切换前备份原声明，失败保留或恢复原状态；不会修改 `jenv global`、Shell 启动文件或全局 Flutter JDK 配置。原有 `17` 声明可直接识别。

带 `.java-version` 的右键运行、Android / 鸿蒙打包、体检和 Android SDK 修复会为本次进程解析 Java，设置 `JAVA_HOME` / `PATH`，并用 `GRADLE_OPTS` 固定 Gradle daemon 的 JDK；后台运行会保留这些变量。Flutter 自身仍可能优先采用 Android Studio JDK，`flutter doctor` 显示的 Java 不等于实际 Gradle daemon 的 Java。项目存在 `android/gradle/gradle-daemon-jvm.properties` 时，该 Gradle 配置优先，工具会停止并提示先处理冲突，避免静默使用另一套 JDK。IDE 独立启动及普通终端需自行启用 jEnv 或配置项目 Gradle JDK。查询 SDK、依赖解析、iOS 直达打包和静态操作不强制 Java 环境。JDK 的真实安装路径支持空格和中文，但拒绝各代 Gradle wrapper 解释不一致的美元符、反引号、双引号、反斜杠和控制字符；Flutter 项目路径不受此 JDK 路径限制。

两个新安装入口都无需先有 FVM 绑定。在本包目录只读检查（替换项目路径），不联网、不安装、不写日志或项目配置：

```shell
/bin/zsh ./Scripts/Tools/ManageHarmonyFlutterVersion.zsh \
  --project "/绝对路径/Flutter项目" \
  --check

/bin/zsh ./Scripts/Tools/ManageProjectJava.zsh \
  --project "/绝对路径/Flutter项目" \
  --check
```

## 打包平台与产物

从 `Flutter开发相关辅助工具 → Flutter打包 → iOS / Android / 鸿蒙` 选择平台。文件夹右键和项目内空白处右键的行为一致。平台通过固定动作 `package-ios`、`package-android`、`package-ohos` 传给分发脚本，再转成 `PackageFlutter.zsh --platform ios|android|ohos`，终端不再询问平台。

iOS 直接构建 IPA，无需 fzf；Android 仍用 fzf 选择 APK / AAB / 两者，鸿蒙选择 HAP / APP / 两者。直接调用脚本可用 `--target apk|appbundle|all`、`--ohos-target hap|app|all` 预设产物，全部预设时无需 fzf。未指定 `--platform` 的旧 CLI 调用保留平台选择。非法、缺值或重复的平台参数会在构建前拒绝。

终端保留用途说明、回车确认和日志；构建使用项目 FVM SDK，鸿蒙要求该 SDK 已支持对应构建命令，以及已有 `ohos/` 工程和 DevEco 工具链。菜单选择本身不安装 SDK，不改签名。`fzf` 仍仅用于尚未指定的选择；不自动安装。

## FVM 与体检

“清理当前项目构建产物”和“修复 Dart 相对 import 为 package 引用”是无需 SDK 的静态操作；原生 / OpenHarmony SDK 安装切换与 Java 管理使用各自引导流程。其余执行入口要求项目 `.fvmrc`（或旧 `.fvm/fvm_config.json`）及 `.fvm/flutter_sdk`。缺失时提示先安装/切换项目版本，不会调用全局 Flutter。不执行 `fvm global`、不把 Flutter 写入全局 PATH 或 Shell 配置。其余体检、修复及依赖缓存维护引擎使用该 SDK 内的 Dart 3+，无需额外安装 Dart 包。

原生体检检查 FVM、Flutter 版本声明与实际版本、同源 Dart 及 `flutter doctor -v`。基础 doctor 的警告、错误或无法判定的输出都不能算健康。

Harmony 体检先检查同一套 **FVM 管理的 Harmony Flutter SDK 的基础环境**，再检查 `hap` 构建能力、DevEco/CLT、Node、OHPM、Hvigor、HDC、Java、SDK 编译组件、项目 `ohos/` 结构及已解析原生插件的 `ohos` 声明。只有全部通过才报告健康；不会仅凭模拟器已启动就报告项目可运行。静态插件声明检查不能代替实际构建，联邦插件的替代实现需按失败列表核对。

Harmony Flutter 是适配分支，普通 Flutter 安装并不会自动带来 Harmony 构建能力。可按 [FVM 官方自定义 fork 用法](https://github.com/leoafarias/fvm/blob/main/docs/pages/documentation/guides/quick-reference.md) 先注册所需的适配仓库，再在项目中执行 `fvm use <fork>/<版本或分支> --skip-pub-get`；菜单始终读取该项目绑定。版本选择器的官方发布清单用于原生 Flutter，不把原生版本冒充 Harmony 适配版。多套 DevEco/CLT 并存时通过本次终端的 `TOOL_HOME` 或 `DEVECO_STUDIO_HOME` 指定，体检不改全局环境。

## 修复范围与备份

- **相对 import 转 package**：从“Flutter项目修复 → 修复 Dart 相对 import 为 package 引用”进入。按当前 Dart 文件位置解析相对引用，仅把实际指向本项目 `lib/` 内文件的 `import` URI 转成 `package:<pubspec包名>/...`，例如 `lib/pages/detail.dart` 中的 `../models/user.dart` 转成 `package:demo/models/user.dart`。先预览，再明确确认写入；`package:`、`dart:`、注释、普通字符串、`export` / `part`、生成文件及第三方目录保持原样。此操作不要求 Flutter / FVM，不联网、不修改依赖或 SDK。完整用法见[原脚本说明](<../../../JobsCommand@Flutter/MacOS/小工具/【MacOS】⚙️import =＞package💣.command/README.md>)。
- **Android SDK / platforms**：优先使用项目已有 `sdk.dir`，再参考本机 SDK 环境。按工程 `compileSdk`（或 FVM SDK 的默认值）补齐 platform；优先遵循显式 `buildToolsVersion`，否则选稳定 build-tools。补齐所需 Java/官方命令行工具，校验组件，再备份并更新当前项目 `android/local.properties`。不会安装模拟器镜像，不写 `flutter config`，SDK 许可证仍由本人阅读接受。
- **中文路径**：修复 Dart `import` / `export` / `part` URI 中合法的中文 UTF-8 百分号编码。保留 URI 分隔符、注释和普通字符串；跳过构建及缓存目录。此功能不重命名项目文件夹、不升级依赖。
- **namespace**：从当前项目 `.dart_tool/package_config.json` 定位已解析 Flutter 插件，仅在其 Android Gradle 文件缺少 namespace、且 manifest 有明确 package 时修复。支持 Groovy/Kotlin，已有 namespace 不改，无法判断的插件跳过。不会遍历整个 Pub 缓存。插件可能被多个项目共用，确认前会列出具体文件。

相对 import 修复先回车查看计划，再精确输入 `YES` 写入；正常模式必须在可交互终端执行。日志与原始备份位于终端打印的系统临时目录 `jobs-flutter-imports.XXXXXX/`，分别为 `imports.log` 和 `backup/项目内相对路径`。`RepairPackageImports.zsh --project <项目> --check`（或 `--dry-run`）只读，不创建日志、备份或改写项目；转义、插值、百分号编码等无法安全解释的 URI 保留原样。临时目录可能被系统清理，需要长期保留时复制备份。

中文路径与 namespace 两项先预览，输入 `REPAIR` 才写入；备份在项目 `.jobs_flutter_backups/<时间>/`，`manifest.json` 保存每个原路径与唯一备份文件的映射，同名 Gradle/Dart 文件不会相互覆盖。Android 配置备份在 `android/.jobs-sdk-backup*`。取消或预览不改文件。恢复时应先核对目标文件此后是否有其他修改，再从映射取回原文件。

这些能力基于用户指定的 `JobsCommand@Flutter/小工具/` 中 Android SDK 修复、中文路径修复、namespace 修复和清理维护工具的用途接入；重用了本仓库的 SDK 引导，并收紧了全局安装、缓存扫描及备份范围。源工具是 `.command` 目录，namespace 工具目录名还包含一个字面双引号；安装后不依赖这些外部绝对路径。

## 清理维护

`Flutter开发相关辅助工具 → Flutter清理维护工具` 位于本组末尾，分为两个操作：

| 操作 | 执行内容 | SDK 与确认 |
| --- | --- | --- |
| 清理当前项目构建产物 | 直接删除当前 Flutter 项目的已识别产物，不运行工程脚本或构建命令。 | 无需 Flutter / FVM；先列出实际路径，输入 `CLEAN` 才清理，回车取消。 |
| 依赖与缓存维护 | 保留原维护编号菜单：依赖刷新、`clean + pub get`、主动升级、Pub 缓存修复及所选缓存清理。 | 使用项目 FVM；编号回车取消，命令二次确认，缓存删除要求 `CLEAN`。旧 `maintenance` URL 动作保持兼容。 |

项目产物清理沿用原 `JobsTerminalOpener` 白名单：根目录 `build/`、`.dart_tool/`，以及已识别 `android/`、`ios/`、`ohos/` 的构建和中间产物、桌面 Flutter ephemeral；Xcode 默认 DerivedData 只删除 `info.plist` 的 `WorkspacePath` 精确归属当前 `ios/` 工程的 `Build/`。保留源码、锁文件、Pods、`oh_modules`、`node_modules`、签名、FVM SDK、共享缓存和无关项目产物，不推断自定义输出。整份计划先校验，目标或其父路径是符号链接时停止。入口仅接受 Flutter 根目录，不向父目录寻找工程。

依赖与缓存维护只执行选中的操作，失败立即停止。共享 Pub、Gradle 或当前 FVM SDK 缓存清理会显示路径并要求 `CLEAN`；不会删除 Pub 可执行文件、Gradle 配置/凭据或项目锁文件。共享缓存会影响共用它的项目，重建可能重新下载。请先关闭相关构建进程；Windows 正在使用的 SDK 文件可能被系统锁定，失败会如实报告，保留尚未删除的文件。macOS 另提供当前项目 iOS 生成缓存清理，不删除 `ios/Flutter` 源文件或全局 DerivedData。

## 迁移

安装本包后停用旧 Flutter 独立菜单，包括 Terminal 的旧 pub-get 项。Terminal 的 Flutter 根目录清理入口归入本包，原生 iOS/Xcode、Android、鸿蒙工程清理保留在原菜单。旧 Flutter 安装入口会转到本包；旧源代码、运行数据及卸载入口保留供兼容和排查。卸载统一组不会重新启用已停用的旧菜单。

现有运行、依赖提取、SDK 查询/管理、打包和代码生成流程复用本仓库对应工具；这些入口及附带 worker 都约束到项目 FVM。静态产物清理在 FVM 检查前分发，包内 `Tools/CleanBuildArtifacts.zsh` 与 `JobsTerminalOpener/Scripts/CleanBuildArtifacts.zsh` 保持逐字节一致，安装后不依赖 Terminal 包或源码仓库。更新这些工具时应同步本包资源并运行回归测试。Mac / Windows 共用的 `FlutterProjectTools.dart` 必须保持逐字节一致。

相对 import 修复由包内 `Tools/RepairPackageImports.zsh` 独立承接，与 `JobsCommand@Flutter/MacOS/小工具/【MacOS】⚙️import =＞package💣.command/` 中主脚本保持逐字节一致，随 `Tools` 资源文件夹打包；安装后的菜单不读取外部脚本仓库。动作 `repair-package-imports` 在 FVM 门禁前分发，旧 `repair-imports` 继续只处理中文路径编码。

## macOS 安装与验证

运行 `【MacOS】安装Flutter开发辅助工具Finder扩展.command`，或在仓库总安装器勾选“Flutter开发相关辅助工具”。需要完整 Xcode。扩展已启用后才迁移旧菜单；配置备份保留在 `~/Library/Application Support/JobsTerminalOpener/FlutterMenuMigration.*`。

隔离验证：`python3 Tests/BuildArtifactDispatchTests.py` 不需要 Dart，使用临时工程和独立资源副本验证无 FVM 分发、取消、原生平台产物、DerivedData 归属、依赖保留、链接保护及旧维护的 FVM 门禁。`python3 Tests/MenuTransportTests.py` 编译真实 Swift 菜单与传输代码，核对清理二级菜单、新动作与旧维护 URL，并截获打开请求，不运行用户工程。

`python3 Tests/PackageImportDispatchTests.py` 通过临时工程与真实伪终端核对相对路径和条件 import 转换、注释 / 字符串保护、第三方 / 生成 / 链接跳过、取消、精确备份、CRLF、只读零写入、Flutter 声明和无 SDK 分发；同时校验独立脚本与包内资源逐字节一致。

`ruby Tests/ProjectJavaManagerTests.rb` 使用假 jEnv / Homebrew / JDK 验证 Java 安装分支、项目声明、取消、中断恢复和 Gradle 参数；`ruby Tests/HarmonyFlutterVersionTests.rb` 使用假 Git / FVM 验证鸿蒙标签、精确 commit、缓存、影子绑定及安全发布；`ruby Tests/NativeFlutterReturnTests.rb` 验证受管鸿蒙 SDK 切回官方 SDK、失败恢复与未知 fork 保护；`ruby Tests/VersionManagerDispatchTests.rb` 验证新入口无需现有 FVM、Java 绑定传递及错误退出。测试不安装真实 SDK、不修改用户工程。

维护引擎回归可先设置 `JOBS_TEST_DART` 为某个已安装 FVM SDK 内的原生 Dart，再运行 `python3 Tests/ToolsTests.py`，使用假的 SDK/插件/缓存；可用 `JOBS_TEST_DART=/项目FVM路径/bin/cache/dart-sdk/bin/dart` 指定测试 Dart。`ruby Tests/PackagingMenuTests.rb` 复用旧打包夹具，并额外验证三平台直达、项目 FVM、包型选择、取消、非法参数与分发退出码；不执行真实构建。完整发布验证另运行仓库 `Tests/FlutterInstallerIntegrationTests.rb` 和 Xcode build / codesign 校验。
