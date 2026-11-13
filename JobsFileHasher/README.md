# JobsFileHasher 文件指纹

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、使用与边界](#use)
- [二、安装与卸载](#manage)
- [三、工程结构与验证](#structure)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

在 [**MacOS**](https://www.apple.com/macos/) 的 [**Finder**](https://support.apple.com/guide/mac-help/welcome/mac) 中选中一个普通文件，右键点击 **“🔎 查看文件指纹 Hash（SHA-256）”**：新开的 Terminal 窗口显示文件路径和 SHA-256，完成后自动将 **64 位小写十六进制纯摘要**复制到系统剪贴板，不带路径或换行。

例如内容恰好为 `abc` 的文件（无结尾换行）：

```text
SHA-256：
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad

✔ 纯 SHA-256 已复制到系统剪贴板。
```

功能 ID 为 `file-hash`，独立宿主 `JobsFileHasher.app`、扩展 `com.jobs.filehasher.findersync`。可单独安装 / 卸载，或从 [平台总面板](../README.md)选择本项；不依赖其它功能工程。

## 一、<span id="use">使用与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 仅文件选中菜单支持一个普通文件；不限制扩展名、文件内容或大小。多选、目录、App 包、符号链接、FIFO 和设备不显示本项；目录背景菜单不显示。
- 新终端先展示只读用途和剪贴板覆盖说明，然后计算摘要。大文件分块读取，内存不随文件大小增长；计算期间可按 `Ctrl+C` 取消。文件自身不会被执行，不修改内容、可执行位或隔离属性。
- 菜单生成、点击、URL 接收和实际读取都复核文件。实际读取以不跟随末级链接的描述符打开；结束前复核 inode、大小和修改时间等状态。文件消失、不可读、被替换或计算期间变化时报告失败，未成功完成读取前不写剪贴板。
- 路径以转义形式显示，中文、空格、引号、换行及 Shell 特殊字符按字面传输。Terminal 接收一行安全启动命令，每次独占的临时载体采用目录 `700` / 文件 `600`，业务结束或取消后清理本次载体；不扫描或清理其它会话。
- 成功覆盖当前系统剪贴板。写入失败保留终端中的摘要并返回失败，不假报复制成功。系统首次询问自动化权限时，允许本工具控制 Terminal；拒绝时显示错误，可在系统设置中调整后重试。受保护文件仍遵守系统访问权限，不使用 sudo 或修改 TCC。
- SHA-256 用于文件内容一致性校验；与别人提供的摘要比较时应核对可信来源。本入口不联网、不上传文件。

## 二、<span id="manage">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

双击 [管理入口](./【MacOS】管理文件指纹Finder扩展.command)或同名 App。面板默认空选，在 GUI 中选择本项并点击“安装 / 更新”或“卸载”；空选、关闭或取消不操作系统。完整仓中进入限定 `file-hash` 的总面板，整体复制本文件夹后使用随包面板。具体参数见 [脚本说明](./Scripts/README.md)。

```shell
/bin/zsh ./【MacOS】管理文件指纹Finder扩展.command
```

需要 MacOS 12 或以上、完整 [**Xcode**](https://developer.apple.com/xcode/) 和 MacOS SDK。摘要使用系统 [**CryptoKit**](https://developer.apple.com/documentation/cryptokit)，剪贴板使用系统 `pbcopy`；不额外安装第三方解释器或命令行工具。

- 默认从 `work/DerivedData/Build/Products/Debug/JobsFileHasher.app` 登记运行，须保留该构建产物。
- 勾选“使用「应用程序」文件夹安装 / 卸载”后，完整功能模块安装到 `/Applications/Jobs自定义右键菜单.app` 内，再从该位置登记；不会依赖源码仓绝对路径。
- 安装核对宿主、扩展 Bundle ID、完整签名和精确登记路径，未启用时不报告成功。切换位置保留另一位置文件，卸载仅处理本次所选位置并保留全部用户文件、源码和其它功能。
- 应用程序路线支持默认关闭的安装后构建清理和独立清理按钮；需核验已安装运行副本后才清理本功能明确的构建根。App 管理权限由用户在系统设置中授权，不以全程提权绕过。
- 安装日志可在面板中查看和复制，同时位于系统临时目录 `JobsFileHasherManage.log`。安装停止请求等待本次完整 App 事务结束；不强杀编译、签名或登记。

管理面板复用平台现有的白天 / 黑夜 / 跟随系统主题及当前语言设置；具体可选语言以平台面板为准。本功能不新增自定义图形业务窗口。

## 三、<span id="structure">工程结构与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 目录 | 职责 |
| --- | --- |
| `JobsFileHasher/` | URL 宿主、新终端调度、分块摘要、终端只读入口和剪贴板写入 |
| `JobsFileHasherFinderSync/` | 单文件菜单、点击请求保存与精确宿主投递 |
| `Shared/` | 普通文件验证、请求编码、宿主身份核对和本地系统 API 工厂 |
| `JobsFileHasher.xcodeproj/` | 独立宿主 / 扩展与共享 Scheme，无安装登记 Build Phase |
| `Scripts/` | 随包管理面板、安装 / 卸载与位置事务 |
| `Tests/` | [文件指纹隔离验证](./Tests/FileHashTests.rb/README.md) |

```shell
/bin/zsh ./Scripts/ManageExtension.zsh --help
ruby ./Tests/FileHashTests.rb/FileHashTests.rb
```

隔离验证覆盖空文件、标准 SHA-256、多块二进制、特殊路径、单文件边界、失败不触碰剪贴板、URL 校验、私有载体清理和复制改名后的管理范围；宿主 / 扩展类型检查及工程属性检查通过。临时 DerivedData 中的 Debug 构建产出包含 arm64 / x86_64 的完整宿主和内嵌扩展，Bundle ID、扩展主类及 ad-hoc 深度严格签名验证通过。构建器自动生成的 LaunchServices / PlugInKit 临时路径记录已精确清理并复核恢复为构建前无本功能登记的状态；未启动宿主、未启用 Finder 扩展、未运行 Terminal 或写系统剪贴板。真实右键交互和自动化授权仍需安装后单独验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
