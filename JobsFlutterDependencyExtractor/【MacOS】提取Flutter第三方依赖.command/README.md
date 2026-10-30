# 提取 Flutter 第三方依赖

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、目录与运行](#jobs-toc-heading-2)
- [二、输出与范围](#jobs-toc-heading-3)
- [三、日志与排查](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

双击同目录的 [【MacOS】提取Flutter第三方依赖.command](./【MacOS】提取Flutter第三方依赖.command)，输入或拖入 [**Flutter**](https://flutter.dev/) 项目文件夹，再选择输出父目录。**目标直接回车使用系统桌面**。无需先安装 Finder 扩展，整个文件夹可以整体复制到其它 Mac 使用。

| 输入或情况 | 实际结果 |
| --- | --- |
| 自述处直接回车 | 继续；任意非空输入或 EOF 取消。 |
| 输入或拖入项目目录 | 只处理该目录自身，不递归查找工程。 |
| 目标处直接回车 | 使用系统解析的桌面，兼容桌面重定向。 |
| 输入或拖入目标目录 | 新建独立输出目录；支持中文、空格、Terminal 拖入转义。 |
| 重复提取同一项目 | 每次产生不同名称，不覆盖旧结果。 |
| 缓存缺失、版本不匹配、解析过期 | 停止并提示先执行 `flutter pub get`；不会自动下载或更新依赖。 |

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、目录与运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
【MacOS】提取Flutter第三方依赖.command/
├── 【MacOS】提取Flutter第三方依赖.command
├── ExtractFlutterDependencies.dart
└── README.md
```

要求 macOS、自带的 `/bin/zsh` 和健康的 [**Dart**](https://dart.dev/) SDK。脚本依次查找项目 FVM SDK、PATH 中 Dart / Flutter 对应的原生 Dart、常见的已安装 SDK；只做版本体检，不安装工具、不改 Shell 或代理设置。保留同目录 `.dart` 引擎，不能只复制 `.command` 文件。

也可在本目录执行，预先带入项目参数：

```shell
/bin/zsh ./【MacOS】提取Flutter第三方依赖.command \
  '/实际/Flutter 项目'
```

1、先阅读内置自述，按回车继续；按 `Ctrl+C` 随时取消。

2、未传参数时，输入或拖入 Flutter 项目目录。

3、输入或拖入目标父目录，或者直接回车选桌面；新目标目录可以不存在。目标不能放在源项目或任一待提取依赖包内部。

4、等待逐包显示来源、版本和目标，查看完成路径与日志。失败会给出原因，不把部分复制显示为完整成功。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、输出与范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

```text
FlutterDependencies-项目名-UTC时间-随机标识/
├── packages/
│   └── 包名/                 # 原始源码、资源、插件平台源码和许可证
├── manifest.json             # 名称、版本、来源类别、依赖层级、本地原路径、文件数量
├── pubspec.yaml              # 项目原始声明
├── pubspec.lock              # 实际使用的原始锁文件
└── README.md
```

- 基于 `pubspec.lock` 和 `.dart_tool/package_config.json` 交叉核对本地真实路径，覆盖 hosted、Git、path，包含直接、间接和开发依赖。Workspace 使用共享解析文件，必须由祖先或嵌套 workspace 声明成员关系，只导出选中项目依赖闭包；内部成员以 `workspace` 标记。成员列表支持标准块列表、单行 flow 列表和相对路径模式 `*`、`**`、`?`。
- Flutter / Dart SDK 包排除。包内 iOS / Android / macOS / Windows 原生源码会保留；CocoaPods、Gradle、Maven 另外下载的库、框架和二进制缓存不属于 Pub 源码提取范围。
- 忽略 `.git`、`.dart_tool`、`node_modules`、`Pods`、`.fvm`、`build`、`DerivedData`、`.gradle`、`.idea`、`.symlinks`。包内有效符号链接物化为普通文件；失效、包外、循环及指向排除目录的链接跳过，终端及 `manifest.json` 的 `warnings` 记录具体路径与原因。真实包根、普通源码读取 / 复制失败及特殊文件仍明确停止。
- 输出是源码归档，不重写依赖地址或生成离线构建配置；不能把源码归档当作跨机器完整构建环境。
- 读取项目和包缓存，不修改源文件。复制完整后才将隐藏临时目录改名为正式输出；中途失败可能保留 `.FlutterDependencies-…incomplete-…` 隐藏目录，终端会显示其准确位置。
- 原始声明、锁文件及包源码可能包含私有地址、本地路径；分享前自行检查，并遵守各包原许可证。

Pub 的解析与缓存机制见 [Dart pub get](https://dart.dev/tools/pub/cmd/pub-get)；共享解析行为见 [Pub workspaces](https://dart.dev/tools/pub/workspaces)。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、日志与排查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

日志在自述确认后，以私有权限创建于系统临时目录 `${TMPDIR:-/tmp/}`，普通文件名称为 `JobsFlutterDependencyExtractor.随机标识`，准确路径显示在终端。日志同步保存逐包本地来源、目标、失败原因与最终结果，不展开远端认证 URL。

| 问题 | 处理 |
| --- | --- |
| 缺少 `.dart` 引擎 | 重新整体复制本文件夹。 |
| 找不到健康 Dart | 先正常安装 / 修复 Flutter 或 Dart，检查项目 FVM SDK 或 PATH 后重试。 |
| 缺少解析文件或解析过期 | 在项目正常执行 `flutter pub get`，完成后重新提取。 |
| 版本 / 路径不匹配 | 停止后台依赖操作，重新解析项目，避免使用别的机器遗留的 `.dart_tool`。 |
| Workspace 成员不在声明范围 | 核对祖先及嵌套 workspace 的成员路径列表，在正确 workspace 根重新解析；不能仅凭 `resolution: workspace` 借用任意祖先解析文件。 |
| YAML anchor / tag 或跨行 flow 映射 | 使用 Pub 标准块映射；不猜测复杂 YAML 的依赖语义。 |
| 输出权限或磁盘空间不足 | 改选可写目录、留足空间；此前结果保留。 |
| 桌面隐私权限阻止写入 | 在系统设置允许 Terminal 访问桌面，或手动指定可写目录。 |

引擎与交互均经过临时项目验证，交互回归入口为完整工程的 `Tests/ExtractionShellTests.rb`。该三件套可独立运行，不注册右键菜单；需要 Finder 菜单时，另用完整 `JobsFlutterDependencyExtractor` 工程的独立安装入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
