# `MacOS@Extension`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <font id=前言>前言</font>

`MacOS@Extension` 用来收纳 Jobs 本机自用的 [**Swift**](https://www.swift.org/) macOS App + Finder Sync Extension 工程。当前目录下有三个 Finder 右键增强入口：打开 Git 远程地址、复制文件或文件夹绝对路径、用终端打开文件或文件夹所在目录。

## 一、环境先决条件 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 检查项 | 最低要求 | 说明 |
| --- | --- | --- |
| 系统版本 | macOS `12.0` 及以上 | 三个工程的 `MACOSX_DEPLOYMENT_TARGET` 均为 `12.0`，并依赖 macOS 的 Finder Sync Extension 机制。 |
| 开发工具 | [**Xcode**](https://developer.apple.com/xcode) 可正常打开 `.xcodeproj` | 手动运行需要 Xcode；批量安装脚本还需要 `xcodebuild`。首次换机器构建时，按 Xcode 提示完成本机签名配置。 |
| 命令行工具 | `xcodebuild`、`pluginkit`、`pkill`、`killall` 可用 | `xcodebuild` 负责构建 App，`pluginkit` 负责注册和启用 Finder Sync Extension，`pkill pkd` 和 `killall Finder` 用来刷新扩展发现索引与 Finder 菜单缓存。 |
| 批量选择 | 已安装 [**fzf**](https://formulae.brew.sh/formula/fzf) | 只有运行根目录 `./【MacOS】🧩安装Finder扩展.command` 时才需要；可以通过 [**Homebrew**](https://brew.sh/) 安装。 |
| Finder 扩展权限 | 系统设置中允许对应 Finder 扩展 | 构建或安装后，如果右键菜单未出现，先到系统设置的扩展管理里确认对应 Finder 扩展已启用，再重新打开 Finder 窗口。 |
| 功能权限 | 按拓展 README 单独确认 | `JobsTerminalOpener` 需要允许控制 `Terminal.app`；`JobsGitRemoteOpener` 需要读取目标仓库的 `.git/config`；`JobsPathCopier` 主要依赖系统剪贴板。 |

常用自检命令：

```shell
xcode-select -p
xcodebuild -version
pluginkit -m -p com.apple.FinderSync -A -v
fzf --version
```

## 二、工程索引 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 工程 | 入口文案 | 核心用途 | 打开方式 |
| --- | --- | --- | --- |
| `./JobsGitRemoteOpener` | `打开 Git 远程地址` | 右键 Git 仓库文件夹，打开 `remote` 对应网页。 | `./JobsGitRemoteOpener/JobsGitRemoteOpener.xcodeproj` |
| `./JobsPathCopier` | `复制绝对路径` | 右键任意一个本地文件或文件夹，把绝对路径写入剪贴板。 | `./JobsPathCopier/JobsPathCopier.xcodeproj` |
| `./JobsTerminalOpener` | `用终端打开` | 右键任意一个本地文件或文件夹，用 `Terminal.app` 打开目标目录。 | `./JobsTerminalOpener/JobsTerminalOpener.xcodeproj` |

## 三、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

### 3.1、批量选择安装

1. 确认本机已经安装 [**fzf**](https://formulae.brew.sh/formula/fzf)。

   ```shell
   brew install fzf
   ```

2. 双击根目录脚本 `./【MacOS】🧩安装Finder扩展.command`。
3. 脚本打印内置自述后，按回车进入 `fzf` 选择界面。
4. 按 `Tab` 多选需要安装的功能，或选择 `全选｜安装全部 Finder 扩展`。
5. 按 `Enter` 后脚本会调用 `xcodebuild` 构建选中的 App，清理同 Bundle ID 的旧 LaunchServices / PlugInKit 记录，注册并启用 Finder Sync Extension，最后重启 `pkd` 和 Finder 刷新右键菜单缓存。

### 3.2、单工程手动运行

1. 进入目标工程目录。
2. 用 [**Xcode**](https://developer.apple.com/xcode) 打开对应 `.xcodeproj`。
3. 选择同名 Scheme 运行主 App。
4. App 或 Xcode Build Phase 会注册并启用 Finder Sync Extension。
5. 回到 Finder，右键符合条件的文件或文件夹，点击对应一级菜单入口。

## 四、维护边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 每个扩展工程保持独立目录、独立 `.xcodeproj`、独立 Bundle ID 和独立卸载脚本。
- Finder Sync Extension 菜单位置由 macOS 决定，本目录只保证扩展注册、启用和菜单动作逻辑。
- 如果 `pluginkit` 显示扩展前缀为 `+`，但 Finder 右键菜单仍缺少对应入口，优先重新运行根目录安装脚本；脚本会清理旧会话、旧 DerivedData 或散落 appex 留下的同 Bundle ID 注册记录。
- 新增同类工程时优先沿用 `JobsGitRemoteOpener` 的主 App 注册流程、Build Phase 启用脚本和 README 结构。
- 根目录只做工程索引；每个工程的具体使用、排查和卸载说明写在各自 `README.md`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
