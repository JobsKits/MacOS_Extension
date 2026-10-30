# JobsFlutterRunner 脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与风险](#runtime)
- [二、验证与故障](#verify)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录负责[独立 Flutter 运行扩展](../README.md)的终端交互、设备选择、后台会话和构建后注册。业务与 JSON 脚本必须放在一起；App Bundle 只打包这两份业务资源。

| 文件 | 入口与职责 |
| --- | --- |
| `RunFlutterProject.zsh` | `/bin/zsh -l` 运行；`--project <根目录>` 验证 Flutter、选择设备、启动或连接 launchd 会话、追踪日志和热重载。无参数时可输入或拖入根目录。 |
| `FlutterRunner.jxa` | macOS `osascript -l JavaScript` 调用；严格项目声明识别、设备 / 模拟器 JSON、launchd plist 和 Flutter machine 控制数据；不执行用户字符串中的 Shell 命令。 |
| `EnableFinderExtension.zsh` | Xcode Build Phase 的扩展注册与 Finder 刷新；`JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过，用于隔离构建及外层安装器接管。 |

## 一、<span id="runtime">运行与风险</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行：

```shell
/bin/zsh -l ./RunFlutterProject.zsh \
  --project '/实际 Flutter 项目根目录'
```

先显示用途、影响与日志位置，回车继续、非空输入取消。复用项目 FVM SDK 或 PATH Flutter；未找到时给出提示，不自动安装。终端设备编号按项目平台目录过滤，并允许重新加载。有 `ios/` 才提供 iOS 模拟器入口；没有可用 iOS 模拟器时，使用内置 `xcrun simctl` 逻辑列出设备型号和已安装 iOS runtime，选择后创建并启动；型号与系统分别列出，型号按本机有无可搭配系统优先推荐，选定型号后只列匹配该型号的系统，组合是否受支持由 Xcode 创建命令最终校验；创建结果不明确时不自动重试，只有明确不兼容且输入 `r` 才重新选择，一路回车不会反复弹出列表；缺 runtime 时提示前往 Xcode Settings → Components（旧版 Platforms）安装，不自动安装 Homebrew、Xcode 或 runtime。

有 `android/` 才提供“Android 模拟器（启动已有 / 缺失时初始化）”。优先选择已有 AVD，也可新建；清单为空时直接进入“型号 → 系统镜像 → 确认创建”。优先复用本机完整镜像，只列当前主机架构对应的稳定手机 / 平板镜像；需要其它版本时从 Google 官方源查询，最终确认后才下载精确选中的镜像和缺失 emulator / platform-tools，SDK 许可证仍由本人阅读接受。不会覆盖同名 AVD、清除数据或升级其它包。子层支持 `←` 和返回行，最终确认可输入 `b` 返回镜像选择；Esc、空输入结束或其它取消输入不创建。模拟器通过独立 launchd job 启动；用 adb 的 AVD 名称精确匹配序列号，最多等 240 秒开机，再等待同一设备进入 Flutter 列表，随后直接运行当前工程。已启动的目标设备直接复用。

SDK 按 `ANDROID_HOME`、`ANDROID_SDK_ROOT`、用户 `Library/Android/sdk` 及 PATH emulator 解析，工具保持同一 SDK。已有 AVD 无需 Java / avdmanager；创建需要可用 Java 和 Android SDK Command-line Tools。SDK 或命令行工具完全缺失时，先运行独立“初始化 Android 模拟器”准备工具链，或在 [**Android Studio**](https://developer.android.com/studio) SDK Manager 安装，再重新运行。Android 模拟器 job 与 Flutter 会话分开，不因终端关闭而退出。命令语法参见 [avdmanager](https://developer.android.com/tools/avdmanager) 与 [sdkmanager](https://developer.android.com/tools/sdkmanager)。

后台会话以项目 / 设备为独立身份，通过 `launchctl bootstrap gui/<UID>` 管理 `/bin/zsh` 同脚本的私有 `--worker` 入口。启动前将脚本与 helper 保存至会话目录，Worker 的输入连接 FIFO，不继承终端 stdin、EOF 或 HUP。`--worker` 只用于已准备的会话，无独立用户确认。 保活用的 fd 9 以读写模式打开 FIFO，传给 Flutter stdin 的 fd 0 则单独以只读模式打开；macOS 下 Dart 异步 stdin 无法正确消费读写模式的 FIFO，不能直接 `<&9`。

终端由 `FlutterRunner.jxa watch-log` 增量读取并分级展示日志，保留跨写入的 UTF-8 和半行；`format-log` 可离线重放验证。依赖版本明细与已知系统索引噪声折叠；快捷指令 / Spotlight 的 `WF*` 参数转换与缺失扩展诊断只显示一条 `[提示]`，不会因其中的 `Failed` 被误标为 Flutter 构建失败。真正编译错误、machine 应用错误、非零索引错误计数、停维依赖、SPM 插件名称和未知事件保留；仅 `app.started` 显示启动成功。完整 machine 日志仍保存到用户资源库 `Application Support/JobsFlutterRunner/sessions/` 的 `run.log`，不影响后台控制。操作日志在系统临时目录，终端打印精确路径。`r` 热重载、`R` 热重启、`s` 停止、`d` 离开，输入后回车；关闭 Terminal、Ctrl+C 或 EOF 都只离开查看。重复右键并选择相同设备可重连。注销 / 关机仍会终止当前用户会话，不提供自动重启。

Flutter 可能下载项目依赖、生成构建目录；创建模拟器会增加一个本机设备。停止只处理所选会话，不向无关 Flutter、模拟器或终端进程发信号。日志保留项目路径与目标输出，分享前检查。卸载菜单不清理或停止已有后台会话。

## 二、<span id="verify">验证与故障</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

隔离测试与构建命令见[工程验证说明](../README.md#verify)。脚本语法检查不会启动项目：

```shell
/bin/zsh -n ./RunFlutterProject.zsh
/bin/zsh -n ./EnableFinderExtension.zsh
ruby ../Tests/FlutterRunnerShellTests.rb
ruby ../Tests/FlutterRunnerAndroidTests.rb
ruby ../Tests/FlutterRunnerJSONTests.rb
ruby ../Tests/FlutterRunnerLogTests.rb
```

设备发现、模拟器就绪使用有界超时，超时后显示诊断并允许重试；持续运行的 Flutter 不设整体超时。`launchctl` 失败时确认从当前登录桌面的 Terminal 启动。构建日志报签名、依赖或平台工具错误时修复目标环境，不把提交 launchd 成功当作 Flutter 运行成功。真实 launchd 配合假 Flutter 的 HUP 存活、日志增长、重连与停止已通过；Finder 安装、真实设备运行和关闭终端后的真实 Flutter App 生命周期仍需单独验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
