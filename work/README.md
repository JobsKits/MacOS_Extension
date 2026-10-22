# `work` 本机构建目录

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、由谁生成、由谁使用](#sources)
- [二、目录内容](#layout)
- [三、版本控制规则](#git-ignore)
- [四、清理与恢复](#cleanup)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

`work/` 是本仓统一安装脚本的本机构建输出目录，用于集中保存各个 [**Xcode**](https://developer.apple.com/xcode) 工程的 DerivedData：宿主 App、Finder 扩展、编译缓存、索引和构建日志。源码保存在旁边各工程目录中。

**统一安装脚本直接注册这里的 App 和内嵌扩展。正在使用这些扩展时，删除、移动或改名对应构建目录，可能导致右键菜单或宿主调用失效。** 如需清理，先阅读[清理与恢复](#cleanup)。

## 一、<span id="sources">由谁生成、由谁使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 入口 | 与当前目录的关系 |
| --- | --- |
| [统一安装脚本](../【MacOS】🧩安装Finder扩展.command) | 按选中的功能创建 `./<项目名>DerivedData/`，将其传给 `xcodebuild -derivedDataPath`；默认构建 `Debug` 配置，再注册其中的 App 和内嵌扩展。 |
| [统一卸载脚本](../【MacOS】🧩卸载Finder扩展.command) | 当前覆盖十一个宿主，包含 Flutter 版本管理、依赖提取、Git 拉取、Flutter 运行与 iOS 模拟器创建，按选中的功能停用扩展、停止进程、注销注册记录，并删除对应的 `./<项目名>DerivedData/`；不包含 `JobsGitRemoteCopier`。 |
| [复制远程地址专用卸载脚本](../JobsGitRemoteCopier/【MacOS】卸载复制Git远程地址Finder扩展.command/【MacOS】卸载复制Git远程地址Finder扩展.command) | 用于停用、注销 `JobsGitRemoteCopier`；其本地清理路径位于工程内部，不会自动删除当前目录中的 `./JobsGitRemoteCopierDerivedData/`。 |
| [源码与使用说明](../README.md) | 本仓说明安装、卸载和各工程的用途；工程中的源码与工程文件可重新生成构建产物。 |

安装脚本当前使用的路径规则为：

```text
./<项目名>DerivedData/Build/Products/Debug/<项目名>.app
./<项目名>DerivedData/Build/Products/Debug/<项目名>.app/Contents/PlugIns/<扩展名>.appex
```

安装过程直接通过这些路径注册，没有将 App 另行复制到系统应用程序目录。直接从 Xcode 构建时，产物也可能位于 Xcode 自身配置的 DerivedData 位置。

## 二、<span id="layout">目录内容</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

各目录按需生成；新克隆的仓库只有说明文档，安装过的功能才会出现对应构建目录。

```text
./
├── README.md
├── JobsAndroidStudioOpenerDerivedData/
├── JobsFlutterDependencyExtractorDerivedData/
├── JobsFlutterVersionMgrDerivedData/
├── JobsGitPullerDerivedData/
├── JobsGitProxyConfiguratorDerivedData/
├── JobsGitRemoteCopierDerivedData/
├── JobsGitRemoteOpenerDerivedData/
├── JobsIOSSimulatorCreatorDerivedData/
├── JobsPathCopierDerivedData/
├── JobsTerminalOpenerDerivedData/
├── JobsVSCodeOpenerDerivedData/
└── JobsXcodeOpenerDerivedData/
```

| DerivedData 内部条目 | 用途 |
| --- | --- |
| `Build/Products/Debug/` | 构建出的宿主 `.app`、扩展 `.appex` 及其他产物；App 内包含实际注册的扩展。 |
| `Build/Intermediates.noindex/` | 编译中间文件和构建数据库。 |
| `ModuleCache.noindex/`、`SDKExplicitPrecompiledModules/` | 模块与 SDK 预编译缓存。 |
| `Index.noindex/` | 代码索引。 |
| `CompilationCache.noindex/`、`SDKStatCaches.noindex/` | 编译与 SDK 状态缓存。 |
| `Logs/`、`info.plist` | Xcode 构建活动日志及该 DerivedData 的元信息。 |

缓存内容会随 Xcode 版本和实际构建变化，不需要手工创建或逐项维护。统一安装、卸载脚本自己的终端日志位于系统临时目录，分别名为 `【MacOS】🧩安装Finder扩展.log`、`【MacOS】🧩卸载Finder扩展.log`。

## 三、<span id="git-ignore">版本控制规则</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

这些产物体积较大，并与本机 Xcode、SDK、编译环境有关，可由源码重新生成，因此应由 [**Git**](https://git-scm.com/) 忽略。本仓 [`.gitignore`](../.gitignore) 保留文档例外：

```gitignore
/work/*
!/work/README.md
```

即只把 `./README.md` 纳入版本控制，其余本地产物忽略。该规则不会删除磁盘上的已有文件；十二个工程源码由本仓统一版本管理，本目录只保存可再生的本地产物。

## 四、<span id="cleanup">清理与恢复</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 继续使用已安装的 Finder 扩展时，保留对应 DerivedData，尤其是 `Build/Products/Debug/` 内已注册的 App 和扩展。
- 不再使用功能时，除 `JobsGitRemoteCopier` 外，运行[统一卸载脚本](../【MacOS】🧩卸载Finder扩展.command)。脚本先展示影响范围，选择功能后还需回车确认；它会停用、注销所选功能并清理对应构建目录，同时重启 Finder。
- `JobsGitRemoteCopier` 使用[专用卸载脚本](../JobsGitRemoteCopier/【MacOS】卸载复制Git远程地址Finder扩展.command/【MacOS】卸载复制Git远程地址Finder扩展.command)。按回车确认后会停用、注销扩展并重启 Finder；该脚本的本地构建清理目标实际为 `../JobsGitRemoteCopier/work/JobsGitRemoteCopierDerivedData/`，因此本仓中的 `./JobsGitRemoteCopierDerivedData/` 仍会保留。需要回收这部分空间时，先确认扩展已成功注销，再另行清理对应目录。
- 需要恢复时，重新运行[统一安装脚本](../【MacOS】🧩安装Finder扩展.command)，选择相应功能。脚本会重新构建并注册扩展；重新构建需要完整源码及可用的 Xcode 环境。
- 手工误删后菜单失效时，同样重新安装受影响的功能。构建目录可再生，源码应始终保存在工程中，不要把手工修改或需要长期保留的文件放入这里。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
