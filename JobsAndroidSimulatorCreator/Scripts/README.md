# Android 模拟器扩展脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与风险](#jobs-toc-heading-2)
- [二、开发验证](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

> 本目录携带可独立运行的 Android 模拟器核心与 Finder 注册辅助脚本，不依赖其它仓库的运行时文件。

| 文件 | 职责与边界 |
| --- | --- |
| `CreateAndroidSimulator.zsh` | 检查并自动补齐 SDK 与工具，交互创建 / 启动 Android AVD；`--create` 直接新建，`--prepare` 仅准备工具链，`--check` 只读检查，`--help` 显示参数。与聚合桌面资源和项目准备内核保持相同实现。 |
| `EnableFinderExtension.zsh` | Xcode Build Phase 注册当前构建产物、核对扩展启用路径并按标记刷新 Finder；不创建模拟器。独立安装器会跳过自动注册阶段并统一执行注册。 |


**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，默认 `build`。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。默认不清理；UI 仅在应用程序安装模式显示清理选项，退出该组合就清空。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与风险</span><!-- jobs-toc:heading-end -->

在本目录执行：

```shell
/bin/zsh ./CreateAndroidSimulator.zsh --check
/bin/zsh ./CreateAndroidSimulator.zsh --prepare
/bin/zsh ./CreateAndroidSimulator.zsh
```

首屏回车统一授权本次必要工具链自动补齐；健康依赖不升级，缺失 / 损坏 SDK、Java、命令行工具与 emulator 自动补齐并复检，不再另设安装确认。没有本地系统映像时自动读取官方清单，选中后直接安装；安装器退出码为零仍须检查必要组件或映像文件；未就绪继续获取，在线清单的退出零但网络警告同样继续重试。创建仍由最终确认决定，SDK 许可证保留官方本人交互。`--prepare` 仅准备工具链，`--check` 始终只读；创建消耗磁盘，启动消耗内存和 CPU，不删除或覆盖已有 AVD。

CLT 使用传统命令兼容版 21.0，跳过会隐式下载 Android CLI 的新版包装器；与缺失 Java 分别从 Google / Adoptium 官方源补齐，校验归档长度和摘要，在目标同卷 `0700` 私有目录暂存、检查路径与链接，再排他新增独立版本；不覆盖原有版本，不修改系统代理或 Shell 配置。损坏 emulator 仅通过官方管理器重装工具包，保留 AVD 和映像。操作前显示来源与目标，下载显示真实进度；SDK 获取失败后自动持续重试，2～30 秒退避，无次数或总时长上限，保留续传内容和逐次日志，Ctrl+C 立即结束。明确权限、磁盘、版本或许可错误停止并显示阶段、退出码与日志；SDK / Java 准备及安装 / 卸载说明见[功能 README](../README.md)。

`JOBS_SDK_RETRY_DELAY` / `JOBS_SDK_RETRY_MAX_DELAY` 可配置重试初始间隔 / 最大间隔，默认 2 / 30 秒；不设置总次数或总时长上限。当前操作日志保留终端原始详情，相邻的 `.attempts.log` 追加各次获取结果。Ctrl+C / TERM / HUP 停止本轮获取子进程与后续重试，已安装 SDK 和设备保留。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、开发验证</span><!-- jobs-toc:heading-end -->

在工程目录使用 `zsh -n` 检查所有脚本，运行 `ruby ./Tests/InstallerRegistrationTests.rb` 验证安装 / 卸载的精确注册与保留设备数据；传输和 AppDelegate 测试通过 `xcrun swiftc` 隔离编译真实源码与替身，覆盖固定 URL、桌面白名单、路径转义、私有载体清理和重复回调。

运行 `ruby ./Tests/CreateAndroidSimulatorTests.rb`，用假 SDK、Java 与官方下载夹具验证单次首屏授权、`--prepare` 健康 / 多层缺失自动补齐、损坏 emulator 精确重装、Java 校验与重定向边界、安装后复检失败、SDK 同卷发布、已有目标保护、命名冲突与只读入口；测试不会连接真实下载源或操作用户设备。

仅构建、不注册或重启 Finder：

```shell
JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1 xcodebuild \
  -project ./JobsAndroidSimulatorCreator.xcodeproj \
  -scheme JobsAndroidSimulatorCreator \
  -configuration Debug \
  -derivedDataPath ./work/VerificationDerivedData \
  build
```

普通回归使用临时夹具，不安装真实 SDK / 系统映像、不创建设备；真实安装与交互应单独验收。

<a id="🔚" href="#前言">回到首页</a>
