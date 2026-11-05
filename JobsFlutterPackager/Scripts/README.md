# Flutter 打包脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口与行为](#jobs-toc-heading-2)
- [二、运行方式](#jobs-toc-heading-3)
- [三、构建后启用与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**SDK 获取策略：** 必需 SDK 的下载、安装中的网络获取及 Flutter 首次启动补齐 Dart / 引擎组件，默认失败自动持续重试，直到成功或用户按 Ctrl+C / 结束进程；不再询问是否重试，也不设次数或总时长上限。退避默认为 2、4、8、16、30 秒；`JOBS_SDK_RETRY_DELAY` / `JOBS_SDK_RETRY_MAX_DELAY` 可配置。保留工具原生进度与已有缓存，每次获取输出追加保存到原日志旁的 `.attempts.log`；版本选择、真正的许可证 / 权限操作及原始入口确认保留。确定的权限、磁盘、架构、参数或不存在版本错误直接说明原因并停止；项目构建与代码生成失败不整体重放。`--check` / `--help` 继续只读。

运行和打包在实际 `run` / `build` 前，先为已选设备 / 打包平台执行对应 `flutter precache --ios|--android|--web|--macos|--ohos`，平台资源获取失败持续重试；不会因此反复构建 App。鸿蒙先检查适配 SDK 是否支持 `--ohos`，不支持时在构建前明确说明。

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

> 本目录属于 [JobsFlutterPackager](../README.md)。[**Flutter**](https://flutter.dev/) 业务脚本自包含，随 App Resources 打包，不读取原 [**Sourcetree**](https://www.sourcetreeapp.com/) 目录，不通过 [**Finder**](https://support.apple.com/guide/mac-help/welcome/mac) 扩展进程直接执行构建。


**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，默认 `build`。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。默认不清理；UI 仅在应用程序安装模式显示清理选项，退出该组合就清空。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、入口与行为 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 调用方 | 职责与边界 |
| --- | --- | --- |
| [PackageFlutter.zsh](./PackageFlutter.zsh) | [**Terminal**](https://support.apple.com/guide/terminal/welcome/mac) 私有载体或手动终端 | 当前 Flutter 根目录重验；自述与回车确认；[**fzf**](https://github.com/junegunn/fzf) 选择 Android / iOS / 鸿蒙；Android 再选 APK / AAB，鸿蒙再选 HAP / APP；pub get、构建、核验产物 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | [**Xcode**](https://developer.apple.com/xcode) Build Phase | 注册本 App 中的固定扩展，确认当前精确路径启用后刷新 Finder；不运行 Flutter |

`--platform ios|android|ohos` 可直接指定平台并跳过平台选择；省略时兼容旧 CLI 的 fzf 选择。统一 Finder 菜单会传入此参数。iOS 或平台和产物都已指定时不需要 fzf。

打包默认 `release`，支持 `--mode release|debug|profile`、`--flavor NAME` 和 Android `--target apk|appbundle|all`。项目 [**FVM**](https://fvm.app/) 固定存在时不静默回退系统 SDK。Android 要求 JDK 17；[**iOS**](https://developer.apple.com/ios/) 要求完整 Xcode、项目签名，含 Podfile 时要求 [**CocoaPods**](https://cocoapods.org/)。需要交互选择且 fzf 不可用时提示 `brew install fzf` 并停止，不采用编号回退或自动安装。

Android 根据模式 / flavor 匹配非空 APK / AAB，可接受本轮构建命中 [**Gradle**](https://gradle.org/) 缓存；iOS 要求此次新导出的 IPA，只有 xcarchive 或旧 IPA 会报告失败。可用 `OPEN_AFTER_BUILD=0` 禁止构建后打开产物目录。

鸿蒙通过 `--ohos-target hap|app|all` / `OHOS_BUILD_TARGET` 预设包型，省略时 fzf 首选 HAP；`--flutter-sdk` / `FLUTTER_OHOS_SDK` 可指定鸿蒙适配 SDK 根目录。已有 FVM 配置但本地 SDK 缺失时停止，不自动下载。鸿蒙拒绝非空 flavor，使用工程默认 product / target；缺少 `ohos/build-profile.json5` / `ohos/oh-package.json5`、有效 `DEVECO_SDK_HOME` 或健康 Node.js / npm / ohpm / hvigorw / Java 时，在 pub get 前停止。CLI 会逐个检查 `flutter build hap` / `flutter build app` 能力。

DevEco 可由 `DEVECO_STUDIO_HOME` / `TOOL_HOME` 指定，只有一个已安装版本时自动发现；兼容 `HOS_SDK_HOME`，不把 `OHOS_SDK_HOME` 当作相同路径。鸿蒙 HAP / APP 从 `build/ohos/` 或平台模块 `build/**/outputs/` 收集非空文件；允许增量复用旧产物并明确提示，未签名包警告，签名安装和发布单独验收。环境只在当前进程生效；不安装升级 SDK、不创建平台、不改签名。详见[功能说明](../README.md)。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```shell
/bin/zsh ./PackageFlutter.zsh \
  --project /path/to/flutter-app \
  --mode release

/bin/zsh ./PackageFlutter.zsh \
  --check \
  --project /path/to/flutter-app

/bin/zsh ./PackageFlutter.zsh --help
```

正常运行先显示影响和取消方式，再等待回车；fzf 中 Esc / Ctrl+C 取消。`--check` 只验证参数与项目身份，不创建日志、不执行 Flutter；`--help` 只显示帮助。脚本不执行 clean、不安装升级环境、不更改 Git，不提供假包或离线演示回退。

业务日志在系统临时目录每次独立的 `JobsFlutterPackager.*/PackageFlutter.log`，终端显示实际位置；原生 Flutter 输出同步保存。产物保留在项目的 `build/ios/ipa/`、`build/app/outputs/flutter-apk/` 或 `build/app/outputs/bundle/`。终端关闭或中断会影响前台构建，失败后可以重试；不会自动清理项目。

鸿蒙产物也可能位于 `build/ohos/hap/`、`build/ohos/app/` 或 `ohos/` 平台下的 `build/**/outputs/`；脚本打印实际非空包路径，保留原输出，不把中间文件当最终包。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、构建后启用与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

`EnableFinderExtension.zsh` 只接受此工程完整 Xcode 构建上下文；日志为系统临时目录 `JobsFlutterPackagerBuildPhase.log`。单独安装入口设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 后自行注册，避免重复启用。隔离构建也设置该开关，只跳过本自定义阶段，不启用扩展或重启 Finder；本机 Xcode 27.1 的自动 LaunchServices 登记仍会发生，不能用 `LS_REGISTER_URL=NO` 等未生效参数声称完全无登记。验证后按本次临时 App 精确路径注销，并确认 PlugInKit 记录已移除。

正常 Build Phase 未跳过时，会停止同名旧宿主、注册并启用扩展，最多有限轮询当前精确 appex 路径，成功后刷新 Finder。失败记录诊断并留下 `JobsFlutterPackagerNeedsFinderRestart` 标记，交由宿主后续重试；旧路径的 `+` 状态不算成功。

语法验证使用 `/bin/zsh -n`。独立安装、注册、注销和 Finder 刷新通过假系统命令与临时夹具回归；真实 Flutter 构建、权限授权和安装后的菜单须在目标机器单独验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
