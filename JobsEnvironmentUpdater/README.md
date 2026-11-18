# JobsEnvironmentUpdater

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、行为与确认](#jobs-toc-heading-2)
- [二、管理与交付](#jobs-toc-heading-3)
- [三、构建与验证](#jobs-toc-heading-4)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

桌面空白右键提供 **🔄 更新开发环境（update）**。独立功能 ID 为 `environment-update`，通过本目录的[管理入口](./【MacOS】管理开发环境更新Finder扩展.command)或同名 [App](./【MacOS】管理开发环境更新Finder扩展.app)安装／更新及卸载；同时接入上级[总管理面板](../【MacOS】🧩管理Finder扩展.command)。本项仅适用于用户指定的 [**MacOS**](https://www.apple.com/macos/)。

**可运行成品：** [JobsEnvironmentUpdater.app](./work/TerminalSingleWindow-20261118/Build/Products/Debug/JobsEnvironmentUpdater.app) 包含双架构宿主、FinderSync 与业务资源；源码、安装及真实菜单验收分别见[资产盘点](../../项目相关报告/update桌面菜单资产盘点.md)。

**固定顺序背景菜单：** 应用程序中的联合 App 通过包内 `Contents/Resources/DesktopMenu.json` 指定唯一展示扩展，依次生成“新建文件 → 新建 iOS / Android / Harmony 模拟器 → Android / Harmony 模拟器检测与修复 → 显示 / 隐藏文件 → 更新开发环境（update）→ 磁盘剩余”；只显示已安装且适用的项目。各功能独立宿主、叶开关和安装 / 卸载边界保留。普通文件夹背景按同一顺序显示新建文件、文件显示开关和磁盘剩余。跨模块固定顺序需要将这四个模块均更新到支持清单的版本；独立构建目录路线继续使用原菜单。系统手动停用当前展示扩展会暂时隐藏整组背景菜单，重新启用或从面板安装 / 更新可恢复；从管理面板卸载模块时自动重选展示扩展。损坏清单、身份变化及过期点击不会派发业务。详见[右键菜单顺序资产盘点](../../项目相关报告/右键菜单顺序资产盘点.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、行为与确认 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 仅在系统桌面的空白菜单展示；普通目录、文件或选中项不提供该动作。
- Finder 观察根目录以接收桌面事件，再用桌面白名单过滤菜单；观察范围不会把更新入口显示到普通目录，也不增加全盘读取权限。每个插件进程仅在自身系统临时目录保留最近一次初始化／菜单回调状态，文件名为 `JobsEnvironmentUpdater-menu-进程号.log`，不记录文件名或目录内容。
- 点击后由精确宿主打开一个独立 [**Terminal**](https://support.apple.com/guide/terminal/welcome/mac) 执行窗口，先 `launch` 启动而不发送开窗事件，再提交 `do script`，最后激活 Terminal，避免无窗口时额外打开空白窗口，不占用已有终端会话。无参数运行随包完整 `update`，与终端直接输入 `update` 一样默认低打扰。显示自述后自动按顺序维护，不等待回车或逐项确认；`-t`、`--trust`、`--unattended` 不再接受，只保留 `-h`／`--help`。
- 启动时复用已有管理员授权；缺少授权且终端可交互时，可能调用一次 `sudo -v` 要求系统密码，本轮每 45 秒保活，后续提权命令使用 `sudo -n`。不保存密码、不改 `sudoers`；缺少授权时记录未完成并继续其它项目。
- 普通子命令以输入结束运行，已知确认点沿用定点自动回答；需要额外认证或未知输入时报告未完成，不等待手工填写，也不自动打开下载页面。单项失败后继续，收尾直接汇总并退出，未完成时返回非零；需要再试时重新执行 `update`，`Ctrl+C` 可中止本轮。
- 支持原 `update` 的系统、Homebrew、Ruby、CocoaPods、全局 Flutter 等维护流程，保留项目 FVM SDK、选路、失败统计、日志及既有命令内部网络重试。业务实现来自 `JobsMacEnvVarConfigs/scripts/【MacOS】update.command`，随包副本及五组 `_lib` 资源独立维护，运行不依赖原仓库；两份脚本遵循同一默认交互约定，保留各自已有业务差异。
- 终端主日志仍为 `$TMPDIR/update.log`。每次请求先创建权限 `0700` 的私有资源快照，结束后删除快照，日志按原脚本保留；宿主后续更新或卸载不会截断本轮已打开的更新终端。
- 仅对子脚本设置 `LC_ALL=en_US.UTF-8` 以保留中文路径，清除 `JOBS_MAC_ENV_SOURCE_MODE` 和 `JOBS_MAC_ENV_SKIP_README`，不修改用户全局语言或Shell配置。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、管理与交付 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

管理面板默认空选，支持安装／更新和卸载、白天／黑夜／跟随系统、十种语言及跟随系统；沿用已有日志、关闭后台、权限及精确安装登记核验。安装本功能只部署本单元，不运行 `update`；点击菜单才开始默认低打扰维护。

| 交付项 | 位置 |
| --- | --- |
| 完整工程 | [JobsEnvironmentUpdater.xcodeproj](./JobsEnvironmentUpdater.xcodeproj) |
| Finder 菜单 | [FinderSync.swift](./JobsEnvironmentUpdaterFinderSync/FinderSync.swift) |
| 请求、上下文、宿主定位 | `Shared/EnvironmentUpdate*.swift` |
| Terminal 快照与启动 | [EnvironmentUpdateTerminalLauncher.swift](./JobsEnvironmentUpdater/EnvironmentUpdateTerminalLauncher.swift) |
| 管理后台和资源 | [Scripts](./Scripts/README.md) |
| 可运行成品 | `work/DerivedData/Build/Products/Debug/JobsEnvironmentUpdater.app`（含 FinderSync 插件及全部业务资源） |
| 验证与限制 | [Tests](./Tests/README.md)及[资产盘点](../../项目相关报告/update桌面菜单资产盘点.md) |

整体搬迁须保留工程、`Scripts/`、独立 `.command` 与同名 `.app`；启动器从自身位置定位资源，不依赖启动工作目录。本次源码和构建不等于本机已安装或菜单已人工验收。

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、构建与验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

要求完整 [**Xcode**](https://developer.apple.com/xcode/) 及 MacOS 12+。从本目录构建：

```zsh
xcodebuild -project JobsEnvironmentUpdater.xcodeproj \
  -scheme JobsEnvironmentUpdater -configuration Debug \
  -derivedDataPath work/DerivedData \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  build
codesign --verify --deep --strict \
  work/DerivedData/Build/Products/Debug/JobsEnvironmentUpdater.app
```

Xcode 的 Mac App 构建可能自动登记构建路径。开发验证结束后，只对本次构建路径精确注销，避免把开发产物当成正式安装；不要全局重置登记库：

```zsh
/usr/bin/pluginkit -r \
  "$PWD/work/DerivedData/Build/Products/Debug/JobsEnvironmentUpdater.app/Contents/PlugIns/JobsEnvironmentUpdaterFinderSync.appex"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -u "$PWD/work/DerivedData/Build/Products/Debug/JobsEnvironmentUpdater.app"
```

桌面菜单此前已定向更新到应用程序联合 App，原有 13 模块保留，内外签名及资源核验通过；实际 Finder 桌面菜单回调命中，用户已确认“已经出现”。默认低打扰行为的源码、隔离验证及成品同步状态见[资产盘点](../../项目相关报告/update桌面菜单资产盘点.md)；此前菜单显示记录不代表当前更新流程已完成真实升级验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
