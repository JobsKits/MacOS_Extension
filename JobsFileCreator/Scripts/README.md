# JobsFileCreator 管理脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#files)
- [二、内部参数与边界](#options)
- [三、只读检查](#verification)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录负责“📃 新建文件…”功能的 GUI 启动和后台安装 / 卸载。用户入口为上级 [管理脚本](../【MacOS】管理新建文件Finder扩展.command)及同名 App；实际文件创建由 Swift 宿主处理，这些脚本不创建用户业务文件。

## 一、<span id="files">文件职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 文件 | 职责 |
| --- | --- |
| `ManageExtension.zsh` | 解析当前一项功能范围，打开 GUI 或处理面板已确认的操作；构建、核对签名和身份、注册 / 停用及精确注销 |
| `FinderManagerGUI.zsh` | 随包 GUI 支持库，后台编译缓存并运行原生管理面板，不直接安装扩展 |
| `ManagementPanel.swift` | 随包单功能面板；默认空选、安装 / 卸载操作、逐项状态、总进度百分比、安装 / 卸载独立计时、实时可复制日志 |

完整仓中 `ManageExtension.zsh` 优先转交总管理器并限定 `file-create`。独立复制本包后使用随包面板；公开 App / `.command` 不接受跳过 GUI 的后台开关。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中和执行中不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。切换操作会显示该操作已有的耗时。

日志区上方的分隔条可上下拖动，窗口也可调整大小；功能列表与日志分别滚动，并保留操作按钮。日志右键提供“全选”，也可用 `⌘A` 全选后 `⌘C` 复制；拖动不会清空日志或改变功能勾选。

## 二、<span id="options">内部参数与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

后台仅由 GUI 或总管理器在完成确认后调用。`--non-interactive` 必须同时显式提供 `--action`，功能范围只允许 `file-create`；未知操作、未知 ID、额外参数在系统写入前拒绝。

| 参数 | 默认 / 行为 |
| --- | --- |
| `--action install` / `uninstall` | GUI 默认预设 install；后台必须明确提供 |
| `--features file-create` / `--scope file-create` | 默认只管理本功能，不能转为其它功能 |
| `--non-interactive` | 内部 worker 模式；直接执行已确认任务 |
| `--gui-session` | 由公开 App 进入独立后台面板会话 |
| `--skip-finder-restart` | 将 Finder 刷新交给上级总管理器 |
| `--help` | 只显示参数帮助，不构建和注册 |

安装构建上级 `JobsFileCreator.xcodeproj` 的 Debug 产物，核对 Bundle ID 及深度签名，再注册、启用并确认当前精确路径。卸载只处理已核验的 `com.jobs.filecreator.findersync` 登记副本，不删除 App、源码和任何已创建文件。未跳过时最后刷新 Finder。

首次登记尚未进入系统索引时，后台初始化宿主并最多重新登记一次，再核对当前精确路径及启用状态。重新登记命令失败立即停止；两次后仍未登记、被停用或只查到旧路径均报告失败。安装回归使用命令替身覆盖这些分支，不操作真实系统登记。

业务标准输出、错误输出与状态事件进入同一 GUI 输出管道，完整 worker 日志保留在系统临时目录 `JobsFileCreatorManage.log`。GUI 启动编译失败通过桌面提示和独立启动日志报告。每包使用上级 `work/.manager-lock` 防止并行管理，异常锁须先确认没有存活任务再处理。

## 三、<span id="verification">只读检查</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下命令不执行安装或卸载：

```shell
/bin/zsh -n ./ManageExtension.zsh
/bin/zsh -n ./FinderManagerGUI.zsh
/bin/zsh ./ManageExtension.zsh --help
ruby ../Tests/FileCreationTests.rb
ruby ../Tests/InstallerTests.rb
```

首次运行 GUI 编译缓存需要 Xcode 命令行工具，安装还要求完整 Xcode 和 macOS SDK。更多权限、产物和右键使用说明见 [功能 README](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
