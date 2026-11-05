# JobsFlutterDoctor Scripts

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、入口与依赖](#section-1)
- [二、运行方式](#section-2)
- [三、日志与验证](#section-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

**SDK 获取策略：** 必需 SDK 的下载、安装中的网络获取及 Flutter 首次启动补齐 Dart / 引擎组件，默认失败自动持续重试，直到成功或用户按 Ctrl+C / 结束进程；不再询问是否重试，也不设次数或总时长上限。退避默认为 2、4、8、16、30 秒；`JOBS_SDK_RETRY_DELAY` / `JOBS_SDK_RETRY_MAX_DELAY` 可配置。保留工具原生进度与已有缓存，每次获取输出追加保存到原日志旁的 `.attempts.log`；版本选择、真正的许可证 / 权限操作及原始入口确认保留。确定的权限、磁盘、架构、参数或不存在版本错误直接说明原因并停止；项目构建与代码生成失败不整体重放。`--check` / `--help` 继续只读。

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录包含“Flutter 项目体检”的自包含业务资源及 Xcode 构建后启用入口。功能用途、SDK 规则、安装与卸载见[工程说明](../README.md)。


**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，默认 `build`。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。默认不清理；UI 仅在应用程序安装模式显示清理选项，退出该组合就清空。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## <span id="section-1">一、入口与依赖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责与影响 |
| --- | --- |
| [InspectFlutterProject.zsh](./InspectFlutterProject.zsh) | 与 SourceTree 对应 Jobs 脚本保持共用业务主体一致，仅 ANSI 过滤采用本仓实时进度适配；运行时不访问 SourceTree。`--check` 不执行 Flutter / Dart，不写日志；实际执行由 Terminal 自述确认后进行。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | Xcode Build Phase 注册并启用 `com.jobs.JobsFlutterDoctor.FinderSyncExtension`，刷新 Finder。手动无构建上下文时停止；`JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过。 |

业务依赖 macOS 自带 zsh 与项目所选 Flutter SDK，Dart 必须来自同一 SDK；缺 SDK 或 FVM 项目链接损坏时停止。不会自动安装全局工具。体检报告有异常不会显示“全部通过”，不会自动安装 SDK、Xcode 或 Android 工具。

## <span id="section-2">二、运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下命令从本 README 所在目录执行：

```shell
/bin/zsh ./InspectFlutterProject.zsh \
  --check \
  "/路径/Flutter项目"
```

实际执行移除 `--check`；`--help` 可查看参数和环境选项。`--check` 用于只读预检，不代表真实 Flutter / Dart 工具链已经运行通过。

## <span id="section-3">三、日志与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

业务日志位置在实际终端输出中显示，保留每次操作对应记录。外部命令的 ANSI 过滤按数据块实时处理，Flutter 首次初始化或下载 SDK 缓存时，原生回车进度不等待换行，跨块 UTF-8 与控制序列正常保留 / 过滤。构建挂载日志是系统临时目录中的 `JobsFlutterDoctorBuildPhase.log`，待刷新标记为 `JobsFlutterDoctorNeedsFinderRestart`。私有 Terminal 请求目录只包含本次脚本，退出时精确清理。

除本仓为 SDK 原生回车进度增加的 `strip_ansi_text` 流式适配外，共用业务主体由总仓 `Tests/FlutterMaintenanceResourceParityTests.rb` 与 SourceTree 标准源逐字节核对；独立与聚合适配函数必须一致，实时输出另由 `JobsFlutterTools/Tests/SdkDownloadProgressTests.rb` 用假 SDK 验证。本轮只修改右键菜单资源，不修改 SourceTree；独立携走本工程不要求 SourceTree 存在。原生路径载体和菜单回归只调用假脚本，真实 Flutter 体检或代码生成需在目标设备另行运行。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
