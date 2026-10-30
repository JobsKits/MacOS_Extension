# 桌面菜单安装管理

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、参数](#arguments)
- [二、业务资源](#resources)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录的 [ManagementPanel.swift](./ManagementPanel.swift) 与 [FinderManagerGUI.zsh](./FinderManagerGUI.zsh) 负责随包面板和编译缓存。总进度按已处理项 / 本次所选项显示计数和百分比；成功与失败计入已处理，等待中和执行中不计入，100% 表示全部处理完毕，结果以成功 / 失败汇总为准。安装 / 更新和卸载分别计时；点击时只清零并启动当前操作计时，后台全部结束或启动失败时只冻结当前耗时。每秒刷新 `HH:mm:ss`（小时可超过 24），执行时显示“安装用时 / 卸载用时”，结束显示“安装总用时 / 卸载总用时”。两份耗时只在当前面板会话内独立保留。安装成功显示绿色“✅ 安装成功”。切换操作会显示该操作已有的耗时。支持独立复制时须连同上级 App、启动脚本、源码及资源整体保留。

日志区上方的分隔条可上下拖动，窗口也可调整大小；功能列表与日志分别滚动，并保留操作按钮。日志右键提供“全选”，也可用 `⌘A` 全选后 `⌘C` 复制；拖动不会清空日志或改变功能勾选。

`ManageDesktopTools.zsh` 接收 `install|uninstall` 和明确的叶功能 ID，统一管理六个桌面菜单。完整功能、配置、事务、日志和验证见[聚合包说明](../README.md)。

## 一、<span id="arguments">参数</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

支持 `ios-simulator-create`、`android-simulator-create`、`harmony-simulator-create`、`android-simulator-repair`、`harmony-simulator-repair` 和 `hidden-files-toggle`。可一次传多个 ID；空选、未知项和错误操作在构建或写配置前停止。

`--non-interactive` 表示调用方已经确认安装范围；`--install`／`--uninstall` 为旧入口兼容参数。`--skip-finder-restart` 只跳过本层 Finder 刷新，不跳过构建、签名和登记核对。未显式授权无交互运行时，必须从交互终端阅读说明后回车确认。

## 二、<span id="resources">业务资源</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

管理器不会执行 `Resource/` 中的模拟器脚本，不会打开宿主 URL。安装完成后，用户点击菜单才由宿主调用本包业务；五份脚本的来源与摘要见 [SourceManifest.json](../SourceManifest.json)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
