# JobsFlutterCodegen Scripts

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

本目录包含“Flutter 自动化生产代码”的自包含业务资源及 Xcode 构建后启用入口。功能用途、SDK 规则、安装与卸载见[工程说明](../README.md)。

## <span id="section-1">一、入口与依赖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责与影响 |
| --- | --- |
| [GenerateFlutterCode.zsh](./GenerateFlutterCode.zsh) | 与 SourceTree 对应 Jobs 脚本保持逐字节相同的完整业务实现；运行时不访问 SourceTree。`--check` 不执行 Flutter / Dart，不写日志；实际执行由 Terminal 自述确认后进行。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | Xcode Build Phase 注册并启用 `com.jobs.JobsFlutterCodegen.FinderSyncExtension`，刷新 Finder。手动无构建上下文时停止；`JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过。 |

业务依赖 macOS 自带 zsh 与项目所选 Flutter SDK，Dart 必须来自同一 SDK；缺 SDK 或 FVM 项目链接损坏时停止。不会自动安装全局工具。会修改项目锁文件、依赖元数据及生成文件。默认不执行 `flutter clean`，不主动传入强制删除冲突输出参数；生成器仍会改写其管理的产物，执行前请保存修改。`CLEAN_FIRST=1` 与 `DELETE_CONFLICTING_OUTPUTS=1` 启用时须在终端输入精确大写 `YES` 后才执行；`WATCH=1` 仅在交互终端启用。

## <span id="section-2">二、运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下命令从本 README 所在目录执行：

```shell
/bin/zsh ./GenerateFlutterCode.zsh \
  --check \
  "/路径/Flutter项目"
```

实际执行移除 `--check`；`--help` 可查看参数和环境选项。`--check` 用于只读预检，不代表真实 Flutter / Dart 工具链已经运行通过。

## <span id="section-3">三、日志与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

业务日志位置在实际终端输出中显示，保留每次操作对应记录。构建挂载日志是系统临时目录中的 `JobsFlutterCodegenBuildPhase.log`，待刷新标记为 `JobsFlutterCodegenNeedsFinderRestart`。私有 Terminal 请求目录只包含本次脚本，退出时精确清理。

修改业务脚本时同步 SourceTree 对应脚本及本目录资源，通过总仓 `Tests/FlutterMaintenanceResourceParityTests.rb` 核对一致性；独立携走本工程不要求 SourceTree 存在。原生路径载体和菜单回归只调用假脚本，真实 Flutter 体检或代码生成需在目标设备另行运行。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
