# 所选项目隐藏显示扩展 · 管理脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

此目录为独立功能 `file-visibility` 提供管理面板、安装 / 更新、卸载和已装模块构建产物清理。由上一级 [公开管理入口](../【MacOS】管理所选项目隐藏显示Finder扩展.command) 启动；完整功能说明见 [README](../README.md)。

| 文件 / 目录 | 职责 |
| --- | --- |
| `./【MacOS】ManageExtension.zsh/【MacOS】ManageExtension.zsh` | 校验本包范围，打开面板或执行已确认的后台操作；只管理 `JobsFileVisibility` |
| `./【MacOS】FinderManagerGUI.zsh/【MacOS】FinderManagerGUI.zsh` | 编译、缓存、签名并打开原生 GUI；不自行安装或卸载扩展 |
| `ManagementPanel.swift` | 随包管理面板，提供十语言、三种主题、空选门禁、逐项状态与可复制日志 |
| [【MacOS】AppDeployment.zsh](./【MacOS】AppDeployment.zsh/README.md) | 精确 App 身份核验、安装位置、事务备份恢复与清理 |
| [【MacOS】联合App管理.zsh](./【MacOS】联合App管理.zsh/README.md) | 将面板与本功能卸载资源装入联合 App，源码移走后仍可管理已安装功能 |

依赖 MacOS 自带 zsh、Swift 编译器、Xcode、codesign、LaunchServices 和 PlugInKit。管理入口只在用户于面板点击操作按钮后构建并注册或卸载本项扩展，安装完成刷新 Finder；不修改任何文件或文件夹的隐藏属性。取消或空选不执行安装／卸载；任务中关窗会继续后台执行。

构建缓存位于本包 `work/`，管理日志为系统临时目录中的 `JobsFileVisibilityManage.log`，面板另外保留完整会话日志；互斥锁为本包 `work/.manager-lock`。同包已有任务时停止重复执行，故障先查看日志，不并行运行第二次管理。需要单独复制时应完整保留本功能包，不只复制此目录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
