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

> 本目录携带可独立运行的 Android 模拟器核心与 Finder 注册辅助脚本，不依赖其它仓库的运行时文件。

| 文件 | 职责与边界 |
| --- | --- |
| `CreateAndroidSimulator.zsh` | 检查 SDK 与工具，交互创建 / 启动 Android AVD；`--create` 直接新建，`--check` 只读检查，`--help` 显示参数。与独立双击启动脚本保持相同核心。 |
| `EnableFinderExtension.zsh` | Xcode Build Phase 注册当前构建产物、核对扩展启用路径并按标记刷新 Finder；不创建模拟器。独立安装器会跳过自动注册阶段并统一执行注册。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与风险</span><!-- jobs-toc:heading-end -->

在本目录执行：

```shell
/bin/zsh ./CreateAndroidSimulator.zsh --check
/bin/zsh ./CreateAndroidSimulator.zsh
```

交互流程在创建及工具 / 组件安装前确认；创建消耗磁盘，启动消耗内存和 CPU；不删除、覆盖已有 AVD，不自动接受 SDK 许可证。缺失命令行工具可从官方源补齐，先核对归档长度与摘要，再在 SDK 同卷私有目录暂存并新增独立版本；保留全部原有版本，完成后重新体检。源与目标在操作前显示，失败输出原因与日志。SDK / Java 准备及安装 / 卸载说明见[功能 README](../README.md)。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、开发验证</span><!-- jobs-toc:heading-end -->

在工程目录使用 `zsh -n` 检查所有脚本，运行 `ruby ./Tests/InstallerRegistrationTests.rb` 验证安装 / 卸载的精确注册与保留设备数据；传输和 AppDelegate 测试通过 `xcrun swiftc` 隔离编译真实源码与替身，覆盖固定 URL、桌面白名单、路径转义、私有载体清理和重复回调。

运行 `ruby ./Tests/CreateAndroidSimulatorTests.rb`，用假 SDK、Java 与官方下载夹具验证健康复用、缺失及损坏分支、安装后复检失败、SDK 同卷发布、已有目标保护、命名冲突与只读入口；测试不会连接真实下载源或操作用户设备。

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
