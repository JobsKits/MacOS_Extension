# Flutter 项目配置与运行工具

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口与执行顺序](#jobs-toc-heading-2)
- [二、SDK、配置与交互](#jobs-toc-heading-3)
- [三、Gradle 下载与分层依赖边界](#jobs-toc-heading-4)
  - [3.1、平台快照提取与导入](#platform-archives)
  - [3.2、Flutter 平台资源具体包含什么](#precache-faq)
  - [3.3、原生库组合操作的实际调用链与重叠](#native-combination-faq)
- [四、平台准备、设备与实际运行](#jobs-toc-heading-8)
- [五、里程碑、日志与退出码](#jobs-toc-heading-9)
- [六、验证范围](#jobs-toc-heading-10)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**下载版本与组件：** 运行器在 SDK 安装 / 首次补齐及选定平台预缓存之前，先展示项目声明 Flutter、实际解析的 SDK 根路径、本地 Git 精确 tag / 提交或本地版本记录、下载宿主架构、目标平台和 Engine 提交；不靠执行 Flutter / Dart 探测版本。Git 查询只读、禁止隐式联网且单次最多 5 秒，无法确认就明确未解析。Darwin 下载架构按物理 ARM 能力识别，兼容 Rosetta。Dart 目标版本只采信 SDK 明确声明，或与目标 Engine 一致的版本 JSON / 当前缓存 stamp；`.old` 和不匹配的缓存不当作本次目标。尚无可信记录时显示“版本尚未解析，待目标 SDK 下载完成后确认”，目标版本展示不代表已经安装验收。

已打开的终端使用启动时的脚本快照，源码改动不替换当前下载进程；安装 / 更新菜单后重新发起才加载新的上下文展示。版本上下文与重试提示进入本次操作日志，原生机器输出文件及退出码保持原路径。

**SDK 获取策略：** 必需 SDK 的下载、安装中的网络获取及 Flutter 首次启动补齐 Dart / 引擎组件，默认失败自动持续重试，直到成功或用户按 Ctrl+C / 结束进程；不再询问是否重试，也不设次数或总时长上限。退避默认为 2、4、8、16、30 秒；`JOBS_SDK_RETRY_DELAY` / `JOBS_SDK_RETRY_MAX_DELAY` 可配置。保留工具原生进度与已有缓存，每次获取输出追加保存到原日志旁的 `.attempts.log`；版本选择、真正的许可证 / 权限操作及原始入口确认保留。确定的权限、磁盘、架构、参数或不存在版本错误直接说明原因并停止；项目构建与代码生成失败不整体重放。`--check` / `--help` 继续只读。

运行和打包在实际 `run` / `build` 前，先为已选设备 / 打包平台执行对应 `flutter precache --ios|--android|--web|--macos|--ohos`，平台资源获取失败持续重试；不会因此反复构建 App。鸿蒙先检查适配 SDK 是否支持 `--ohos`，不支持时在构建前明确说明。

> 本目录承接Flutter右键菜单的实际环境准备、依赖解析和运行验收；平台、许可与设备状态均以真实工具结果为准。

运行器的设备、型号和系统选择使用 fzf 全屏临时界面，退出后恢复原日志，避免 Terminal 内嵌高度模式重绘时留下重复菜单。iOS 列表来自当前 Xcode 的 CoreSimulator，包含已关闭的模拟器；Device Hub 看不到时，检查过滤器是否为 `All Devices` / `Simulators`，并展开 `Available` 分组。历史测试设备需要按 UUID 注销，不能直接删除设备目录或共享 Runtime。

“从终端运行 Flutter 项目”由 [RunFlutterProject.zsh](./RunFlutterProject.zsh) 承接。项目 FVM SDK 缺失或断链时，自动用本机 [**fvm**](https://fvm.app) 下载 / 初始化并绑定声明版本；安装与绑定前显示版本、FVM 路径和完整日志路径。工具原始输出约每秒显示到终端，保留工具提供的下载百分比、速度、剩余时间及回车刷新，同时分别落盘到 `<操作日志>.fvminstall` / `<操作日志>.fvmuse`。已有 SDK 的首次版本检查可能补下载 Dart / SDK 组件，同样显示并保存到 `<操作日志>.version`；后台日志按回车 / 换行分帧，下载进度不必等任务结束。工具没有输出时不伪造进度。安装 / 初始化、绑定与版本首启的单次窗口均为 1800 秒；超时结束当次后自动继续重试，设备 JSON 查询不输出进度。已打开终端不会更新脚本副本；菜单安装 / 更新后重新发起才加载修改，已有下载可在另一终端执行 `tail -f '<本次操作日志>.fvminstall'` 查看，`Ctrl+C` 仅退出该查看窗口。

SDK 安装 / 切换的最终版本核验和 SDK 查看器的候选探针同样显示首次缓存下载输出，并单独保留供解析的版本 JSON；不会把终端展示文案塞入机器结果。鸿蒙 Flutter 的 Git 克隆显式启用原生进度，在日志管道中也显示接收对象、百分比等信息。项目体检、Pub 拉取和代码生成按字节流过滤颜色，工具仅用回车刷新时不必等待换行。

一键配置、目标平台预缓存和实际构建沿用既有实时输出通道；直接 SDK 归档下载、FVM 安装、鸿蒙克隆及首次调用补齐组件的详情均在终端或配置面板中可见，同时保留原始日志。百分比、速度及剩余时间仅展示工具实际提供的值；工具没有输出时不估造。未重新安装菜单的旧 App 资源、已打开的旧终端和既有后台会话保持其启动时的实现。

一键迁移由 [【MacOS】一键迁移Flutter依赖.zsh](./【MacOS】一键迁移Flutter依赖.zsh/README.md) 和同目录 [FlutterDependencyMigration.dart](./FlutterDependencyMigration.dart) 承接，保留同目录 Pub 提取 / 导入引擎。`export-all-dependencies` / `import-all-dependencies` 在分发器的 SDK 绑定门禁前进入文件迁移；可复用项目 Dart 或本机已有原生 Dart，不下载 SDK、不改变工程绑定。按内容识别迁移目录或原始 Pub / Gradle 缓存，支持目录改名与父目录组合；导入先预检，精确 `YES` 后才写入，冲突停止。提取默认私库，非空才全提取，ZIP 和删除默认值见入口自述；完整材料范围见[一键迁移与底稿](../../README.md#one-click-migration)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、入口与执行顺序 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

Finder 的“🚀 一键配置 Flutter 项目”由 [SetupFlutterProject.zsh](./SetupFlutterProject.zsh) 承接。先选择工程已有目标及 Flutter 来源；Android / OpenHarmony 再选择 Java，其它目标跳过 JDK。准备 SDK、平台工具链及平台资源，下载所需 Gradle，解析 Pub，再选择启动配置、准备目标依赖并实际构建，最后选择设备进行运行验证。Apple 配置生成也共用选定入口、flavor、模式和 defines。macOS 处理 Android、iOS、macOS、Web、OpenHarmony 已有目标，不自动生成平台源码；鸿蒙须使用适配 Flutter，DevEco / SDK 许可保留官方流程。

Web / 鸿蒙工具准备由 [工程依赖工具链模块](./【MacOS】工程依赖工具链.zsh/README.md) 承接。额外 JS 工程检查 Node 版本文件、`engines.node` 与锁定包管理器，复用健康候选，缺失时提供安装 / 选择并复检；没有 `package.json` 时不要求 Node。鸿蒙发现 DevEco / CLT 并在本进程激活和核验 SDK、Node、OHPM、Hvigor、HDC、Java；缺少专有组件时打开官方安装 / SDK Manager，完成后可在本流程复检，不把目录存在或平台预缓存成功视为工具链完成。

“📚 下载Gradled分发与构建插件”由 [DownloadProjectGradle.zsh](./DownloadProjectGradle.zsh) 承接，只准备 Android 项目固定 Wrapper 版本和配置阶段构建插件。它优先读取本机环境记录中的 Java，其次解析 `.java-version`，均未配置时才使用当前系统 JDK。

“拉取Flutter项目工程相关依赖”包含六类包源；“提取Flutter项目工程依赖”和“导入Flutter项目工程依赖”处理本地快照。“安装/切换Flutter运行环境”统一三类 SDK 切换；“Flutter 资源与构建依赖”依次提供 Gradle 下载、Flutter 平台资源下载和“准备原生库与构建依赖（组合操作）”。各类依赖独立入口由 [FetchProjectDependencies.zsh](./FetchProjectDependencies.zsh) 承接，与一键配置共用 [ProjectDependencies.zsh](./ProjectDependencies.zsh)。`--kind android|pods|spm|ohos|native|precache|web` 固定对应菜单动作，`--platform` 可预先指定适用目标；未指定且存在多个适用目录时使用 fzf 选择。只为所选类别准备必要前置条件，现存健康本机环境记录可复用，失效记录停止并提示重新一键配置。Web 额外 JS 安装不要求 Flutter SDK，其他类别按需校验或准备项目 SDK。

```shell
/bin/zsh ./SetupFlutterProject.zsh \
  --project /绝对路径/Flutter项目

/bin/zsh ./SetupFlutterProject.zsh \
  --project /绝对路径/Flutter项目 \
  --sdk-only

/bin/zsh ./DownloadProjectGradle.zsh \
  --project /绝对路径/Flutter项目 \
  --java-home /绝对路径/JDK

/bin/zsh ./FetchProjectDependencies.zsh \
  --project /绝对路径/Flutter项目 \
  --kind native \
  --platform android
```

三个入口均支持 `--check`，只读、不联网、不安装、不写日志。配置与单类依赖入口的检查仅盘点工程、文件边界和计划，不代表 SDK、原生依赖、签名或设备已经健康。`--sdk-only` 只运行 SDK / Gradle / Pub 子流程与 doctor，不执行目标原生依赖构建或运行验证；`--distribution-only` 使 Gradle 下载入口只准备分发包和 Wrapper 缓存，尚不解析插件。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、SDK、配置与交互 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- Flutter 默认 FVM，可复用健康项目 SDK，或调用现有安装 / 切换工具；选择系统模式时可以复用 PATH、指定本机 SDK 或通过 Homebrew 安装 Flutter。Java 默认 jEnv，可选择健康本机 JDK 或安装指定主版本；系统模式保持原 `.java-version` 不变，不读取其损坏的 jEnv 声明。
- 单选统一使用 fzf：Enter 选择，← 返回上一层，Esc 取消。来源选择阶段取消不修改项目；后续已完成的安装 / 绑定不会因返回或取消自动撤销。缺少 fzf 时可确认通过健康 Homebrew 安装；Homebrew 也缺失时由 [SetupHomebrew.zsh](./SetupHomebrew.zsh) 复用原安装内核，精确 `YES` 选择系统标准目录，其它输入选择用户目录，安装失败不改走其它位置。缺 CLT 时自动打开 Apple 官方界面并每 10 秒复检，安装和本人许可完成后自动继续；不写 Shell 启动文件。
- 本机选择保存在工程 `.jobs/flutter-environment.json`，字段为 `Platform`、`FlutterMode`、`FlutterPath`、`JavaMode`、`JavaHome`。系统模式作用于本流程、后续 Gradle 下载和单类依赖入口；其它原有运行 / 打包菜单仍遵循各自 FVM / jEnv 规则，已有终端与 IDE 不会切换。
- Android `local.properties` 只更新本机 `flutter.sdk`，平台模块再合并 `sdk.dir`；原有其它字段保留。环境记录与本机配置写前留快照并检查并发、链接、硬链接及异常文件；不改全局 Flutter、jEnv global、Shell 启动文件或系统代理。
- 跨电脑或跨系统路径失效时停止使用旧环境；重跑配置可以重新选择本机 SDK，并先保存旧配置。取消、失败与后续诊断不回滚已完成的安装和依赖解析；恢复文件前请核对快照和当前内容，保留并发修改。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、Gradle 下载与分层依赖边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

版本来自 `android/gradle/wrapper/gradle-wrapper.properties` 中固定的正式 `x.y[.z]-bin/all.zip`，不因 Java 版本自动升级 Gradle 或 AGP。按 [Gradle 官方运行时兼容矩阵](https://docs.gradle.org/current/userguide/compatibility.html) 检查 Java 8–27；Gradle 9 及以上须 Java 17 或更新版本。项目 daemon JVM criteria 冲突明确停止。

采用 Wrapper 已固定的 SHA256；未配置摘要时只从 Gradle 官方端点取摘要，不能以镜像自身摘要替代信任根。分发包按来源分别保留断点片段，优先项目来源，再用 Gradle 官方备用源；选择备用线路时加入腾讯 Gradle 镜像，并为本次构建使用阿里云 Google / Gradle Plugin / Public Maven 镜像。镜像线路可用性取决于当前网络，脚本不修改用户仓库配置或系统代理。

分发下载连接超时 10 秒、低速 30 秒停止，每轮同源最多两次后自动继续下一轮，单次默认 300 秒，无总尝试上限。插件 `Gradle help` 默认 900 秒；HTTP 连接 / 读取分别 15 / 30 秒，仅对明确网络异常重试一次；认证、权限、证书、配置或兼容错误不重试。Pub 同样默认 900 秒，仅明确网络异常重试一次，不执行 `pub upgrade`。

| 环境变量 | 默认 | 允许范围 |
| --- | --- | --- |
| `JOBS_GRADLE_DOWNLOAD_TIMEOUT` | 300 秒 | 10–1800 秒 |
| `JOBS_GRADLE_TASK_TIMEOUT` | 900 秒 | 30–7200 秒 |
| `JOBS_PUB_GET_TIMEOUT` | 900 秒 | 30–7200 秒 |
| `JOBS_FLUTTER_RUN_TIMEOUT` | 1800 秒 | 30–7200 秒 |

已验分发包保存在用户 Library 的 `Caches/JobsFlutterTools/gradle`，随后由 [WrapperDistributionCache.zsh](./WrapperDistributionCache.zsh) 按 Wrapper URL 散列、`distributionBase/path`、`zipStoreBase/path` 和有效 `GRADLE_USER_HOME` 安全预置到真实 Wrapper ZIP 缓存。它使用与 Wrapper 相同的 Java 文件锁，不覆盖在途或摘要不同的缓存，不伪造 `.ok`；再用所选 Java 启动项目实际 Wrapper `--version`，60 秒内核对版本与本地缓存复用。

Gradle `help` 会执行当前工程构建配置，下载 / 解析 AGP、Kotlin 等配置阶段插件并写正常缓存。成功不代表全部 App 编译依赖、所有 flavor、签名、安装或业务功能通过。新工程先准备分发包，再 `pub get`，最后预热插件，避免 Flutter 插件索引尚未生成导致误报。独立下载入口若缺少 Android SDK、Flutter 本机配置或 Pub 索引，会返回真实失败并提示先一键配置。

| `--kind` / 对应模块 | 执行内容、前提与输出 |
| --- | --- |
| `android` / `pd_android_dependencies` | Android SDK / Java / 固定 Wrapper 健康后，临时 init script 为各子项目注册解析任务，严格解析所有 `canBeResolved` 配置，不用 lenient 模式掩盖缺包；Maven AAR / JAR 进入实际 Gradle 缓存。included builds、自定义任务和延迟下载仍需目标构建验证。 |
| `pods` / `pd_pods_dependencies` | 仅已有 iOS / macOS 目录，沿用 Podfile、锁文件、Gemfile / Bundler 执行 `pod install`，缺 Podfile 明确跳过。输出为目标 Pods 与正常 CocoaPods 缓存，不执行 `pod update`。 |
| `spm` / `pd_spm_dependencies` | 按当前 Flutter 配置策略执行可用的 `--config-only`，不修改全局 SPM 开关；优先顶层 workspace，多容器明确选择，然后 `xcodebuild -resolvePackageDependencies`。检测到 `Package.resolved` 时要求锁定版本，包与二进制制品通过 `-clonedSourcePackagesDirPath` 进入项目 `.jobs/dependencies/spm`，供归档 / 还原复用。 |
| `ohos` / `pd_ohos_dependencies` | 要求 `oh-package.json5`、健康 OHPM 和工程 `hvigorw`，执行 `ohpm install` 后同步 Hvigor；沿用工程声明与锁文件，不安装全局最新版 Hvigor。 |
| `native` / `pd_run_target_dependencies` | 先复用当前目标对应平台依赖步骤，再用所选 SDK 和启动参数真实 `flutter build`：Android 为 APK，iOS 加 `--no-codesign`，macOS / Web 使用对应构建目标，OpenHarmony 为 HAP。会编译并触发 FFI Hooks / CMake / 插件延迟下载，不安装或启动 App。 |
| `precache` / `sr_precache_target` | 下载同套 Flutter 的目标平台资源；这是 Flutter 引擎缓存，不代替 Android SDK / NDK / CMake、Apple 或 OpenHarmony 工具链。 |
| `web` / `pd_web_dependencies` | 只处理根目录或 `web/` 下已有 `package.json` 的 JS 工程；唯一锁文件决定 npm / pnpm / Yarn 及锁定安装参数，缺锁或多锁停止。无 `package.json` 明确跳过，不添加 JS 依赖；生命周期脚本会执行，`npm ci` 会重建 `node_modules`。 |

一键配置在 Pub 之后复用上述目标步骤，再以同一入口、flavor、模式和 defines 准备原生库，最后进入已有实际运行验收。只解析依赖树、`Gradle help` 或 SDK 下载完成不能代替这个构建结果。Apple 构建仅 macOS，Windows 桌面仅 Windows，Linux 桌面须在 Linux 宿主；当前 Mac 单项选择器不提供 Windows / Linux 原生目标。版本、target、flavor、模式与架构共同限定成功范围，不能据此保证其它配置或未来构建全部离线。私有仓库认证、许可、签名及供应商二进制支持范围仍需本人处理。

原生依赖日志按阶段保存到本次 `JobsFlutterEnvironment.*`，`JOBS_NATIVE_DEPENDENCY_TIMEOUT` 可控制实际原生构建上限，默认 3600 秒。失败或取消停止下游流程，已经下载的正常缓存及已完成的工程改动保留。Pub 的原有快照格式仍只处理包源码、许可证与清单；平台缓存使用下面的独立配对快照，不与 Pub 格式混用。

### 3.1、<span id="platform-archives">平台快照提取与导入</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[ArchiveProjectDependencies.zsh](./ArchiveProjectDependencies.zsh) 接收 `--mode export|import`、`--kind gradle|pods|spm|ohos|native|precache|web`、`--project`，可用 `--platform` 指定当前工程适用目标，`--directory` 指定已存在的输出父目录或完整输入快照；缺少目录参数时在终端输入 / 拖入，空输入取消。`--check` 只展示静态计划，不调用 SDK、联网、写日志或复制文件。运行时复用本机环境记录或项目 FVM 的健康 Flutter / Dart，不在此入口安装另一套 SDK。

```shell
/bin/zsh ./ArchiveProjectDependencies.zsh \
  --project /绝对路径/Flutter项目 \
  --mode export \
  --kind gradle \
  --directory /已存在的输出父目录

/bin/zsh ./ArchiveProjectDependencies.zsh \
  --project /绝对路径/Flutter项目 \
  --mode import \
  --kind gradle \
  --directory /完整快照目录
```

Gradle 在 Maven `modules-2` 与固定 Wrapper 分发间选择组件；OHOS 在 OHPM `oh_modules` 与 Hvigor 缓存间选择，分别建立兼容键和快照。共享缓存可能含其它工程或平台的包，终端明确显示来源与目标；不提取认证、全局配置、daemon、Flutter SDK 源码或 Dart runtime。SPM 快照仍使用项目 `.jobs/dependencies/spm`，拉取时定位当前 Flutter / Xcode 的实际 SourcePackages，并通过相对链接让配置生成和实际构建消费同一缓存；已有构建缓存先查冲突再融合，原目录留备份。平台资源 v2 只收 `bin/cache` 白名单中的 artifacts、Web SDK、缓存引擎包和配对 stamp，载荷完成后最后写标记；旧 v1 只还原 artifacts，不补造 Web SDK 或标记。Web 为 `node_modules`，原生扩展要求同宿主 / Node 环境；native 为当前目标构建缓存，可能包含业务二进制。逐类范围见[快照矩阵](../../README.md#dependency-archives)。

内核保留 `Manifest.lock`、Cargo / Yarn 等功能锁，只排除明确的瞬时锁与日志。Pods 的插件头链接可物化到已核验的解析 Pub 包根：包配置、普通包清单名称、最终链接边界与导出前后状态均需一致；不会放开任意外部路径。其它层仍只物化来源根内的有效链接，清单不保留原机器绝对路径。

包内 [NativeDependencyArchive.dart](./NativeDependencyArchive.dart) 是双端共用的数据内核：校验宿主 / 工具版本、组件、工程配置与锁指纹、目录边界及逐文件 hash；导入先完整预检，再精确 `YES` 并复检后写入。同名不同内容拒绝覆盖，不执行归档中的脚本，不自动联网或启动包管理器。恢复完成后仍须由对应拉取 / 构建入口验证，不能保证任意跨宿主、flavor、架构或未来版本全部离线。

### 3.2、<span id="precache-faq">Flutter 平台资源具体包含什么</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

`precache` 把选中 Flutter SDK 的平台制品写入其 `bin/cache`，具体子目录随版本变化。Android 包含引擎制品与 `gen_snapshot` 等编译工具；`libflutter.so` 是 Android Flutter 引擎的原生库形态，见 [Android 官方说明](https://docs.flutter.dev/deployment/android)。Apple 制品可包含 `Flutter.xcframework` / 桌面框架，Web 包含编译 SDK 及配套 JS / Wasm 渲染资源；参见[上游缓存清单](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/flutter_cache.dart)、[制品名](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/artifacts.dart)与 [Web 渲染说明](https://docs.flutter.dev/platform-integration/web)。这些是资源类别示例，不是所有 SDK 版本共同固定的文件列表。

[当前 `PrecacheCommand`](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/commands/precache.dart)将 `--android` 扩展为 `android_gen_snapshot`、`android_maven`、`android_internal_build`；后者是 Flutter 自身制品，不等于解析工程所有 Maven 依赖。该动作也不代替工程 Pub / Pods、完整 Android SDK / NDK / CMake、Xcode 或 DevEco。`sr_precache_target` 只为所选目标调用此命令，已经就绪的缓存由 Flutter 自己判断是否复用。

### 3.3、<span id="native-combination-faq">原生库组合操作的实际调用链与重叠</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

`fd_describe_dependency_kind` 在首次确认之前按行展示 `precache` / `native` 的真实命令、示例、写入位置和完成边界；子项缩进，一行一个要点。只负责自述，不执行 SDK 或下载。

单项 `FetchProjectDependencies.zsh --kind native` 的真实链为 `fd_run`：选择一个已有目标 → `fd_prepare_flutter` 校验 / 准备 SDK → `sf_fetch_dependencies` 运行 Pub → Android 的 `fd_prepare_android` 或 Apple 的工具链检查 → `pd_run_target_dependencies`。后者先调用该目标的 Maven、Pods + SPM、OHPM / Hvigor 或 Web JS 单类内核，再进入 `pd_native_dependencies` 的实际 `flutter build`。Mac 对 Android 构建 APK、iOS 添加 `--no-codesign`、macOS / Web 使用相应目标、OpenHarmony 构建 HAP；保留选中的入口 / flavor / 模式 / defines。

[FFI build / link hooks](https://dart.dev/tools/hooks)、CMake、NuGet 或其它延迟依赖只有在工程及该目标的构建链需要时才会触发；NuGet 常见于 Windows 桌面，不能理解为 Mac 每次都下载 NuGet。Mac 这个单项链没有显式 `sr_precache_target` 步骤，Windows `native-dependencies` 则在构建前显式执行所选目标 `precache`。Flutter 构建本身还可能检查 Pub 和引擎缓存，所以与单类入口有前置重叠；已有缓存通常复用，不能据此承诺永不重新请求网络。

一键配置在前面的平台阶段已预缓存资源，再在 Pub 之后复用 `pd_run_target_dependencies`，并把同一启动配置带到后续运行确认。组合准备只构建、不安装 / 启动 App，不扩成所有平台工具链，也不保证其它配置全部离线。

## <span id="jobs-toc-heading-8" data-jobs-toc="v2">四、平台准备、设备与实际运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[SetupFlutterPlatform.zsh](./SetupFlutterPlatform.zsh) 组合现有 Android 完整工具内核，准备 SDK / 命令行工具、读取项目和 Flutter 默认的 compileSdk / NDK / CMake 需求，再精确安装所需组件。许可证由本人阅读选择，未确认全部许可接受不标记完成。工具所需临时 Java 不覆盖构建选择的 Java。

[SetupFlutterRun.zsh](./SetupFlutterRun.zsh) 为 Apple 平台发现完整 Xcode，必要时选择其它安装或打开 Mac App Store；`DEVELOPER_DIR` 仅对本流程生效。首次组件与许可必须本人在 Xcode 完成。存在 Podfile 时准备 CocoaPods，再在 Pub 之后执行 `pod install`；优先平台目录的 Gemfile，其次工程根 Gemfile，存在固定 CocoaPods 的声明时沿用 Bundler。缺少 Bundler 时依 `Gemfile.lock` 的 `BUNDLED WITH` 补齐对应版本到当前 Ruby 的用户级 Gem 目录，安装后复检，不忽略锁定版本。安装复用原 Jobs CocoaPods 脚本的“Homebrew 优先 → Homebrew Ruby 用户级 Gem 兜底 → pod 二次复检”核心，健康组件不升级，不自动按 IP 改全局 Gem 源，不写 Shell 配置。

Web 目标先验证 Chrome / Edge 可执行性，缺少浏览器时可选择通过 Homebrew 官方 Cask 安装 Chrome，或指定本机已有可执行文件；复检通过才继续。`CHROME_EXECUTABLE` 仅对本流程生效，不会因为存在 `web/` 就宣称浏览器已就绪。

组合内核与来源对应如下；随包功能运行时只依赖本目录资源，不依赖参考仓库的绝对路径。

| 组合模块 | 复用来源与边界 |
| --- | --- |
| [SetupHomebrew.zsh](./SetupHomebrew.zsh) | 复用用户指定 [CocoaPods 安装脚本](../../../../../JobsCommand@iOS/Cocoapods/【MacOS】⚙️双击安装Cocoapods.command/【MacOS】⚙️双击安装Cocoapods.command) 的健康检测、官方安装及复检核心；精确 `YES` 为系统目录，其它输入为用户目录；CLT 由 Apple 官方界面处理，每 10 秒自动复检后继续；仅当前进程激活 PATH，不写 profile。fzf 已健康但后续 jEnv/JDK、系统 Flutter、CocoaPods 缺 Brew 时同样进入该引导。 |
| Apple 平台 / CocoaPods | 同一原脚本的 Homebrew 优先、Homebrew Ruby / 用户级 Gem 兜底及安装后复检；按工程 Ruby 与锁定 Bundler 版本检查兼容，保留项目 Pod 锁定策略。 |
| Android 工具链与 AVD | [AndroidSdkSupport.zsh](./AndroidSdkSupport.zsh) 的 SDK / Java / 命令行工具 / emulator 和完整设备、映像选择内核；平台组件由工程及同套 Flutter 配置确定。 |
| iOS 模拟器 | [现用完整模拟器脚本](../../../JobsIOSSimulatorCreator/Scripts/CreateIOSSimulator.zsh) 的随包副本，保留型号 / Runtime / 创建 / 启动交互和取消边界。 |

设备列表按目标平台过滤，空列表提供重载及模拟器完整入口。iOS 由随包 [SetupCreateIOSSimulator.zsh](./SetupCreateIOSSimulator.zsh) 提供完整型号、Runtime、创建与启动交互，源码与现用 [iOS 模拟器脚本](../../../JobsIOSSimulatorCreator/Scripts/CreateIOSSimulator.zsh) 一致；Android 的 [SetupCreateAndroidSimulator.zsh](./SetupCreateAndroidSimulator.zsh) 显式展示自述后执行 [AndroidSdkSupport.zsh](./AndroidSdkSupport.zsh) 的完整已有 AVD / 新建流程，不以只加载函数冒充已创建设备，不依赖其它仓库绝对路径。

[SetupFlutterRun.jxa](./SetupFlutterRun.jxa) 读取 `.vscode/launch.json` 的 JSONC 和 `.run/*.run.xml`，只解析 `target`、`flavor`、debug / profile / release、dart-define 及 verbose / no-pub 白名单数据；不执行 tasks、Shell、命令替换或 XML 外部实体。入口及 define 文件必须为工程内普通文件。也可以手动填写启动参数，define 不写入项目文件。

最终先选“实际启动验证”或“仅准备”。实际验证前明确确认构建、签名及安装影响，使用所选 SDK、Java、设备与启动配置执行 `flutter run --machine`。只有收到匹配设备与 appId 的 `app.started`，并正常 detach 才报告实际启动通过；`app.start`、任务提交、doctor 或编译成功均不算。detach 后设备 App 保留运行，业务功能仍需本人验收。签名、描述文件、设备资格、许可、供应商模拟器切片及私有仓库权限不能由脚本绕过。

## <span id="jobs-toc-heading-9" data-jobs-toc="v2">五、里程碑、日志与退出码 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

GUI 通过 `JOBS_FLUTTER_SETUP_EVENTS` 指定私有 JSONL 文件；[ProjectEnvironment.zsh](./ProjectEnvironment.zsh) 写 `id/parent/title/state/message/version` 事件，Flutter、Java、Gradle、Pub、平台工具链、设备、启动配置及实际运行均有父子节点。成功节点的可见版本来自所选工具真实输出或已核对元数据，包括 Flutter / Dart、FVM、Java / jEnv、实际 Wrapper、静态 AGP、Xcode Build、实际执行的 CocoaPods / Bundler、浏览器及同套 Flutter 平台资源；未检测到的版本保持空值，不猜数字。后续父阶段完成事件保留已检测版本。没有该变量时仍可直接在终端运行。fzf、输入、许可证及原始日志由同一终端会话处理。

[SetupProjectWindow.swift](./SetupProjectWindow.swift) 将窗口标题、项目 / 工具版本与水平任务线分开展示，阶段名称和状态分行排布。任务线默认按内容取紧凑高度，随子节点适度增长，超出可用高度时滚动；保留真实分隔条，用户拖动后沿用手动高度并同步 PTY 行列数。仅进行中节点循环显示 0～5 个圆点，预留宽度保持布局稳定；节点转为其它状态或任务结束时清除圆点并停止动画。实际版本、分类子节点与等宽 ASCII `>>>>>` 连接符保留。

日志与配置快照保存在系统临时目录 `JobsFlutterEnvironment.*`，路径会在确认后显示。外部工具输出按原样流式送到终端 / GUI；启动门禁从独立流式旁路保存的 `app.start/app.started` 最小状态读取，不因大型构建日志超过整文件读取上限而丢失启动结果，完整原流不截断。原始日志保存在私有运行目录，目录权限 700、文件按 600 创建。`environment.log` 是独立脱敏审计分支，过滤 ANSI、URL 凭据与查询参数，不回写或破坏原日志。分享原始日志前需本人检查凭据与业务信息。Flutter 版本首启单次 1800 秒且自动重试，Wrapper 版本检查 60 秒，doctor / devices 各 120 秒；超时先终止本次子树，2 秒后强制结束仍未退出的本次子进程，不终止其它 Java / Gradle 会话。

`0` 表示所选流程已验证完成；`3` 表示保留环境准备但仍需本人处理或未做实际运行；`124` 为有界任务超时，`130` 为取消，其它失败尽量保留工具真实退出码。`--sdk-only` 的 `0` 只说明该子流程检查通过，不代表实际运行。

## <span id="jobs-toc-heading-10" data-jobs-toc="v2">六、验证范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

通过假 SDK、假网络、假 Wrapper、临时项目和 PTY 验证核心顺序、取消、SHA256、官方回退、兼容检查、Pub 失败停止、doctor 缺项、启动事件与 detach；Wrapper 缓存另有真实本机 Java 文件锁回归。解析器只读核对当前工程的 JSONC / XML 配置。没有通过本次源码测试安装真实 SDK、接受许可、修改业务工程配置、构建安装真实 App 或验证 Windows 桌面菜单。平台工具和真实设备最终以目标机器执行结果为准。

`ruby ../../Tests/ProjectDependencyTests.rb` 用假原生工具核对 Maven 解析任务、Pods install / Bundler、SPM 容器与锁文件、OHPM / Hvigor 顺序、npm / pnpm / Yarn 锁定安装、平台过滤与原生 build 参数；覆盖失败 / 取消停止和单项 Web 不准备无关 SDK。`--check` 只读与共用内核的执行顺序单独验证，不以假命令成功声称真实平台制品已经下载。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>

SDK 获取公共逻辑位于[同名包装函数库](./【MacOS】SDK获取重试.zsh/README.md)，业务脚本内嵌同一实现以支持仅复制单脚本的终端启动器；[隔离回归](../../Tests/SdkAcquisitionRetryTests.rb/README.md)验证持续重试与强制取消。

[工程依赖工具链](./【MacOS】工程依赖工具链.zsh/README.md)负责必需 Node SDK、锁定包管理器、鸿蒙已有工具定位与 Apple SPM 构建缓存桥接。SDK 分发摘要校验失败时保留本次私有坏片段并重取；安装器返回成功但缺少 Flutter 入口时继续获取。Apple 官方 CLT 下载由系统界面管理，脚本自动复检，不代签许可。

SDK自举前若精确Dart归档已有写入者，会显示PID与缓存路径并等待其释放；只读句柄不阻塞。Ctrl+C结束当前等待，不杀其它会话、不清理续传缓存。
