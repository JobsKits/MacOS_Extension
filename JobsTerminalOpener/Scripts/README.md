# <span id="前言">Terminal 扩展支持脚本</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、脚本职责](#files)
- [二、产物清理](#clean)
- [三、验证与日志](#verify)

</details>
<!-- jobs-toc:end -->

---

本目录提供原生工程产物清理和构建后的扩展注册支持。菜单与安装入口见[工程说明](../README.md)。清理核心也自包含打包到 [Flutter 统一工具](../../JobsFlutterTools/README.md)，Flutter 根目录只从统一子菜单进入。

## 一、<span id="files">脚本职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 用途与边界 |
| --- | --- |
| [CleanBuildArtifacts.zsh](./CleanBuildArtifacts.zsh) | 识别当前 Flutter、鸿蒙、Android、iOS/Xcode 工程，仅删除白名单构建产物。系统 zsh、Perl 和 macOS 原生工具即可运行；不要求安装对应 SDK，不执行工程脚本。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | 由 Xcode Build Phase 提供构建环境后调用，停止旧宿主和扩展进程、注册当前 App/appex、请求启用并刷新 Finder。外层安装器设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 时跳过，由调用方接管登记；无需手动执行。 |

## 二、<span id="clean">产物清理</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录执行，路径替换为实际工程；以下命令只预览，不删除：

```shell
/bin/zsh ./CleanBuildArtifacts.zsh \
  "/实际工程路径" \
  --dry-run
```

`--detect` 只输出工程类型；不传选项时先展示路径，精确输入 `CLEAN` 才删除，回车取消，输入结束停止。`--yes` 只供已明确授权的无人值守调用。请先停止构建。清单解析支持常见块映射、单行 flow 与引号；拒绝重复依赖键、损坏或超限清单，Flutter 声明不依赖 `lib/` 是否已创建。

保留源码、锁文件、Pods、FVM SDK、签名、共享缓存和其它工程产物；自定义输出不推断。具体平台白名单和符号链接保护见[清理范围](../README.md#build-artifacts)。与 `../../JobsFlutterTools/Scripts/Tools/CleanBuildArtifacts.zsh` 保持逐字节一致。

## 三、<span id="verify">验证与日志</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录运行隔离回归，测试只处理临时夹具：

```shell
ruby ../Tests/BuildArtifactCleanerTests.rb
```

清理结果显示在当前终端；脚本不单独写日志。由宿主创建的私有请求载体在退出时清理。扩展注册日志在系统临时目录的 `JobsTerminalOpenerBuildPhase.log`，待刷新标记为 `JobsTerminalOpenerNeedsFinderRestart`；注册阶段返回成功不能代替精确路径启用及真实菜单验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
