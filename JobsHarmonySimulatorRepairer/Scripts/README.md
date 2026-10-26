# `Scripts`：Harmony 模拟器检测与修复

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

本目录保存[Harmony 模拟器检测与修复](../README.md)的自包含核心及 [**Finder Sync**](https://developer.apple.com/documentation/findersync) 构建后启用脚本。安装 / 卸载入口与功能包 README 平级。

## 一、<span id="files">文件职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| [RepairHarmonySimulator.zsh](./RepairHarmonySimulator.zsh) | `--check` 只读诊断；交互启动、保留数据 coldboot、完整备份后修复失效 SDK 路径。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | Xcode Build Phase 的本包注册、启用与 Finder 刷新；隔离构建设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过系统注册。 |

## 二、<span id="usage">运行与产物</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录只读诊断：

```shell
/bin/zsh ./RepairHarmonySimulator.zsh \
  --check
```

去掉 `--check` 进入交互；先回车授权诊断，再选固定动作。冷启动与 SDK 路径修复需精确 `YES`；取消、无交互和异常状态不继续动作。需要 Apple Silicon 原生 macOS、已有官方 DevEco Emulator 和同一工具内的 SDK；工具缺失仅报告，不下载或改代理。

交互日志位于系统临时目录 `JobsHarmonySimulatorRepairer.XXXXXX/RepairHarmonySimulator.log`，只读不创建本工具日志。SDK 完整备份在实例父目录的 `.<名称>.jobs-repair-backup.XXXXXX/instance/`；不自动删除，不清空 userdata。核心作为普通资源随 App 打包，不回读仓库或兄弟功能目录。

`EnableFinderExtension.zsh` 的日志为系统临时目录 `JobsHarmonySimulatorRepairerBuildPhase.log`，只在有构建上下文时启用本包。隔离验证不运行真实安装 / 刷新；详细动作、超时、恢复方式与官方来源见[功能包说明](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
