# Flutter 菜单实现

安装器的子功能清单位于当前用户应用支持目录 `JobsFinderExtensions/flutter-tools-features.conf`：总安装器按本次勾选覆盖，独立安装启用全部 19 个动作，独立卸载清除清单。脚本资源仍统一打包到 App，禁用动作由 Finder 与宿主在派发前拦截。

菜单、FVM 要求、修复范围与安装流程见 [功能说明](../README.md)。`Tools/DispatchFlutterTools.zsh` 是唯一分发入口；`Tools/FlutterProjectTools.dart` 处理双层体检、两类代码修复与维护；`RepairAndroidSdk.zsh` 复用 `AndroidSdkSupport.zsh` 的组件引导。`RetireLegacyFlutterMenus.zsh` 只在统一扩展已启用后停用旧 Flutter 入口。

`ohos-sdk-manage` 在 FVM 门禁前交给 `Tools/ManageHarmonyFlutterVersion.zsh --project <目录>`，从 CPF-Flutter 源查询发布标签，下载到独立缓存后固定项目 FVM；`java-manage` 同样在门禁前交给 `Tools/ManageProjectJava.zsh --project <目录>`，管理 jEnv 与 `.java-version`。两个脚本均支持 `--check` 只读模式，安装后使用 App 内自包含资源。存在项目 Java 声明时，分发器通过 `pj_bind_project_java` 为普通工具注入本次 `JAVA_HOME`、`PATH` 和 Gradle daemon 参数，失败即停止；静态清理、静态 import 修复和版本管理不依赖 Java 绑定。

打包子菜单用 `package-ios` / `package-android` / `package-ohos` 固定动作传递平台，分发为 `PackageFlutter.zsh --project <目录> --platform ios|android|ohos`。原 `package` 动作保留兼容旧请求。`--platform` 跳过平台选择；fzf 仅在还需选择平台或产物时检查。

`Flutter清理维护工具` 下的 `clean-build-artifacts` 动作在 FVM 门禁前分发：用包内 `CleanBuildArtifacts.zsh --detect` 再次确认 Flutter 根目录，然后进入该脚本的路径预览和 `CLEAN` 确认。包内脚本与 `JobsTerminalOpener/Scripts/CleanBuildArtifacts.zsh` 保持逐字节一致，通过 `Tools` 文件夹资源随 App 打包；不要求安装 Terminal 包或存在源码仓库。静态清理不运行 `flutter clean` / `pub get`，也不删除共享缓存。

清理脚本用系统 Perl 及其标准模块 `Encode` / `JSON::PP` 保守解析 `dependencies.flutter.sdk`：支持常见缩进块、单行 flow、单双引号和 UTF-8 BOM；拒绝重复依赖段、重复 Flutter/SDK 键，以及环境、开发依赖或说明正文里的误导声明。静态清理与统一菜单一样只要求合法 Flutter 依赖声明，不要求存在 `lib/`；其余旧动作保留原有目录检查。清单仅按 UTF-8 文本读取，最大 1 MiB；不执行 YAML 标签、工程脚本或安装额外解释器。

同级的“依赖与缓存维护”继续使用旧 `maintenance` 动作，保留项目 FVM 检查，再交给 `FlutterProjectTools.dart` 的原编号菜单。`Tests/BuildArtifactDispatchTests.py` 使用独立资源副本与临时目录验证两条路径的权限边界；`Tests/MenuTransportTests.py` 验证真实菜单层级和动作传输。

`Flutter项目修复` 下的 `repair-package-imports` 动作同样在 FVM 门禁前执行：先用 `CleanBuildArtifacts.zsh --detect` 核验当前层 Flutter 声明，再把选中的绝对路径作为 `--project` 参数传给包内 `RepairPackageImports.zsh`。该脚本仅使用系统 zsh / Perl，按引用文件位置解析到本项目 `lib/` 的相对 import，预览并确认后备份和写入，不调用 Flutter / Dart / FVM。与 `JobsCommand@Flutter/MacOS/小工具/【MacOS】⚙️import =＞package💣.command/` 的主脚本保持逐字节一致；`Tools` 为 Xcode 文件夹资源，新脚本自动随 App 打包。原 `repair-imports` 动作及 Dart 引擎继续处理中文 URI 编码，两项互不替代。
