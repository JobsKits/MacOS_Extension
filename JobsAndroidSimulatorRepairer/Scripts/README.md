# `Scripts`：Android 模拟器检测与修复

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#files)
- [二、运行与产物](#usage)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录保存[Android 模拟器检测与修复](../README.md)的自包含核心及 [**Finder Sync**](https://developer.apple.com/documentation/findersync) 构建后启用脚本；安装 / 卸载入口与功能包 README 平级。

## 一、<span id="files">文件职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| [RepairAndroidSimulator.zsh](./RepairAndroidSimulator.zsh) | 独立交互修复及 `--check` 诊断；已有 SDK 发现、模拟器筛选、安装位置、空间、缓存重置、精确卸载与完整备份后容量调整。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | Xcode Build Phase 的本功能注册、启用与刷新；不是模拟器修复入口。隔离构建设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过注册。 |

## 二、<span id="usage">运行与产物</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行只读诊断：

```shell
/bin/zsh ./RepairAndroidSimulator.zsh \
  --check
```

去掉 `--check` 进入可交互修复，先阅读自述并回车；危险操作输入精确 `YES`。卸载会删除对应应用数据；工具缺失、设备不可信或容量安全条件不满足时停止，不自动安装 SDK，不执行 Wipe Data。

修复日志在系统临时目录的 `JobsAndroidSimulatorRepairer-*.log`，只读不创建日志；完整 AVD 备份位于所选 AVD 根的 `.<名称>.repair-backup.XXXXXX/`，不会自动删除。容量是否生效以实际 `/data` 复测为准；参数、依赖、安装与恢复见[功能包说明](../README.md)。

核心以普通资源打入 App，运行不回读仓库。`EnableFinderExtension.zsh` 的构建日志为系统临时目录的 `JobsAndroidSimulatorRepairerBuildPhase.log`；直接手工运行且缺少 Xcode 上下文时拒绝修改系统。实际启用会刷新 Finder，隔离验证必须显式跳过，不以构建通过代替菜单实机验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
