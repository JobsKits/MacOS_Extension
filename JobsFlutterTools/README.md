# [**Flutter**](https://flutter.dev/) 开发、体检、修复与维护

![Jobs出品，必属精品](https://picsum.photos/1500/400)

---

## 🔥 <span id="前言">前言</span>

`JobsFlutterTools` 是 Flutter 工程右键菜单的统一入口。只有同层 `pubspec.yaml` 声明 Flutter SDK 的工程文件夹才展示菜单；支持选中文件夹或工程内空白处。菜单由单个扩展创建，子菜单顺序固定，不再由多个独立扩展竞争排列。其他软件提供的菜单相对于本组的位置由操作系统决定。

## 一、<span id="menu-structure">固定菜单结构</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
🦋 Flutter开发相关辅助工具
├─ 🚀 一键配置 Flutter 项目
├─ ▶️ 从终端运行 Flutter 项目
├─ 📥 拉取Flutter项目工程相关依赖
│  ├─ 📥 拉取 Flutter Pub 依赖
│  ├─ 🤖 拉取 Android 原生依赖
│  ├─ 🥥 拉取 CocoaPods 依赖
│  ├─ 🧬 拉取 Swift Package 依赖
│  ├─ 🕊️ 拉取 OpenHarmony 依赖
│  └─ 🌐 拉取 Web 工程依赖
├─ 🧩 提取Flutter项目工程依赖
│  ├─ 🧩 提取 Flutter Pub 依赖
│  ├─ 🔐 提取Flutter项目工程私库依赖
│  ├─ 🧩 提取 Gradle 分发与依赖缓存
│  ├─ 🧩 提取 CocoaPods 依赖
│  ├─ 🧩 提取 Swift Package 依赖
│  ├─ 🧩 提取 OpenHarmony 依赖
│  ├─ 🧩 提取 原生构建缓存
│  ├─ 🧩 提取 Flutter 平台资源
│  └─ 🧩 提取 Web 依赖
├─ 📤 导入Flutter项目工程依赖
│  ├─ 📤 导入 Flutter Pub 依赖
│  ├─ 📥 导入Flutter项目工程私库依赖
│  ├─ 📤 导入 Gradle 分发与依赖缓存
│  ├─ 📤 导入 CocoaPods 依赖
│  ├─ 📤 导入 Swift Package 依赖
│  ├─ 📤 导入 OpenHarmony 依赖
│  ├─ 📤 导入 原生构建缓存
│  ├─ 📤 导入 Flutter 平台资源
│  └─ 📤 导入 Web 依赖
├─ 🔀 安装/切换Flutter运行环境
│  ├─ 🔀 安装/切换Flutter SDK
│  ├─ 🕊️ 安装/切换Flutter@OpenHarmony SDK
│  └─ ☕ 安装/切换Java SDK
├─ 🧱 Flutter 资源与构建依赖
│  ├─ 📚 下载Gradled分发与构建插件
│  ├─ 🗃️ 下载Flutter平台资源
│  └─ 🧱 准备原生库与构建依赖（组合操作）
├─ 📦 Flutter打包
│  ├─ 🍏 iOS
│  ├─ 🤖 Android
│  └─ 📦 打包鸿蒙（HAP + APP）
├─ ⚙️ Flutter自动化生产代码
├─ 🏥 Flutter项目体检
│  ├─ 🔎 查看当前Flutter项目工程的SDK版本
│  ├─ 🧑‍⚕️ 原生Flutter项目体检
│  └─ 💓 OpenHarmony Flutter 环境体检
├─ 🔧 Flutter项目修复
│  ├─ 🩹 修复 Android SDK / platforms 缺失
│  ├─ 🈶 修复 Flutter 项目中文路径
│  ├─ 🏷️ 修复 Flutter 插件 namespace
│  └─ 🔤 修复 Dart 相对 import 为 package 引用
└─ 🧹 Flutter清理维护工具
   ├─ 🗑️ 清理当前 Flutter 项目构建产物
   └─ ♻️ 依赖与缓存维护
```

上级[总管理器](../【MacOS】🧩管理Finder扩展.command)会把上述 **45 个可执行子功能** 分别列为复选框（2026-10-30，按 `FlutterToolsAction` 排除仅分组的 `package` 计数），管理面板按开发、打包、体检、修复、清理维护展开，支持组内及全局全选 / 全不选。各类依赖可分别安装 / 卸载；打包可分别选择 iOS、Android、鸿蒙；只安装需要的体检或修复也可保留对应父菜单，全部子项关闭的父菜单自动隐藏。安装 / 更新只增加所选动作，保留其它已启用项；卸载只减去所选动作。总管理器中完全不勾选 Flutter 则不改已装配置。

选择保存在当前用户应用支持目录 `JobsFinderExtensions/flutter-tools-features.conf`。Finder 展示、菜单点击及宿主执行前都会检查该配置；直接打开旧 URL 不能绕过关闭的动作。旧安装没有配置时保持全部动作，空配置关闭全部，损坏配置停止显示。本目录唯一管理入口省略范围时管理全部 45 项，指定 `--features` 时仅处理对应动作；最后一项卸载后才注销共享扩展并清理配置。两种模式均不执行 SDK 安装、打包、清理或项目修复。

后续 Flutter 动作应增加到本包的固定动作表和对应分组，不再新增独立的顶层扩展。修复组位于开发辅助组内，排在体检之后、清理维护之前；Finder 顶层只显示一个开发辅助入口。

## 二、<span id="dependency-layers">分层依赖拉取</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

“拉取Flutter项目工程相关依赖”内的六类包源各有单独右键项；“Flutter 资源与构建依赖”依次提供 Gradle 下载、Flutter 平台资源下载和原生构建组合操作。所有动作使用已有工程和锁定版本，不通过升级依赖填补缺项。单项入口先显示用途并回车确认，仅为所选类别准备必要的 SDK / Pub / Java / 平台工具；失败或取消停止后续步骤，已完成下载和正常缓存保留。

| 右键项 / 动作 | 当前能力与完成边界 |
| --- | --- |
| 📥 拉取 Flutter Pub 依赖 / `pub-get` | 使用项目 FVM SDK 运行 `flutter pub get`，未锚定或损坏时先进入 SDK 绑定流程；只完成 Pub 解析，不代表平台二进制已就绪。 |
| 📚 下载Gradled分发与构建插件 / `gradle-download` | 下载工程固定 Wrapper 分发并校验、验证真实 Wrapper 缓存复用，再通过 `Gradle help` 解析 AGP / Kotlin 等配置阶段插件；不编译 App，不包含全部 Maven 编译依赖。 |
| 🤖 拉取 Android 原生依赖 / `android-dependencies` | 准备 Android 工具链与固定 Wrapper，逐 Gradle 子项目严格解析可解析配置中的 Maven AAR / JAR；included builds、自定义任务和延迟下载仍以目标构建结果为准。 |
| 🥥 拉取 CocoaPods 依赖 / `pods-dependencies` | 对已有 iOS / macOS 目标执行 `pod install`，沿用 Podfile、锁文件和项目 Gemfile / Bundler；没有 Podfile 明确跳过，不执行 `pod update`。 |
| 🧬 拉取 Swift Package 依赖 / `spm-dependencies` | 按当前 Flutter 策略生成可用的 Apple 配置，再解析所选顶层 Xcode workspace / project 的 Swift 包与二进制制品；已有 `Package.resolved` 时要求使用其中版本，不切换全局 SPM 开关。 |
| 🕊️ 拉取 OpenHarmony 依赖 / `ohos-dependencies` | 使用已有 `ohos/` 工程运行 `ohpm install` 与工程 Hvigor wrapper 同步；需已配置的适配 SDK、DevEco / OHPM 工具，不替换成全局最新版构建器。 |
| 🧱 准备原生库与构建依赖（组合操作） / `native-dependencies` | 按选中目标解析对应平台依赖，再使用选择的入口、flavor、模式和 defines 实际执行 `flutter build`，触发 FFI Hooks、CMake、插件及延迟二进制下载；会编译并写正常构建产物，不安装或启动 App。 |
| 🗃️ 下载Flutter平台资源 / `flutter-precache` | 只预缓存所选目标的 Flutter 引擎等 SDK 平台资源；不能代替 Android SDK / NDK / CMake、Xcode、DevEco 或项目原生依赖。 |
| 🌐 拉取 Web 工程依赖 / `web-dependencies` | 仅处理项目根或 `web/` 中已有 `package.json` 的额外 JS 工程，要求唯一锁文件，分别使用 `npm ci`、pnpm frozen-lockfile 或 Yarn 对应的锁定安装；无 JS 工程不引入 npm 依赖。安装会运行生命周期脚本，`npm ci` 会重建 `node_modules`。 |

Apple 两项仅 macOS 提供；Windows 对应菜单不提供 CocoaPods / Swift Package 项。原生构建只承诺当前宿主支持的工程目标：Apple 目标须 macOS，Windows 桌面须 Windows，Linux 桌面须 Linux，本包不通过跨平台菜单冒充异宿主构建。私有仓库认证、许可、账号、签名及供应商支持范围继续由工程与本人管理。一次构建成功只覆盖本次 SDK、锁定版本、target、flavor、模式与架构，不保证其它配置或未来构建全部离线。

单项实现及参数见 [Tools 说明](./Scripts/Tools/README.md)；一键配置在 Pub 之后复用相同依赖内核，再进入实际运行验收。Pub 源码的 `extract` / `import-dependencies` 保持原格式和范围；平台依赖使用独立的配对快照动作，不把两类清单混用。拉取成功不等于快照已经提取，也不等于完整离线构建包。

## 三、<span id="dependency-faq">资源与组合操作常见问题</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

单独打开“下载Flutter平台资源”或“准备原生库与构建依赖（组合操作）”时，Terminal / CMD 会在首次回车确认之前逐行展示本项自述：一行一个要点，命令、资源示例和边界在对应要点下缩进。阅读后回车继续，非空输入或取消停止；不用先开始下载才能看清范围。

**“下载Flutter平台资源”具体下载什么？**

它运行所选 SDK 的 `flutter precache --<平台>`，把 Flutter 自己的引擎、编译和渲染配套资源放进 SDK 缓存。例如 Android 的引擎制品与 `gen_snapshot` AOT 工具，iOS 的 `Flutter.xcframework`，以及 Web 编译 SDK 和该版本配套的 CanvasKit / Skwasm 等 JS / Wasm 资源；具体文件、架构和 debug / profile / release 组合取决于 SDK 版本及目标。[平台缓存源码](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/flutter_cache.dart)、[引擎制品定义](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/artifacts.dart)和 [Web 渲染说明](https://docs.flutter.dev/platform-integration/web)给出了这些资源的职责。

Android 的 `--android` 在当前上游实现中还覆盖 Flutter 自身的 `android_maven` 制品，因此不能理解为“完全不碰 Maven”；它不会替工程解析全部 Maven / 第三方包，也不能代替工程 `pub get`、`pod install` 或完整 Android SDK / NDK / CMake、Xcode、DevEco 安装。已有健康缓存通常直接复用。以当前 SDK 的 `flutter precache --help` 和[官方命令实现](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/commands/precache.dart)为准。

**“准备原生库与构建依赖（组合操作）”为什么与其它入口有重叠？**

它是当前所选目标的组合流程：先复用或准备 SDK，再正常 `pub get`；Android 准备必要 Java / Android 工具、固定 Gradle 和构建插件，Apple 目标准备 Xcode / CocoaPods；随后调用同一平台依赖内核，分别处理 Android Maven、Apple 的 Pods + SPM、OHPM / Hvigor 或已有 Web JS 工程，最后按同一入口、flavor、模式与 defines 实际执行 `flutter build`。这会触发该目标需要的 FFI build hooks、CMake 或插件延迟下载；不会安装或启动 App，也不会为未选择的平台下载全家桶。独立资源入口负责显式 `precache`，单项 Mac 组合入口没有另加这一资源阶段，实际构建仍可能检查并补齐所需 Flutter 制品。

所以组合操作与单类拉取共享前置和缓存，已有依赖通常复用；需要只处理一个层级时用对应单项。构建钩子是否下载或编译由具体包决定，见 [Dart hooks](https://dart.dev/tools/hooks)。单次成功仅覆盖当前目标、配置和架构；一键配置还会另行确认设备安装 / 启动验收，组合操作本身不做这一步。脚本执行顺序见 [Tools 说明](./Scripts/Tools/README.md#native-combination-faq)。

## 四、<span id="dependency-archives">平台依赖与缓存快照</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

“提取Flutter项目工程依赖”和“导入Flutter项目工程依赖”分别列出本地导出和本地恢复叶子；Pub 源码保留原格式，以下平台类别各有对应配对动作。macOS 共十四个新快照动作；Windows 提供 Gradle、OpenHarmony、原生构建、Flutter 平台资源、Web 的十个动作，不提供 Apple 两类。各项可单独安装或卸载，不增加外层 Flutter 菜单。

| 类别 / 配对动作 | 快照内容与恢复位置 |
| --- | --- |
| `export-gradle-dependencies` / `import-gradle-dependencies` | 在同一菜单内选择 Maven `modules-2` 缓存或工程固定 Wrapper 的分发目录，分别提取 / 导入，兼容键区分组件。`modules-2` 是共享缓存，可能包含其它工程的包；不收集用户认证、全局 Gradle 配置或 daemon 状态。 |
| `export-pods-dependencies` / `import-pods-dependencies` | 已选 iOS / macOS 目标的 Pods 内容，沿用对应 Pod 锁文件与 CocoaPods 版本；不包含完整 Xcode、系统 SDK 或全局 Gem 环境。 |
| `export-spm-dependencies` / `import-spm-dependencies` | SPM 包源码与二进制制品缓存。拉取统一使用项目 `.jobs/dependencies/spm`；旧 Xcode 默认 SourcePackages 可明确选择为提取来源，导入固定还原到项目本地缓存，再由拉取 / 构建入口消费。 |
| `export-ohos-dependencies` / `import-ohos-dependencies` | 分别选择 OHPM `oh_modules` 或 Hvigor 缓存组件。源 / 目标位置按本机工具动态解析，必要时明确选实际缓存根，不扫描整个用户目录；不包含完整 DevEco / OpenHarmony SDK。 |
| `export-native-dependencies` / `import-native-dependencies` | 当前宿主、当前目标的 `build` 构建缓存及产物，可能含业务二进制；它不是可跨系统重建的源码包，仍依赖兼容 SDK / 工具链和工程配置。 |
| `export-precache-dependencies` / `import-precache-dependencies` | 当前 Flutter SDK 的 `bin/cache/artifacts` 平台制品；共享目录可能含已下载的其它平台内容，不包含 Flutter SDK 源码或 Dart runtime。 |
| `export-web-dependencies` / `import-web-dependencies` | 所定位 JS 工程的 `node_modules`；依赖对应锁文件，可能含本机原生扩展，须匹配宿主系统、架构与 Node 环境，不当作任意平台通用包。 |

提取前需要当前项目已具备可读取的依赖及健康 Flutter / Dart；此入口不替代拉取，不为提取缓存安装另一套 SDK。先阅读自述并回车，选择当前工程目标及适用组件，再输入或拖入输出父目录；这里空输入取消，不沿用 Pub 提取的默认桌面语义。导入选择完整快照目录，先核对宿主、工具版本、组件、工程配置 / 锁文件指纹以及全部文件 hash 和路径；兼容性不符、快照残缺、路径异常或同名不同内容均停止，不覆盖冲突。完整预检通过后精确输入 `YES`，写入前再次检查。

导入只恢复校验通过的文件，不自动执行快照中的脚本、包管理器或构建任务，也不自动安装 SDK、联网修包或修改认证。导入后应运行对应依赖 / 原生构建入口验证可用性。相同文件可复用；取消保留已完成提取、正常缓存及此前工程状态。清单和快照中的本机业务产物、共享包与原始日志在分发前需自行核对。版本、锁指纹和宿主匹配是恢复前提，不是任意跨宿主或任意 flavor / 架构离线构建的保证。

Pods 的 `Manifest.lock` 等功能锁会随内容保留。插件头文件链接到 Pub 源码时，仅允许物化当前 `.dart_tool/package_config.json` 已解析、且普通 `pubspec.yaml` 中包名核验一致的依赖根内文件；工程自身条目不授权读取其它项目文件。未声明、失效、循环或继续越界的链接拒绝提取，不把开发机绝对链接写入快照。

## 五、<span id="dependency-import">导入已提取的 Pub 第三方源码</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在目标 Flutter 工程右键选择“导入Flutter项目工程依赖 → 📤 导入 Flutter Pub 依赖”，在 Terminal 阅读自述并回车，然后输入或拖入“🧩 提取 Flutter Pub 依赖”生成的完整快照目录。目录输入处空回车会继续询问，不退出；`Ctrl+C` 或输入结束可取消。需要同层 `manifest.json`、`packages/`、原始 `pubspec.yaml` 和 `pubspec.lock`，不能只选 `packages/` 或任意源码文件夹。路径支持空格、中文、Terminal 拖入转义和粘贴时外侧的不换行空格；真实存在的原始路径优先保留，不误裁实际文件名中的边界空格，也不执行路径中的命令字符。

入口先只读核对格式与完成状态、包目录、包名、版本、文件数量、依赖关系及目标项目声明；损坏、不完整、链接或路径越界立即停止。校验通过后显示来源、目标、依赖和配置计划，精确输入 `YES` 才写入，其它输入或 EOF 取消。导入使用项目 FVM 的健康原生 Dart，不回退全局 SDK，不下载工具或执行第三方脚本。

快照含提取时的 `warnings` 时，计划显示告警数量及原 `manifest.json` 路径；已跳过的源内容不会由导入补齐。导入目录中的 `source-manifest.json` 原字节保留源清单，便于核对。

依赖原样复制到项目 `vendor/flutter_dependencies/<本次目录>/packages/`，再增量合并 `pubspec_overrides.yaml` 的本地 `path` 覆盖。目标工程应已声明需要恢复的第三方依赖，且直接依赖声明须与快照来源一致；不代写 `pubspec.yaml` 新增依赖。目标 `pubspec.yaml` 中已有覆盖仅在整个原始覆盖区与快照证据完全一致时允许恢复，包含嵌套 Git 的 URL / ref / path；原文件逐字保留，由新覆盖文件指向本地源码。不同声明或目标 `pubspec_overrides.yaml` 已有同名覆盖仍拒绝，避免取代项目的新决定；其它覆盖及配置保留。存在原覆盖文件时，本次目录保留 `pubspec_overrides.yaml.before-import` 原字节备份。当前不接受 Pub workspace（根项目与成员均不支持），避免把覆盖写到无效解析位置。

导入后按终端提示正常执行项目依赖解析，刷新 `.dart_tool/package_config.json`。导入本身不自动执行 `pub get`，不写 Pub 全局缓存，不保证 CocoaPods、Gradle、SDK 或平台构建缓存已具备。备份和具体结果位置会输出到终端；恢复前先核对配置后续是否有其它修改，再恢复原文件，原本不存在时撤去本次覆盖文件。

源码独立运行方式（需保留同目录的两个 Dart 引擎）：

```shell
/bin/zsh ./Scripts/Tools/ImportFlutterDependencies.zsh \
  '/实际 Flutter 项目路径'
```

仅校验可使用项目 Dart 运行 `ImportFlutterDependencies.dart --project <项目> --source <快照> --validate-only`，不创建依赖目录、配置或备份。菜单资源随 App 打包；取得新源码后从管理入口安装 / 更新并勾选本项，重新发起 Finder 请求才会载入新实现。Windows 对应入口见[平行功能说明](../../WindowsOS@Extension/JobsFlutterTools/README.md)。

## 六、<span id="private-dependency-migration">私库便捷迁移</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

源工程右键 → **🧩 提取Flutter项目工程依赖 → 🔐 提取Flutter项目工程私库依赖**（`export-private-dependencies`）。选择输出父目录，生成 `FlutterPrivateDependencies-<项目名>-<时间>-<随机值>/`；把整个目录随工程带到另一台机器。

目标工程右键 → **📤 导入Flutter项目工程依赖 → 📥 导入Flutter项目工程私库依赖**（`import-private-dependencies`）。输入或拖入完整快照目录，预检成功后输入 `YES`。源码写到当前工程的 `vendor/flutter_dependencies/<本次目录>/packages/`，并为全部私库（包括间接依赖）生成相对 `path` overrides。最后单独运行 `flutter pub get` 获取公共包；私库改用工程内的源码，不再访问旧机器路径或私库 Git 服务器。

- 提取范围：锁文件中所有 Git、path、自建 hosted Pub 源的已解析包，包含开发和间接依赖、Git 仓库子目录、插件包内平台源码、资源及许可证。公共 `pub.dev`、`pub.dartlang.org`、`pub.flutter-io.cn`、`pub-web.flutter-io.cn` 的包和 SDK 不复制，也不要求公共缓存仍存在。
- 无法仅凭 Git URL 判断仓库权限，所以 Git 依赖全部收录（包括公开 Git 仓库）；其它自建 Pub 镜像也按私库收录，以免漏包。
- macOS / Windows 使用同一 Dart 引擎与快照格式。提取端须已有 `pubspec.lock`、`.dart_tool/package_config.json` 和完整私库源码；导入端只需工程与健康的项目 FVM Dart，不需要旧私库缓存或 Git 凭据。
- 私库快照带文件级 SHA-256，缺包、内容损坏、包名/版本不符、Git url/ref/path 声明冲突会停止。导入前和发布覆盖文件前都会复检；普通 Pub 快照与私库快照不能混用入口。
- 保留 `pubspec.yaml` 和原锁文件；已有 `pubspec_overrides.yaml` 按字节备份，无关覆盖与注释保留。同名覆盖与来源一致时转换为新本地路径，不一致则拒绝覆盖。完整快照及导入后的 vendor 源码应一起备份；还原时使用本次目录中的配置备份。
- 当前支持独立 Flutter 工程，不支持 Pub workspace。包外/失效源码链接会导致私库提取失败，避免静默漏源码。跳过 `.git`、构建产物、生成链接目录；不迁移 Git 历史和机器凭据，也不承诺迁移独立 CocoaPods / Maven / Gradle 私服中的原生二进制。这些仍使用各自的平台依赖入口。

`flutter@aito_ie` 蓝本验证：5 个 Git 包（`eeasy_camera_plugin`、`flutter_im_plugin`、`flutter_nb_net`、`seres_flutter_plugin`、`seres_flutter_unionpay_plugin`）和 1 个本地包（`tigertally_flutter_plugin`）可提取，公共包不进入快照。

## 七、<span id="project-setup">一键配置与 Gradle 分发 / 构建插件下载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

“🚀 一键配置 Flutter 项目”打开独立原生窗口。已构建扩展随包携带该窗口可执行文件，打开界面本身无需新电脑预装CLT或Swift编译器；业务工具链仍按所选平台逐项准备。窗口标题显示工具版本与构建号，唯一版本源为随包 `SetupVersion.json`。上方按 Flutter SDK → Java SDK → 平台工具链 → Gradle分发 → 依赖与插件 → 设备与运行条件显示水平任务线；父节点下直接列出 Android SDK、许可证、iOS / Xcode 等分类状态。节点区分等待、进行中、成功、失败、需用户处理，实际检测到的 SDK、Dart、FVM、jEnv、JDK、Gradle 与各平台组件版本在对应节点标题下直接显示，最多两行；完整版本说明、路径与原因可悬停查看。尚未检测到版本时不填造数字；阶段之间统一使用等宽 ASCII `>>>>>`，默认窗口完整显示六列；超宽或子节点较多时可滚动。

中间分隔条带明显拖柄，可上下拖动调整任务线与黑框终端的高度；两区都保留最小可用高度，任务线和终端日志也可各自滚动。拖动会实时更新终端行列数，fzf 不会沿用旧尺寸。

下方是真正的 PTY 终端，随包 [xterm.js](https://xtermjs.org/) 处理 ANSI、fzf、光标和窗口大小变化，不通过文本日志框代替交互。先在终端阅读自述并回车，再用 `Enter` 选择、`←` 返回上一层、`Esc` 取消选择；`Ctrl+C` 或“取消任务”中断当前业务。关闭运行中的窗口需选择继续或取消；Ctrl+C 未响应时只对本次 PTY 进程组有界发送 TERM / KILL，已有安装与已完成阶段保留，返回上一层不等于撤销安装。顶部状态和下方原始输出同时可见；某项需人工处理时仍可查看完整命令输出。

| 阶段 | 当前行为与边界 |
| --- | --- |
| Flutter SDK | fzf 首项为 FVM 项目 SDK，可复用或进入现有安装 / 切换流程；也可选系统 Flutter，从 PATH、指定本机 SDK 或经确认的 Homebrew 安装取得。验证同一套 Flutter / Dart 实际可运行。 |
| Java SDK | fzf 首项为 jEnv；可选系统 Java，复用实际 JDK、指定目录或安装指定主版本。验证 `java` 与 `javac` 一致，再与项目固定 Gradle 做运行兼容检查。 |
| 平台与运行条件 | 先选当前宿主支持的已有 Android / iOS / macOS / Web / OpenHarmony 目标，按实际工具逐项检查 / 引导；Android 许可由本人阅读确认。Apple 目标检查 Xcode 首次配置、CocoaPods / Bundler；OpenHarmony 要求适配 SDK 与已有 DevEco 工具。下载同套 Flutter 的目标平台资源，后续匹配设备与启动配置。收尾 `flutter doctor -v` 与 `devices --machine` 有界等待，完整保留 SDK、许可、签名、flavor 与私有仓库缺项。实际运行仅在收到 Flutter `app.started` 且正常 detach 后标记成功。 |
| Gradle | 读取现有 Android Wrapper 的精确正式版本与 `bin/all` 类型，不根据 Java 自动升级 Gradle 或 AGP。可信 SHA-256 校验后预置真实 Wrapper ZIP 缓存，用当前项目 Wrapper `--version` 核验缓存复用，再解析构建插件。 |
| Pub 依赖 | 用本次选择的 Flutter 正常执行 `pub get`，使用项目依赖及锁文件，不执行 `pub upgrade`；私有 Git / Pub 源沿用当前认证。 |
| 目标原生与构建依赖 | Pub 后按目标执行 Maven，或 Pods + SPM，或 OHPM / Hvigor，或锁定的 Web JS 安装；再以同一启动配置实际 `flutter build` 准备 FFI / CMake / 延迟依赖。构建阶段不安装或启动 App；后面的运行验证另行确认。失败即停止，不把只显示依赖树或下载分发包当完成。 |

完整流程可从现有 VS Code `launch.json` 或 `.run` 配置读取白名单参数，也可手动选择入口、flavor、模式和 Dart defines；不执行配置中的 Shell / preLaunchTask。原生依赖构建与后续实际运行使用同一配置。设备列表为空可重新加载或进入已有模拟器创建流程；模拟器创建和实际构建 / 签名 / 设备安装均按窗口终端中显示的用途确认。选择“仅准备”会明确保留实际运行未验证状态，不把准备结果等同于 App 已成功启动。`--sdk-only` 保留 SDK / Gradle / Pub 子流程，不执行目标原生依赖构建或实际运行。

Android 环节复用随包官方 SDK 内核，优先项目 `sdk.dir`；从工程及所选 Flutter 的真实默认配置解析 `compileSdk`、build-tools、NDK / CMake，无法静态判定时才 fzf 选择。只补缺少的健康组件，SDK Manager 若要求更高的工具 JDK 可临时准备，项目 Gradle 仍使用原先选定的兼容 JDK。许可证保留真实终端供本人阅读确认，`local.properties` 写前留快照并复检并发变化，不把安装 SDK 误当成已验证业务运行。

本流程保存项目 `.jobs/flutter-environment.json` 中的本机 Flutter / Java 来源和路径，并更新 `android/local.properties` 的 `flutter.sdk`；原文件先留快照，写前核对是否被并发修改。系统模式不删除已有 FVM / `.java-version` 声明，不修改全局 PATH、`fvm global`、`jenv global`、Flutter 全局 JDK 配置或系统代理。本流程和后续 Gradle 下载入口使用本次选择；其它原有 FVM 专用菜单仍按其自身规则运行。设备、签名和业务运行未验证时，不把下载成功或 `Gradle help` 通过当作 App 已可运行。

“📚 下载Gradled分发与构建插件”可独立运行，优先读取上述环境记录，其次项目 `.java-version`，最后当前系统 JDK；失效声明或 Gradle daemon JVM criteria 冲突会停止并说明。这里同时准备 Gradle 分发及配置阶段的 AGP / Kotlin 等构建插件，实际执行 Android 工程 `Gradle help`，会运行该项目构建配置脚本并写正常缓存；不会编译 App，也不承诺所有 App 运行依赖已下载。

网络默认项目 / 官方来源，失败尝试 Gradle 官方备用线路；fzf 可明确选择腾讯 Gradle 分发镜像及阿里云 Maven 临时源，退出后即撤回，不写工程或用户全局仓库。分发包每来源最多两次，连接 10 秒、低速 30 秒停止，单次默认 300 秒；插件解析默认 900 秒，只在明确网络错误时重试一次。可用 `JOBS_GRADLE_DOWNLOAD_TIMEOUT`（10–1800 秒）、`JOBS_GRADLE_TASK_TIMEOUT`（30–7200 秒）设置；Wrapper 版本验证上限 60 秒。摘要优先项目 `distributionSha256Sum`，缺省仅从 Gradle 官方取得，无法取得可信摘要时不执行下载包。分发缓存中的同源片段可续传，已有异常缓存保留并报错。

真实 Wrapper 缓存遵循 `GRADLE_USER_HOME` 与 `distributionBase/distributionPath/zipStoreBase/zipStorePath`，支持标准 `GRADLE_USER_HOME` 和 `PROJECT`（Android 工程）基准及安全相对目录。Java FileLock 与 Wrapper 共用同一个 `.lck`，并发构建、在途 `.part`、链接、硬链接或已有摘要不符 ZIP 不覆盖；不伪造 `.ok`。缺少 `gradle-wrapper.jar`、特殊路径语法或 JVM 参数另改缓存根时明确停止。缓存路径算法及内容校验分别使用 MD5 base36 与 SHA-256，二者用途不同，详见 [Gradle Wrapper 官方说明](https://docs.gradle.org/current/userguide/gradle_wrapper.html)。

GUI 会话目录为系统临时目录 `JobsFlutterSetup-*`：`terminal.raw.log` 原样保存终端输出（含 ANSI），权限仅当前用户读写；`events.jsonl` 保存状态事件。点击“打开日志目录”查看，分享前核对其中可能的敏感内容。业务日志、下载片段和配置快照另在终端提示的 `JobsFlutterEnvironment.*` 与用户缓存中；临时目录可能被系统清理，需要长期保留时自行复制。恢复配置前先对照快照与当前文件，确认没有后续编辑，再恢复本次涉及的文件；不整份回滚项目。

源码手动运行仍可用终端模式；`--check` 不安装、不联网或写配置，下载入口会检查本机 JDK，配置入口只盘点项目与 Wrapper，不代表完整环境健康：

```shell
/bin/zsh ./Scripts/Tools/SetupFlutterProject.zsh \
  --project '/Flutter 项目绝对路径' \
  --check

/bin/zsh ./Scripts/Tools/DownloadProjectGradle.zsh \
  --project '/Flutter 项目绝对路径' \
  --check
```

下载入口另有 `--java-home <JDK>` 显式指定本次 JDK；`--distribution-only` 只准备并校验分发与 Wrapper，跳过构建插件解析。完整窗口资源、事件协议和本机验证入口见 [Scripts 说明](./Scripts/README.md)；Windows 功能与原生验收边界见[平行包](../../WindowsOS@Extension/JobsFlutterTools/README.md)。

## 八、<span id="sdk-version-management">项目 SDK 与 Java 版本管理</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

“安装/切换Flutter@OpenHarmony SDK”使用 [CPF-Flutter 适配仓库](https://gitcode.com/CPF-Flutter/flutter_flutter) 的实际发布标签，先选择版本，再确认下载及项目绑定；不使用原生 Flutter 发布清单。SDK 按远端标签对应的 commit 放入独立 FVM 缓存，并通过当前项目 `.fvmrc` / `.fvm/flutter_sdk` 使用。切换失败恢复原项目绑定，不执行 `pub get`、不设置 `fvm global`。同名入口同时提供在 [Windows 包](../../WindowsOS@Extension/JobsFlutterTools/README.md) 中。

原生 SDK 和 OpenHarmony SDK 是两个明确的选择入口；一个项目同一时刻使用一套 FVM 绑定。切换入口会更改当前项目所选 SDK，不能把两个入口理解为同时绑定两套。需要并行开发时可使用不同工作目录。OpenHarmony 原生构建还需要配套 DevEco / OHOS SDK 和插件适配；此入口只安装及切换 Flutter SDK。iOS / Android 建议使用上游 Flutter，鸿蒙使用对应适配版本，见[适配方升级说明](<https://gitcode.com/CPF-Flutter/flutter_samples/blob/master/ohos/docs/10_appendix/Flutter-OH版本升级指导.md>)。

“安装/切换Java SDK”通过 [jEnv](https://github.com/jenv/jenv) 管理当前项目 `.java-version`，支持复用已安装 JDK，或安装指定主版本后绑定。jEnv 负责版本切换；缺失 JDK 使用现有 Homebrew 安装，不主动升级健康组件。首次确认前说明来源与影响，切换前备份原声明，失败保留或恢复原状态；不会修改 `jenv global`、Shell 启动文件或全局 Flutter JDK 配置。原有 `17` 声明可直接识别。

带 `.java-version` 的右键运行、Android / OpenHarmony打包、体检和 Android SDK 修复会为本次进程解析 Java，设置 `JAVA_HOME` / `PATH`，并用 `GRADLE_OPTS` 固定 Gradle daemon 的 JDK；后台运行会保留这些变量。Flutter 自身仍可能优先采用 Android Studio JDK，`flutter doctor` 显示的 Java 不等于实际 Gradle daemon 的 Java。项目存在 `android/gradle/gradle-daemon-jvm.properties` 时，该 Gradle 配置优先，工具会停止并提示先处理冲突，避免静默使用另一套 JDK。IDE 独立启动及普通终端需自行启用 jEnv 或配置项目 Gradle JDK。查询 SDK、依赖解析、iOS 直达打包和静态操作不强制 Java 环境。JDK 的真实安装路径支持空格和中文，但拒绝各代 Gradle wrapper 解释不一致的美元符、反引号、双引号、反斜杠和控制字符；Flutter 项目路径不受此 JDK 路径限制。

两个新安装入口都无需先有 FVM 绑定。在本包目录只读检查（替换项目路径），不联网、不安装、不写日志或项目配置：

```shell
/bin/zsh ./Scripts/Tools/ManageHarmonyFlutterVersion.zsh \
  --project "/绝对路径/Flutter项目" \
  --check

/bin/zsh ./Scripts/Tools/ManageProjectJava.zsh \
  --project "/绝对路径/Flutter项目" \
  --check
```

## 九、<span id="packaging">打包平台与产物</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

从 `Flutter开发相关辅助工具 → Flutter打包 → iOS / Android / 📦 打包鸿蒙（HAP + APP）` 选择平台。文件夹右键和项目内空白处右键的行为一致。平台通过固定动作 `package-ios`、`package-android`、`package-ohos` 传给分发脚本，再转成 `PackageFlutter.zsh --platform ios|android|ohos`，终端不再询问平台。

iOS 直接构建 IPA，无需 fzf；Android 仍用 fzf 选择 APK / AAB / 两者。鸿蒙菜单一次依次执行 `flutter pub get`、`flutter build hap --release` 和 `flutter build app --release`，不再选择包型，固定 release 且忽略终端遗留的 flavor。两次构建均成功、分别发现非空 HAP 与 APP，且最终复核已记录的两类包仍存在非空才报告整体成功；第二次失败时保留已生成的 HAP 并返回失败。直接调用脚本可用 `--target apk|appbundle|all`、`--ohos-target hap|app|all` 预设产物，全部预设时无需 fzf。未指定 `--platform` 的旧 CLI 调用保留平台选择。非法、缺值或重复的平台参数会在构建前拒绝。

合法 Flutter 根目录在启用 `package-ohos` 后始终显示鸿蒙打包入口。点击时检查普通 `lib/`、`ohos/` 目录及 `ohos/build-profile.json5`、`ohos/oh-package.json5` 两份普通非链接文件；缺少时明确提示先完成鸿蒙适配，不启动构建。宿主与分发器执行前再次核对，纯 ArkTS 项目不进入 Flutter 菜单。沿用 `package-ohos` 及总面板 `flutter-package-ohos` 标识，不产生重复功能或改动其它安装选择。使用项目 `.fvm/flutter_sdk` 的鸿蒙适配 SDK，在依赖解析前同时验证 `build hap --help` 与 `build app --help`；普通官方 SDK、缺失 DevEco / HarmonyOS SDK、Node / npm / OHPM / Hvigor / Java 均明确停止。构建使用工程已有签名和默认 product / target，不修改签名；`-unsigned` 包会警告，产物不代表真机安装或上架验收。

终端保留用途说明、回车确认和日志；构建使用项目 FVM SDK，鸿蒙要求该 SDK 已支持对应构建命令，以及已有 `ohos/` 工程和 DevEco 工具链。菜单选择本身不安装 SDK，不改签名。`fzf` 仍仅用于尚未指定的选择；不自动安装。

## 十、<span id="project-doctor">FVM 与体检</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

“📥 拉取 Flutter Pub 依赖”先在当前终端显示用途并等待回车确认，再检查项目自身的 `.fvmrc`（或旧 `.fvm/fvm_config.json`）、`.fvm/flutter_sdk`，以及实际 Flutter / Dart 是否可运行。已有健康绑定时直接执行 `flutter pub get`；未绑定、SDK 文件残缺、链接失效或运行检查失败时，在同一终端进入“安装/切换Flutter SDK”的现有版本选择与确认流程。安装 / 切换完成后重新检查项目绑定和实际运行情况，通过后自动继续本次依赖拉取，不需要再次点击右键菜单。

SDK 选择取消、准备失败或准备后复检失败都会停止本次依赖拉取；不会回退全局 Flutter。SDK 准备沿用版本管理器的配置快照、依赖安装确认和项目级修改范围，独立的“安装/切换Flutter SDK”入口仍只准备 SDK。这里检查的是依赖解析所需的 SDK 运行条件，不要求先具备所有平台的打包环境。

依赖拉取日志为系统临时目录中的 `InspectFlutterProject.log`；按需进入的 SDK 管理流程另保留 `JobsFlutterVersionMgr.*/ManageFlutterVersion.log` 与原配置快照，实际位置均在终端显示。`InspectFlutterProject.zsh --check <项目> pub-get` 只检查文件并显示计划，不调用 SDK、不写日志，也不启动安装 / 切换；SDK 尚未就绪时返回失败并说明实际运行时的准备流程。

“清理当前 Flutter 项目构建产物”和“修复 Dart 相对 import 为 package 引用”是无需 SDK 的静态操作；原生 / OpenHarmony SDK 安装切换与 Java 管理使用各自引导流程。Pub 拉取及各类[分层依赖入口](#dependency-layers)按需准备其前置条件；新单项入口可复用一键配置已保存且仍健康的本机 SDK。其余 SDK 执行入口仍要求项目 `.fvmrc`（或旧 `.fvm/fvm_config.json`）及 `.fvm/flutter_sdk`，缺失时提示先安装/切换项目版本。普通入口不执行 `fvm global`、不把 Flutter 写入全局 PATH 或 Shell 配置；一键配置可显式选择本次使用系统 Flutter，详见[配置说明](#project-setup)。其余体检、修复及依赖缓存维护引擎使用项目 SDK 内的 Dart 3+，无需额外安装 Dart 包。

原生体检检查 FVM、Flutter 版本声明与实际版本、同源 Dart 及 `flutter doctor -v`。基础 doctor 的警告、错误或无法判定的输出都不能算健康。

Harmony 体检先检查同一套 **FVM 管理的 Harmony Flutter SDK 的基础环境**，再检查 `hap` 构建能力、DevEco/CLT、Node、OHPM、Hvigor、HDC、Java、SDK 编译组件、项目 `ohos/` 结构及已解析原生插件的 `ohos` 声明。只有全部通过才报告健康；不会仅凭模拟器已启动就报告项目可运行。静态插件声明检查不能代替实际构建，联邦插件的替代实现需按失败列表核对。

Harmony Flutter 是适配分支，普通 Flutter 安装并不会自动带来 Harmony 构建能力。可按 [FVM 官方自定义 fork 用法](https://github.com/leoafarias/fvm/blob/main/docs/pages/documentation/guides/quick-reference.md) 先注册所需的适配仓库，再在项目中执行 `fvm use <fork>/<版本或分支> --skip-pub-get`；菜单始终读取该项目绑定。版本选择器的官方发布清单用于原生 Flutter，不把原生版本冒充 Harmony 适配版。多套 DevEco/CLT 并存时通过本次终端的 `TOOL_HOME` 或 `DEVECO_STUDIO_HOME` 指定，体检不改全局环境。

## 十一、<span id="repair-and-backup">修复范围与备份</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- **相对 import 转 package**：从“Flutter项目修复 → 修复 Dart 相对 import 为 package 引用”进入。按当前 Dart 文件位置解析相对引用，仅把实际指向本项目 `lib/` 内文件的 `import` URI 转成 `package:<pubspec包名>/...`，例如 `lib/pages/detail.dart` 中的 `../models/user.dart` 转成 `package:demo/models/user.dart`。先预览，再明确确认写入；`package:`、`dart:`、注释、普通字符串、`export` / `part`、生成文件及第三方目录保持原样。此操作不要求 Flutter / FVM，不联网、不修改依赖或 SDK。完整用法见[原脚本说明](<../../../JobsCommand@Flutter/MacOS/小工具/【MacOS】⚙️import =＞package💣.command/README.md>)。
- **Android SDK / platforms**：优先使用项目已有 `sdk.dir`，再参考本机 SDK 环境。按工程 `compileSdk`（或 FVM SDK 的默认值）补齐 platform；优先遵循显式 `buildToolsVersion`，否则选稳定 build-tools。补齐所需 Java/官方命令行工具，校验组件，再备份并更新当前项目 `android/local.properties`。不会安装模拟器镜像，不写 `flutter config`，SDK 许可证仍由本人阅读接受。
- **中文路径**：修复 Dart `import` / `export` / `part` URI 中合法的中文 UTF-8 百分号编码。保留 URI 分隔符、注释和普通字符串；跳过构建及缓存目录。此功能不重命名项目文件夹、不升级依赖。
- **namespace**：从当前项目 `.dart_tool/package_config.json` 定位已解析 Flutter 插件，仅在其 Android Gradle 文件缺少 namespace、且 manifest 有明确 package 时修复。支持 Groovy/Kotlin，已有 namespace 不改，无法判断的插件跳过。不会遍历整个 Pub 缓存。插件可能被多个项目共用，确认前会列出具体文件。

相对 import 修复先回车查看计划，再精确输入 `YES` 写入；正常模式必须在可交互终端执行。日志与原始备份位于终端打印的系统临时目录 `jobs-flutter-imports.XXXXXX/`，分别为 `imports.log` 和 `backup/项目内相对路径`。`RepairPackageImports.zsh --project <项目> --check`（或 `--dry-run`）只读，不创建日志、备份或改写项目；转义、插值、百分号编码等无法安全解释的 URI 保留原样。临时目录可能被系统清理，需要长期保留时复制备份。

中文路径与 namespace 两项先预览，输入 `REPAIR` 才写入；备份在项目 `.jobs_flutter_backups/<时间>/`，`manifest.json` 保存每个原路径与唯一备份文件的映射，同名 Gradle/Dart 文件不会相互覆盖。Android 配置备份在 `android/.jobs-sdk-backup*`。取消或预览不改文件。恢复时应先核对目标文件此后是否有其他修改，再从映射取回原文件。

这些能力基于用户指定的 `JobsCommand@Flutter/小工具/` 中 Android SDK 修复、中文路径修复、namespace 修复和清理维护工具的用途接入；重用了本仓库的 SDK 引导，并收紧了全局安装、缓存扫描及备份范围。源工具是 `.command` 目录，namespace 工具目录名还包含一个字面双引号；安装后不依赖这些外部绝对路径。

## 十二、<span id="maintenance">清理维护</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

`Flutter开发相关辅助工具 → Flutter清理维护工具` 位于本组末尾，分为两个操作：

| 操作 | 执行内容 | SDK 与确认 |
| --- | --- | --- |
| 清理当前 Flutter 项目构建产物 | 直接删除当前 Flutter 项目的已识别产物，不运行工程脚本或构建命令。 | 无需 Flutter / FVM；先列出实际路径，输入 `CLEAN` 才清理，回车取消。 |
| 依赖与缓存维护 | 保留原维护编号菜单：依赖刷新、`clean + pub get`、主动升级、Pub 缓存修复及所选缓存清理。 | 使用项目 FVM；编号回车取消，命令二次确认，缓存删除要求 `CLEAN`。旧 `maintenance` URL 动作保持兼容。 |

项目产物清理沿用原 `JobsTerminalOpener` 白名单：根目录 `build/`、`.dart_tool/`，以及已识别 `android/`、`ios/`、`ohos/` 的构建和中间产物、桌面 Flutter ephemeral；Xcode 默认 DerivedData 只删除 `info.plist` 的 `WorkspacePath` 精确归属当前 `ios/` 工程的 `Build/`。保留源码、锁文件、Pods、`oh_modules`、`node_modules`、签名、FVM SDK、共享缓存和无关项目产物，不推断自定义输出。整份计划先校验，目标或其父路径是符号链接时停止。入口仅接受 Flutter 根目录，不向父目录寻找工程。

依赖与缓存维护只执行选中的操作，失败立即停止。共享 Pub、Gradle 或当前 FVM SDK 缓存清理会显示路径并要求 `CLEAN`；不会删除 Pub 可执行文件、Gradle 配置/凭据或项目锁文件。共享缓存会影响共用它的项目，重建可能重新下载。请先关闭相关构建进程；Windows 正在使用的 SDK 文件可能被系统锁定，失败会如实报告，保留尚未删除的文件。macOS 另提供当前项目 iOS 生成缓存清理，不删除 `ios/Flutter` 源文件或全局 DerivedData。

## 十三、<span id="menu-migration">迁移</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

安装本包后停用旧 Flutter 独立菜单，包括 Terminal 的旧 pub-get 项。本包的“清理当前 Flutter 项目构建产物”负责 Flutter 全平台产物；Terminal 的“清理 Android / OpenHarmony 构建产物”同时适用于 Flutter 根目录和两类原生工程，只清对应平台产物。iOS/Xcode 清理位于 iOS 辅助菜单。各 Flutter 单功能管理入口转到本包，只增减对应动作；旧源代码和运行数据保留供实现参考和排查。卸载统一组不会重新启用已停用的旧菜单。

现有运行、依赖提取、SDK 查询/管理、打包和代码生成流程复用本仓库对应工具；这些入口及附带 worker 都约束到项目 FVM。静态产物清理在 FVM 检查前分发，包内 `Tools/CleanBuildArtifacts.zsh` 与 `JobsTerminalOpener/Scripts/CleanBuildArtifacts.zsh` 保持逐字节一致，安装后不依赖 Terminal 包或源码仓库。更新这些工具时应同步本包资源并运行回归测试。Mac / Windows 共用的 `FlutterProjectTools.dart` 必须保持逐字节一致。

相对 import 修复由包内 `Tools/RepairPackageImports.zsh` 独立承接，与 `JobsCommand@Flutter/MacOS/小工具/【MacOS】⚙️import =＞package💣.command/` 中主脚本保持逐字节一致，随 `Tools` 资源文件夹打包；安装后的菜单不读取外部脚本仓库。动作 `repair-package-imports` 在 FVM 门禁前分发，旧 `repair-imports` 继续只处理中文路径编码。

## 十四、<span id="installation-validation">macOS 安装与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

菜单安装与卸载统一使用 [图形管理入口](./【MacOS】管理Flutter开发辅助工具Finder扩展.app)。直接打开面板，选择“安装 / 更新”或“卸载”并勾选当前范围内的功能；默认空选，点击操作按钮即确认。每项显示等待、正在安装 / 卸载、成功或失败；底部日志实时滚动，可选择复制或复制全部。运行中锁定选择和关闭入口，结束后保留结果与日志。首次打开或面板源码更新后会在后台编译，失败以桌面提示和启动日志说明。

原同名 `.command` 入口保留，终端只负责唤起独立 GUI，随后结束启动脚本；本次启动任务结束后自动关闭对应终端页，安装 / 卸载、进度与实时日志均由 GUI 后台处理。已有交互 Shell 中手工调用时保留原工作会话。内部实现为 `Scripts/ManageExtension.zsh`；完整仓内单功能入口使用总面板的受限范围。可独立复制的包须整体保留 `.command`、`.app`、Scripts、工程源码和资源。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

每项失败后，点击红色带下划线的“失败，见日志”，会新建 Terminal 会话并用 `cat` 显示本次完整会话日志；现有任务继续，已有终端保留。“日志文件”按钮仍用于在 Finder 中定位原始日志。

运行本目录管理入口，或在 [总管理面板](../【MacOS】🧩管理Finder扩展.command) 勾选需要的一个或多个 Flutter 叶功能。需要完整 Xcode。扩展已启用后才迁移旧菜单；配置备份保留在当前用户应用支持目录 `JobsTerminalOpener/FlutterMenuMigration.*`。

本包 `--features` 使用动作名，和总面板的 `flutter-` 前缀叶 ID 区分。例如只管理运行和 Android 打包：

```shell
/bin/zsh ./【MacOS】管理Flutter开发辅助工具Finder扩展.command \
  --action install \
  --features run,package-android

/bin/zsh ./【MacOS】管理Flutter开发辅助工具Finder扩展.command \
  --action uninstall \
  --features run,package-android
```

固定动作是 `project-setup`、`run`、`pub-get`、`android-dependencies`、`pods-dependencies`、`spm-dependencies`、`ohos-dependencies`、`native-dependencies`、`flutter-precache`、`web-dependencies`、`extract`、`import-dependencies`、`export-gradle-dependencies`、`import-gradle-dependencies`、`export-pods-dependencies`、`import-pods-dependencies`、`export-spm-dependencies`、`import-spm-dependencies`、`export-ohos-dependencies`、`import-ohos-dependencies`、`export-native-dependencies`、`import-native-dependencies`、`export-precache-dependencies`、`import-precache-dependencies`、`export-web-dependencies`、`import-web-dependencies`、`sdk-version`、`sdk-manage`、`ohos-sdk-manage`、`java-manage`、`gradle-download`、`package-ios`、`package-android`、`package-ohos`、`codegen`、`native-doctor`、`harmony-doctor`、`repair-android`、`repair-imports`、`repair-namespace`、`repair-package-imports`、`clean-build-artifacts`、`maintenance`。省略范围即全部动作，未知值停止。内部 `Scripts/ManageExtension.zsh` 的 `--skip-finder-restart` 只把刷新交给外层；`--non-interactive` 仅供面板提交已确认计划并要求明确 `--action`，会实际安装或卸载，公开启动器不接受该开关。

安装日志是系统临时目录的 `JobsFlutterToolsInstall.log`，卸载为管理入口同名 `.log`，具体路径见终端。取消或空选不改变功能配置。

依赖拉取验证：`ruby Tests/PubGetSdkPreparationTests.rb` 在真实伪终端中，用临时项目和假 SDK 覆盖健康复用、未绑定 / 断链 / 损坏准备、取消 / 失败停止、准备后复检、拉取退出码与只读检查；同时验证真实管理器四处取消在串接时阻断后续拉取。`JOBS_TEST_TOOLS_DIR` 可指定已安装 App 的 `Contents/Resources/Tools` 复验资源，不安装真实 SDK、不联网或修改用户工程。

分层依赖验证：`ruby Tests/ProjectDependencyTests.rb` 使用临时工程、假 Gradle / Xcode / OHPM / JS / Flutter 工具和真实伪终端，核对实际解析命令、锁文件策略、目标目录、原生构建参数、取消 / 失败停止、同一内核复用及 `--check` 零工具执行。`python3 Tests/MenuTransportTests.py` 和仓库 `Tests/FlutterInstallerIntegrationTests.rb` 同时覆盖各依赖项的菜单传输、单独选择、共享包映射与禁用拦截。隔离结果不替代真实包源、私库认证、原生构建和设备运行验收。

依赖导入验证：`ruby Tests/DependencyImportShellTests.rb` 覆盖拖入路径、目录识别、取消、确认与失败码；`dart Tests/DependencyImportTests.dart` 使用临时项目核对真实导出 / 导入、只读预检、冲突、备份和异常目录拦截。`ruby Tests/DependencyImportEndToEndTests.rb` 完整执行分发器、原样交互脚本和原生 Dart，覆盖没有 `lib/` 的合法 Flutter 项目、真实导出快照、拖入路径、确认及取消零写入；`JOBS_TEST_TOOLS_DIR` 可指定已安装 App 的 `Contents/Resources/Tools` 复验打包资源。测试不操作用户项目、不运行 Flutter / pub get 或安装扩展。

隔离验证：`python3 Tests/BuildArtifactDispatchTests.py` 不需要 Dart，使用临时工程和独立资源副本验证无 FVM 分发、取消、原生平台产物、DerivedData 归属、依赖保留、链接保护及旧维护的 FVM 门禁。`python3 Tests/MenuTransportTests.py` 编译真实 Swift 菜单与传输代码，核对清理二级菜单、新动作与旧维护 URL，并截获打开请求，不运行用户工程。

`python3 Tests/PackageImportDispatchTests.py` 通过临时工程与真实伪终端核对相对路径和条件 import 转换、注释 / 字符串保护、第三方 / 生成 / 链接跳过、取消、精确备份、CRLF、只读零写入、Flutter 声明和无 SDK 分发；同时校验独立脚本与包内资源逐字节一致。

`ruby Tests/ProjectJavaManagerTests.rb` 使用假 jEnv / Homebrew / JDK 验证 Java 安装分支、项目声明、取消、中断恢复和 Gradle 参数；`ruby Tests/HarmonyFlutterVersionTests.rb` 使用假 Git / FVM 验证鸿蒙标签、精确 commit、缓存、影子绑定及安全发布；`ruby Tests/NativeFlutterReturnTests.rb` 验证受管鸿蒙 SDK 切回官方 SDK、失败恢复与未知 fork 保护；`ruby Tests/VersionManagerDispatchTests.rb` 验证新入口无需现有 FVM、Java 绑定传递及错误退出。测试不安装真实 SDK、不修改用户工程。

维护引擎回归可先设置 `JOBS_TEST_DART` 为某个已安装 FVM SDK 内的原生 Dart，再运行 `python3 Tests/ToolsTests.py`，使用假的 SDK/插件/缓存；可用 `JOBS_TEST_DART=/项目FVM路径/bin/cache/dart-sdk/bin/dart` 指定测试 Dart。`ruby Tests/PackagingMenuTests.rb` 复用旧打包夹具，并额外验证三平台直达、项目 FVM、包型选择、取消、非法参数与分发退出码；不执行真实构建。完整发布验证另运行仓库 `Tests/FlutterInstallerIntegrationTests.rb` 和 Xcode build / codesign 校验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
