# Flutter 运行前环境体检

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

内部模块由 [**Flutter**](https://flutter.dev/) 运行器加载；不单独启动，不安装工具、不切换 SDK、不修改工程。只写本轮运行日志。

## 一、<span id="checks">检查与门禁</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 未适配的原生插件按一行一个的列表展示，便于逐项核对。

- `jobs_flutter_harmony_discovery_rows` 有界读取系统 USB 调试节点及可用的 HDC 目标，将尚未进入可运行列表的连接显示为诊断行。无 HDC 时仍能发现明确的 HDC USB 产品；仅品牌匹配不认作鸿蒙。选中后由运行器在当前流程承接随包鸿蒙环境准备模块，完成后复检并只匹配原设备；诊断标识不能直接成为 Flutter 设备 ID，相同身份与已显示的真实运行目标精确去重，保留其它物理设备。
- HDC 发现独立于编译环境是否完整：先复用本轮工具链，再按显式 `OHOS_SDK_HOME`、`DEVECO_SDK_HOME`、DevEco/CLT 根目录、当前进程 `PATH` 及标准安装目录定位；显式目录不悄悄换成另一套 SDK，多版本歧义明确提示。支持 SDK 自身 `toolchains/hdc`、DevEco 的 `default/openharmony`、`harmonyos` 及已选 SDK 根下的数字版本目录。
- HDC 和 USB 取证相互独立：USB 读取失败或 plist 损坏时保留已确认 HDC 目标；HDC 命令失败时保留原始输出及退出码，继续查询 USB，绝不将错误文字作为设备。HDC 的 `Unauthorized`、`Offline` 和服务消息会显示诊断提示并写入证据，不伪造运行设备。已开开发者模式仍需打开 USB 调试并在手机确认本机授权；有关状态以 [**HDC 官方说明**](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/hdc/)及本轮实际输出为准。
- `harmony-run-target` 使用原 HDC ID 或 USB 物理位置与序列号精确匹配一个受支持的鸿蒙 Flutter 设备；USB 断开、换机、重号、缺序列号、未授权或重复目标均不猜测其它设备。准备只执行一次，运行器之后只进行有界设备查询，失败或取消停止本轮。

- `jobs_flutter_preflight_overview` 使用运行器已准备的同源 Dart、SDK 源码依赖和工具快照，调用当前 SDK 的官方本地验证器，并查询构建能力及依赖索引；同时核对工程 FVM 声明、实际 SDK 版本或鸿蒙固定提交。首轮完整显示 iOS、Android、OpenHarmony 三端结果，缺失平台目录明确显示未就绪。同一工程与 SDK 身份下，后续仍实际复检，但只展示状态或缺项变化的结果；完全未变化时仅显示一行提示，不重复展开其它平台的插件清单。更换工程、FVM 声明或 SDK 工具身份后重新完整展示，所选平台的运行门禁始终保留。
- iOS 检查 Xcode、CocoaPods 及 iOS 构建能力；Android 检查 doctor 的 Android 工具链完整结果，包含 Java、SDK 与许可证；OpenHarmony 检查 HAP 能力、DevEco/CLT、SDK 编译组件、Node、OHPM、Hvigor、HDC、Java、工程结构及移动端原生插件的平台声明。
- Hvigor 优先使用当前工程 `ohos/hvigorw`，按原生 Shell 在 `ohos/` 内检查版本，不要求脚本执行位；不存在时再查配套工具与当前进程路径。
- `jobs_flutter_preflight_require 平台 设备ID` 在运行前校验结果，只要求所选平台通过。未知平台、缺失体检、工具失败、超时、无法解析及依赖 SDK 不一致均阻止运行。
- 设备选择后再次核对工程与 SDK 摘要、依赖索引和所选平台工具链；鸿蒙还须在 HDC 授权连接列表中精确找到所选设备。菜单停留期间切换版本、修改依赖、移除平台目录或撤销设备授权均不会沿用陈旧通过结果。
- 本地官方验证器仅执行 Android 工具链、Xcode／CocoaPods、Chrome 等本地项目，不执行公网资源检测、设备扫描或远端版本查询；最多等待 45 秒，全部选定验证器结束后才输出完整 JSON。超时、源码依赖缓存缺失、API 不兼容、格式错误或半成品报告均拒绝运行，不从中断日志推断成功。其它平台缺项仍按各平台实际结果判断，避免误拦健康目标；日志保留原退出码及详细信息。体检通过仅说明已检查的环境前置条件通过，签名、公司仓库可达性及业务编译仍以实际执行结果为准。

## 二、<span id="integration">集成与日志</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 运行器提供 `PROJECT_PATH`、`FLUTTER_BIN`、`LOG_FILE`、`log` 与 `run_bounded`，保留本目录的 Shell、JXA 与 `DoctorScope.dart` 模块资源；路径从实际脚本位置解析。
- 详细结果位于运行器日志旁的 `.preflight.doctor`、`.preflight.build`、`.preflight.packages`、`.preflight.ohos-*` 文件；连接取证另存 `.harmony-discovery`，记录实际 HDC 路径、命令退出码和解析结果，原始文件为 `.harmony-hdc.targets`、`.harmony-usb.plist`、`.harmony-visible.ids`。只保留本轮调试信息，不采集账号凭据；取证失败不能推断手机没有连接。
- 体检不自动接受许可证，不启动模拟器，不执行依赖拉取或应用构建。选中有明确连接证据的鸿蒙设备后，运行器在当前流程准备缺项并重新体检；许可证仍由本人确认，失败或取消停止本轮。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
