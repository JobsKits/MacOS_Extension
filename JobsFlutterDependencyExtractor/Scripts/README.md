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

> 本目录承接 [**Flutter**](https://flutter.dev/) 第三方依赖归档与 Finder 扩展构建后的注册，完整行为见 [工程说明](../README.md)。

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

普通项目包含直接、间接与开发依赖；workspace 核验声明成员关系，只取所选成员依赖闭包。支持标准块列表、单行 flow 列表、相对 `*` / `**` / `?` 模式及嵌套 workspace；未知复杂 YAML 明确停止。包内符号链接物化复制，包外 / 循环链接及特殊文件拒绝。输出是源码归档，未包含平台包管理器缓存，也不保证离线构建。

交互回归入口为 `../Tests/ExtractionShellTests.rb`；从工程根执行 `ruby ./Tests/ExtractionShellTests.rb`。引擎回归执行 `dart ./Tests/DependencyExtractionTests.dart`，均使用临时项目，不运行真实安装或注册。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、构建注册边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

`EnableFinderExtension.zsh` 在真实 Xcode Build Phase 中自动注册 `com.jobs.JobsFlutterDependencyExtractor.FinderSync`，正常启用后可能重启 Finder。普通验证须设置 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1`；外层独立安装器也设置此开关，避免重复注册。不要把直接运行该脚本作为语法测试。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
