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

**下载版本与组件：** 运行器在 SDK 安装 / 首次补齐及选定平台预缓存之前，先展示项目声明 Flutter、实际解析的 SDK 根路径、本地 Git 精确 tag / 提交或本地版本记录、下载宿主架构、目标平台和 Engine 提交；不靠执行 Flutter / Dart 探测版本。Git 查询只读、禁止隐式联网且单次最多 5 秒，无法确认就明确未解析。Darwin 下载架构按物理 ARM 能力识别，兼容 Rosetta。Dart 目标版本只采信 SDK 明确声明，或与目标 Engine 一致的版本 JSON / 当前缓存 stamp；`.old` 和不匹配的缓存不当作本次目标。尚无可信记录时显示“版本尚未解析，待目标 SDK 下载完成后确认”，目标版本展示不代表已经安装验收。

已打开的终端使用启动时的脚本快照，源码改动不替换当前下载进程；安装 / 更新菜单后重新发起才加载新的上下文展示。版本上下文与重试提示进入本次操作日志，原生机器输出文件及退出码保持原路径。

**SDK 获取策略：** 必需 SDK 的下载、安装中的网络获取及 Flutter 首次启动补齐 Dart / 引擎组件，默认失败自动持续重试，直到成功或用户按 Ctrl+C / 结束进程；不再询问是否重试，也不设次数或总时长上限。退避默认为 2、4、8、16、30 秒；`JOBS_SDK_RETRY_DELAY` / `JOBS_SDK_RETRY_MAX_DELAY` 可配置。保留工具原生进度与已有缓存，每次获取输出追加保存到原日志旁的 `.attempts.log`；版本选择、真正的许可证 / 权限操作及原始入口确认保留。确定的权限、磁盘、架构、参数或不存在版本错误直接说明原因并停止；项目构建与代码生成失败不整体重放。`--check` / `--help` 继续只读。

运行和打包在实际 `run` / `build` 前，先为已选设备 / 打包平台执行对应 `flutter precache --ios|--android|--web|--macos|--ohos`，平台资源获取失败持续重试；不会因此反复构建 App。鸿蒙先检查适配 SDK 是否支持 `--ohos`，不支持时在构建前明确说明。

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录负责[独立 Flutter 运行扩展](../README.md)的终端交互、设备选择、后台会话和构建后注册。业务与 JSON 脚本必须放在一起；App Bundle 只打包这两份业务资源。

设备、型号和系统选择使用 fzf 全屏临时界面，退出后恢复原来的终端日志，避免内嵌高度模式在 Terminal 重绘时留下两份菜单。用户的 fzf 默认布局不影响本次选择；回车选择，Esc 取消。

iOS 清单来自当前 Xcode 的 CoreSimulator，包含已关闭的模拟器。Device Hub 看不到时，先将过滤器切到 `All Devices` / `Simulators` 并展开 `Available` 分组。历史测试设备不会随工程关闭而删除；清理时按设备 UUID 使用 Xcode 或 `simctl delete` 注销，不直接删除 `Devices` 目录，也不删除共享 Runtime。

| 文件 | 入口与职责 |
| --- | --- |
| `RunFlutterProject.zsh` | `/bin/zsh -l` 运行；`--project <根目录>` 验证 Flutter、选择设备、启动或连接 launchd 会话、追踪日志和热重载。无参数时可输入或拖入根目录。 |
| `FlutterRunner.jxa` | macOS `osascript -l JavaScript` 调用；严格项目声明识别、设备 / 模拟器 JSON、launchd plist 和 Flutter machine 控制数据；不执行用户字符串中的 Shell 命令。 |
| `EnableFinderExtension.zsh` | Xcode Build Phase 的扩展注册与 Finder 刷新；`JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过，用于隔离构建及外层安装器接管。 |


**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，默认 `build`。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。默认不清理；UI 仅在应用程序安装模式显示清理选项，退出该组合就清空。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## 一、<span id="runtime">运行与风险</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行：

```shell
/bin/zsh -l ./RunFlutterProject.zsh \
  --project '/实际 Flutter 项目根目录'
```

先显示用途、影响与日志位置，回车继续、非空输入取消。复用项目 FVM SDK；项目声明版本但链接未就绪时，自动调用本机 [**fvm**](https://fvm.app) 补齐，缓存已有版本只绑定、没有才下载。未声明 FVM 时沿用 PATH Flutter；不安装或升级全局 Flutter。终端设备编号按项目平台目录过滤，并允许重新加载。有 `ios/` 才提供 iOS 模拟器入口；没有可用 iOS 模拟器时，使用内置 `xcrun simctl` 逻辑列出设备型号和已安装 iOS runtime，选择后创建并启动；型号与系统分别列出，型号按本机有无可搭配系统优先推荐，选定型号后只列匹配该型号的系统，组合是否受支持由 Xcode 创建命令最终校验；创建结果不明确时不自动重试，只有明确不兼容且输入 `r` 才重新选择，一路回车不会反复弹出列表；缺 runtime 时提示前往 Xcode Settings → Components（旧版 Platforms）安装，不自动安装 Homebrew、Xcode 或 runtime。

SDK 补齐会先显示版本、FVM 可执行文件和本次完整日志路径；`fvm install` 的下载 / 初始化输出与 `fvm use` 的绑定输出约每秒原样显示到终端，保留工具提供的百分比、速度、剩余时间和回车刷新，同时保存到 `<操作日志>.fvminstall` / `<操作日志>.fvmuse`。已有 SDK 首次调用 `flutter --version` 时仍可能补齐 Dart / SDK 组件，该检查同样实时显示并保存到 `<操作日志>.version`；后台构建日志也按回车或换行及时显示下载进度。不生成虚假百分比；工具暂时没有输出时继续等待。下载 / 初始化和绑定的单次窗口均为 1800 秒，版本首启单次窗口为 1800 秒，超时自动重试；失败保留原始日志。设备查询等机器 JSON 输出仍只写文件，避免进度混入解析结果。

已打开的旧终端使用启动时的脚本副本，不会自动加载源码修改。菜单需安装 / 更新后重新发起；已有下载可在另一终端用 `tail -f '<本次操作日志>.fvminstall'` 查看，`Ctrl+C` 只退出该查看窗口，不影响原下载。

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

SDK自举前若精确Dart归档已有写入者，会显示PID与缓存路径并等待其释放；只读句柄不阻塞。Ctrl+C结束当前等待，不杀其它会话、不清理续传缓存。
