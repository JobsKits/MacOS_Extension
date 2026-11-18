# `Flutter 运行环境准备`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、准备与隔离](#jobs-toc-heading-2)
- [二、验证边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

供 [**Flutter**](https://flutter.dev/) 终端运行器加载的内部模块，不单独执行。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、准备与隔离 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

- 首次平台体检前先核对当前工程依赖索引是否属于本轮选定 Flutter SDK；缺失或失配时，只在该工程执行当前 SDK 的 `pub get` 并复检。公共只读探针超时124或信号退出（≥128）原样返回，不触发依赖修复。修复成功再刷新体检指纹；公共依赖问题未解决不触发其它平台工具或许可安装。
- 选定 iOS / Android 后，缺失环境直接准备并复检，不再询问是否安装；许可、认证和管理员权限仍由原工具处理，不代签许可。缺失平台仅在私有目录生成后发布新增目录，不覆盖已有平台源码。
- [**iOS**](https://developer.apple.com/ios/) 真机仅准备 [**Xcode**](https://developer.apple.com/xcode) 与首次组件，不为真机运行下载 Simulator Runtime；选择虚拟设备时才由原模拟器流程准备 Runtime。健康 [**CocoaPods**](https://cocoapods.org/) 直接复用；缺失时使用已存在、可执行的 [**Homebrew**](https://brew.sh/) 安装 `cocoapods`，关闭自动更新／全量升级并复检 `pod --version`。没有健康 Homebrew 时明确停止，不用全局 Ruby 安装或静默改环境。
- Android 复用[随包工程组件内核](./Resources/Android/README.md)，按当前工程和绑定 Flutter 的声明准备 compileSdk、build-tools、NDK、CMake；许可证由本人阅读处理；仅命令退出零且本轮末尾明确报告全部接受才继续，兼容有无句点、CR 和 ANSI，不以模糊子串或旧日志当作已接受。SDK Manager 临时工具 JDK 与项目 [**Gradle**](https://gradle.org/) JDK 分开，成功后只向运行器带回已核验 SDK 路径与原选项目 JDK；更新 `android/local.properties` 前保留原文备份并检查并发变化。
- 其它未就绪移动平台按“回车后台补齐；任意字符加回车不补”选择，EOF 跳过。后台任务使用独立工程草稿、Android / Harmony / Pub / Gradle 缓存，不修改当前工程 FVM、依赖索引和共享 SDK，不阻塞原运行。
- 后台只准备 SDK、宿主工具及平台草稿；工程绑定、依赖集成和插件兼容在实际选用时复检并应用，`prepared` 不表示原工程已经支持该平台。已有可用结果复用；失败现场归档后可重新准备。
- 每项目、平台保留独立任务目录及 `prepare.log`、`operations.log`、`status`、`pid`。关闭运行终端后后台任务继续；失败或需要人工授权会在日志中记录，不冒充完成。 运行日志控制中输入 `e` 后回车，可停止经 PID 与出生时间复核属于当前工程的后台准备及其子进程，保留缓存、日志和现场；不按进程名称批量终止。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证边界 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

准备分支、回车 / 跳过 / EOF、原工程保护和隔离状态用假工具验证；测试不下载 SDK、不安装环境、不创建模拟器。真实官方账号授权、兼容插件改造和跨机验证需按实际环境另验。

<a id="🔚" href="#前言">我是有底线的➤点我回到首页</a>
