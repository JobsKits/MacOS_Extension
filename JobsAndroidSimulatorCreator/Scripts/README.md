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
| `CreateAndroidSimulator.zsh` | 检查并自动补齐 SDK 与工具，交互创建 / 启动 Android AVD；`--create` 直接新建，`--prepare` 仅准备工具链，`--check` 只读检查，`--help` 显示参数。与独立双击启动脚本保持相同核心。 |
| `EnableFinderExtension.zsh` | Xcode Build Phase 注册当前构建产物、核对扩展启用路径并按标记刷新 Finder；不创建模拟器。独立安装器会跳过自动注册阶段并统一执行注册。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与风险</span><!-- jobs-toc:heading-end -->

在本目录执行：

```shell
/bin/zsh ./CreateAndroidSimulator.zsh --check
/bin/zsh ./CreateAndroidSimulator.zsh --prepare
/bin/zsh ./CreateAndroidSimulator.zsh
```

首屏回车统一授权本次必要工具链自动补齐；健康依赖不升级，缺失 / 损坏 SDK、Java、命令行工具与 emulator 自动修复一次并复检，不再另设安装确认。没有本地系统映像时自动读取官方清单，选中后直接安装；创建仍由最终确认决定，SDK 许可证保留官方本人交互。`--prepare` 仅准备工具链，`--check` 始终只读；创建消耗磁盘，启动消耗内存和 CPU，不删除或覆盖已有 AVD。

CLT 使用传统命令兼容版 21.0，跳过会隐式下载 Android CLI 的新版包装器；与缺失 Java 分别从 Google / Adoptium 官方源补齐，校验归档长度和摘要，在目标同卷 `0700` 私有目录暂存、检查路径与链接，再排他新增独立版本；不覆盖原有版本，不修改系统代理或 Shell 配置。损坏 emulator 仅通过官方管理器重装工具包，保留 AVD 和映像。操作前显示来源与目标，下载显示进度，失败显示阶段、退出码与日志；SDK / Java 准备及安装 / 卸载说明见[功能 README](../README.md)。

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
