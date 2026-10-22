# JobsFlutterCodegen

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、菜单与 SDK 范围](#section-1)
- [二、安装与卸载](#section-2)
- [三、终端与只读检查](#section-3)
- [四、工程与请求链](#section-4)
- [五、验证与排查](#section-5)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

独立的 [**macOS**](https://www.apple.com/macos/) [**Finder**](https://support.apple.com/zh-cn/102339) 右键扩展，为当前 [**Flutter**](https://flutter.dev/) 项目提供“Flutter 自动化生产代码”。项目由 Jobs 维护，状态为维护中。宿主在后台转交请求，业务在系统 Terminal 中交互执行。

先执行 `flutter pub get`，再按项目依赖和配置运行实际可用的生成任务。支持 build_runner、Flutter launcher icons / native splash、Flutter l10n、ffigen、带 `@ConfigurePigeon` 的 Pigeon 配置和 protobuf / grpc。缺少声明或配置的任务会跳过；任何选中任务失败立即停止并保留非零退出码。

本目录是 [MacOS@Extension](../README.md) 中的普通源码目录；保留自己的宿主 App、Finder 扩展、Xcode 工程和独立安装 / 卸载脚本。业务资源完整打包在 App 中，单独携走本目录即可构建；运行时不需要 SourceTree 或其它扩展目录。

| 操作 | 实际行为 |
| --- | --- |
| 总安装器勾选“Flutter 自动化生产代码” | 只构建并启用本安装单元，可与其它功能分别选择 |
| [独立安装](./【MacOS】安装Flutter自动化生产代码Finder扩展.command) | 阅读自述后直接回车安装；任何非空输入（包括空格）跳过，EOF 停止 |
| Finder 单选 Flutter 根目录或根目录内空白处 | 二次校验项目后打开 Terminal，展示业务自述与目标 |
| [独立卸载](./【MacOS】卸载Flutter自动化生产代码Finder扩展.command) | 停用并注销固定扩展，停止对应进程，清理本工程产物；保留业务项目与 SDK |

## <span id="section-1">一、菜单与 SDK 范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

只接受当前层 `pubspec.yaml` 以 `dependencies.flutter.sdk: flutter` 声明 Flutter 的真实普通目录，不递归搜索，不接受文件包、目录符号链接、多选、普通 Dart 包或 `ios/` 子目录。系统桌面空白处隐藏此功能；桌面上选中的 Flutter 项目仍可使用。

SDK 顺序为项目 `.fvm/flutter_sdk`，再到 PATH 中可执行的 Flutter。发现 [**FVM**](https://fvm.app/) 配置但项目 SDK 缺失时停止，提示先安装 / 切换项目 SDK，不回退到全局 SDK；Dart 必须来自选定的同一 SDK，不跨 SDK 混用。不会修改全局 Flutter 默认版本。

会修改项目锁文件、依赖元数据及生成文件。默认不执行 `flutter clean`，不主动传入强制删除冲突输出参数；生成器仍会改写其管理的产物，执行前请保存修改。`CLEAN_FIRST=1` 与 `DELETE_CONFLICTING_OUTPUTS=1` 启用时须在终端输入精确大写 `YES` 后才执行；`WATCH=1` 仅在交互终端启用。

## <span id="section-2">二、安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

最低 macOS 12.0，需要完整 [**Xcode**](https://developer.apple.com/xcode)、macOS SDK 和可用本机签名。安装器检查 `xcodebuild`、`xcrun`、`pluginkit` 等系统命令，不自动下载依赖或修改 `xcode-select`。两个 `.command` 裸露在本目录，与本 README 平级。

独立安装产物在 `./work/DerivedData/Build/Products/Debug/JobsFlutterCodegen.app`；总安装器产物在总仓的 `work/JobsFlutterCodegenDerivedData/`。安装及卸载会刷新 Finder，请先完成 Finder 中的重要操作。系统若尚未授权，请启用对应 Finder 扩展，并允许宿主 App 自动化控制 Terminal。

独立安装与卸载日志分别为系统临时目录中的 `JobsFlutterCodegenInstall.log` / `【MacOS】卸载Flutter自动化生产代码Finder扩展.log`。宿主初始化、URL 接收、Terminal 派发和退出状态追加到 `JobsFlutterCodegen.log`；业务日志位置由终端输出。

## <span id="section-3">三、终端与只读检查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行以下命令，不安装 Finder 扩展：

```shell
/bin/zsh ./Scripts/GenerateFlutterCode.zsh \
  --check \
  "/路径/Flutter项目"
```

`--check` 只检查项目声明、SDK 选择和任务计划，不调用 Flutter / Dart、不写业务日志。`--help` 显示参数。实际执行去掉 `--check`，在终端阅读自述并回车继续；`Ctrl+C` 取消。选项可放在项目路径前后，路径包含空格或中文时保持引用。

## <span id="section-4">四、工程与请求链</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```text
./
├── JobsFlutterCodegen.xcodeproj/          # 宿主与 Finder Extension，共享 Scheme
├── JobsFlutterCodegen/                   # 后台宿主、日志与 Terminal 派发
├── JobsFlutterCodegenFinderSync/         # 菜单上下文与点击时重新校验
├── JobsFlutterCodegenShared/             # 精确 Flutter 判定与 URL 请求
├── Scripts/                 # 自包含业务资源与构建后启用入口
├── Tests/                   # 临时项目、假脚本与路径隔离验证
├── 【MacOS】安装Flutter自动化生产代码Finder扩展.command
├── 【MacOS】卸载Flutter自动化生产代码Finder扩展.command
└── README.md
```

| 配置 | 值 |
| --- | --- |
| 工程 / Scheme | `JobsFlutterCodegen.xcodeproj` / `JobsFlutterCodegen` |
| 宿主 / Bundle ID | `JobsFlutterCodegen.app` / `com.jobs.JobsFlutterCodegen` |
| 扩展 / Bundle ID | `JobsFlutterCodegenFinderSync.appex` / `com.jobs.JobsFlutterCodegen.FinderSyncExtension` |
| Finder 请求 | `jobsfluttercodegen://generate?path=...`，只允许一个绝对路径参数 |
| 打包业务资源 | `Scripts/GenerateFlutterCode.zsh` |
| 运行窗口 | 无管理窗口或 Dock 图标，完成初始化和全部派发后退出 |

```mermaid
flowchart LR
    A[FinderSync.swift 验证当前根目录] --> B[URL 请求]
    B --> C[AppDelegate.swift 验证并接收]
    C --> D[FlutterCodegenLauncher.swift 私有载体]
    D --> E[Terminal 业务自述与确认]
    E --> F[GenerateFlutterCode.zsh]
```

Terminal 仅收到一条物理单行命令。多行业务代码和用户路径留在私有载体，目录权限 `0700`、脚本 `0600`；路径按数据传递，单引号、反斜线、命令替换和控制字符不进入 Terminal 输入流。正常退出、失败或可捕获中断时只清理本次载体，保留业务日志和其它并发请求。

构建阶段的 `Scripts/EnableFinderExtension.zsh` 默认负责注册并刷新本扩展；外层安装器与隔离构建使用 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过该阶段的系统修改。

## <span id="section-5">五、验证与排查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

`Tests/FlutterProjectBehaviorTests.swift` 覆盖 Flutter 清单、误判排除、畸形 URL、特殊路径、载体权限、退出码、中断和并发清理，只运行假业务脚本，不启动 Terminal。总仓 `Tests/DesktopFinderMenuTests.rb` 验证桌面背景隐藏、项目菜单及点击回调；`Tests/FlutterInstallerIntegrationTests.rb` 核对安装与卸载映射。

| 现象 | 排查 |
| --- | --- |
| 菜单未出现 | 确认只选一个 Flutter 根目录，检查系统扩展开关和清单格式 |
| 点击后无 Terminal | 查看 `JobsFlutterCodegen.log`，核对请求接收 / 派发状态和 Terminal 自动化权限 |
| 提示 FVM 项目 SDK 不可用 | 在终端按项目配置执行 FVM 安装 / 切换，然后重试 |
| 业务失败 | 查看 Terminal 与业务日志；失败码会保留，不把部分成功当成整体成功 |
| 卸载后菜单短暂残留 | 重新打开 Finder 窗口或注销登录，检查 `pluginkit` 对应固定 Bundle ID |

源码、隔离回归和构建验证不能代替目标设备的 Finder 菜单与真实项目业务验收。本工程未自动执行真实业务、安装启用或重启 Finder。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
