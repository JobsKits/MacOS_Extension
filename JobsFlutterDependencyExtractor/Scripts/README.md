# Flutter 依赖提取脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、脚本职责](#jobs-toc-heading-2)
- [二、运行与风险](#jobs-toc-heading-3)
- [三、构建注册边界](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

> 本目录承接 [**Flutter**](https://flutter.dev/) 第三方依赖归档与 Finder 扩展构建后的注册，完整行为见 [工程说明](../README.md)。

提取范围默认私库候选：回车只取 Git、path、自建 hosted 包，任意非空输入（含空格）才收集全部已解析 Pub 包。完成后回车默认打包 ZIP，非空不打包；ZIP 校验成功后回车保留原目录，非空删除本次提取目录。私库权限不能仅凭 Git 来源证明；平台私库制品与原始缓存迁移使用[统一一键迁移](../../JobsFlutterTools/README.md#one-click-migration)。


**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，默认 `build`。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。默认不清理；UI 仅在应用程序安装模式显示清理选项，退出该组合就清空。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、脚本职责 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 文件 | 用途 |
| --- | --- |
| `ExtractFlutterDependencies.zsh` | 交互入口，项目校验、Dart 发现、目标路径输入 / 拖入，回车默认系统桌面 |
| `ExtractFlutterDependencies.dart` | 基于锁文件与包配置复制本地已解析依赖、输出清单和许可证 |
| `EnableFinderExtension.zsh` | Xcode Build Phase 注册并启用固定 Finder 扩展，可由开关跳过 |

```text
Scripts/
├── ExtractFlutterDependencies.zsh
├── ExtractFlutterDependencies.dart
├── EnableFinderExtension.zsh
└── README.md
```

两份提取资源必须同目录。Finder 宿主会复制到本次私有请求目录，在 Terminal 中调用外层 zsh 脚本，业务结束后精确删除本次私有副本。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行与风险 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

独立使用可运行：

```shell
/bin/zsh ./ExtractFlutterDependencies.zsh \
  '/实际 Flutter 项目路径'
```

入口先显示内置自述并等待确认，再收集输出父目录；直接回车默认桌面。`Ctrl+C` 取消，不会自动运行 `pub get` 或安装工具。缺少 Dart、本地解析记录或依赖源码时明确停止。

提取需要 macOS 自带 `/bin/zsh`、健康的 [**Dart**](https://dart.dev) SDK 及已有本地解析记录。入口只运行已安装 SDK 的原生 Dart，避免通过 shim 隐式下载工具；工程路径和拖入的转义路径作为数据传递。自述直接回车继续，任意非空输入或 EOF 取消。

提取产物包含 `packages/`、原始锁文件、配置和 `manifest.json`，其中可能有本地路径或私有仓库地址，分享前检查。提取业务日志是 `${TMPDIR:-/tmp/}JobsFlutterDependencyExtractor.随机标识` 私有普通文件，准确位置在自述确认后的首屏显示；宿主与安装日志分别见 [工程日志说明](../README.md)。

普通项目包含直接、间接与开发依赖；workspace 核验声明成员关系，只取所选成员依赖闭包。支持标准块列表、单行 flow 列表、相对 `*` / `**` / `?` 模式及嵌套 workspace；未知复杂 YAML 明确停止。包内有效符号链接物化复制；失效、包外、循环及指向排除目录的链接跳过并记录 `warnings`，特殊文件、真实包根及普通源码读取错误仍失败。输出是源码归档，未包含平台包管理器缓存，也不保证离线构建。

归档排除 `.plugin_symlinks` 及 `linux/flutter/ephemeral`、`windows/flutter/ephemeral`、`macos/Flutter/ephemeral`，包括嵌套 example 中的相同路径；这些目录可能保留其他开发机器的失效链接，须在解析链接前排除。普通源码中名为 `ephemeral` 的目录仍保留；非生成目录中的失效 / 包外 / 循环链接也只告警跳过，真实普通文件读取或复制失败仍停止。清单的 `excludedDirectories`、`excludedGeneratedDirectorySuffixes` 记录排除规则；`excludedRelativePaths` 保留为后者的等值兼容别名，逐项跳过原因在 `warnings`。

交互回归入口为 `../Tests/ExtractionShellTests.rb`；从工程根执行 `ruby ./Tests/ExtractionShellTests.rb`。引擎回归执行 `dart ./Tests/DependencyExtractionTests.dart`，均使用临时项目，不运行真实安装或注册。引擎也可作为首个参数指定，便于复核统一菜单中的副本。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、构建注册边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

`EnableFinderExtension.zsh` 在真实 Xcode Build Phase 中自动注册 `com.jobs.JobsFlutterDependencyExtractor.FinderSync`，正常启用后可能重启 Finder。普通验证须设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1`；外层独立安装器也设置此开关，避免重复注册。不要把直接运行该脚本作为语法测试。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
