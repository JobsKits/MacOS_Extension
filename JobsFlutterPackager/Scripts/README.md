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

> 本目录属于 [JobsFlutterPackager](../README.md)。[**Flutter**](https://flutter.dev/) 业务脚本自包含，随 App Resources 打包，不读取原 [**Sourcetree**](https://www.sourcetreeapp.com/) 目录，不通过 [**Finder**](https://support.apple.com/guide/mac-help/welcome/mac) 扩展进程直接执行构建。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、入口与行为 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 调用方 | 职责与边界 |
| --- | --- | --- |
| [PackageFlutter.zsh](./PackageFlutter.zsh) | [**Terminal**](https://support.apple.com/guide/terminal/welcome/mac) 私有载体或手动终端 | 当前 Flutter 根目录重验；自述与回车确认；[**fzf**](https://github.com/junegunn/fzf) 选择 Android / iOS / 鸿蒙；Android 再选 APK / AAB，鸿蒙再选 HAP / APP；pub get、构建、核验产物 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | [**Xcode**](https://developer.apple.com/xcode) Build Phase | 注册本 App 中的固定扩展，确认当前精确路径启用后刷新 Finder；不运行 Flutter |

打包默认 `release`，支持 `--mode release|debug|profile`、`--flavor NAME` 和 Android `--target apk|appbundle|all`。项目 [**FVM**](https://fvm.app/) 固定存在时不静默回退系统 SDK。Android 要求 JDK 17；[**iOS**](https://developer.apple.com/ios/) 要求完整 Xcode、项目签名，含 Podfile 时要求 [**CocoaPods**](https://cocoapods.org/)。fzf 不可用时提示 `brew install fzf` 并停止，不采用编号回退或自动安装。

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
