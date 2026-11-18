# 鸿蒙准备工具快照

![Jobs出品，必属精品](https://picsum.photos/1500/400)

> 来源均为当前 OS@Extension 仓库的 Jobs 自维护实现，运行时只读取本目录。

| 文件 | 源实现与用途 |
| --- | --- |
| `./【MacOS】ManageHarmonyFlutterVersion.zsh/【MacOS】ManageHarmonyFlutterVersion.zsh` | MacOS 端 `JobsFlutterTools/Scripts/Tools/`：固定适配版本与提交、隔离缓存、项目级影子绑定、失败恢复；`--prepare-for-run` 供当前运行链自动选正式版。 |
| `./【MacOS】CleanBuildArtifacts.zsh/【MacOS】CleanBuildArtifacts.zsh` | 同目录标准实现；此包仅由 SDK 管理器使用 `--detect` 检测工程，不执行清理。 |
| `./【MacOS】CreateHarmonySimulator.zsh/【MacOS】CreateHarmonySimulator.zsh` | MacOS 端 `JobsHarmonySimulatorCreator/Scripts/`：保留 CLT 固定来源、大小、SHA-256 和官方许可；此包仅使用 `--tools-only`，不获取系统镜像或创建设备。 |
