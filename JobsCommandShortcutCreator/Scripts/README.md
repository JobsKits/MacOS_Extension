# 脚本快捷入口扩展 · 管理脚本

此目录为独立功能 `command-shortcut-create` 提供管理面板、安装 / 更新、卸载和已装模块构建产物清理。由上一级 [公开管理入口](../【MacOS】管理脚本快捷入口Finder扩展.command) 启动；完整功能说明见 [README](../README.md)。

| 文件 / 目录 | 职责 |
| --- | --- |
| `./【MacOS】ManageExtension.zsh/【MacOS】ManageExtension.zsh` | 校验本包范围，打开面板或执行已确认的后台操作；只管理 `JobsCommandShortcutCreator` |
| `./【MacOS】FinderManagerGUI.zsh/【MacOS】FinderManagerGUI.zsh` | 编译、缓存、签名并打开原生 GUI；不自行安装或卸载扩展 |
| `ManagementPanel.swift` | 随包管理面板，提供十语言、三种主题、空选门禁、逐项状态与可复制日志 |
| [【MacOS】AppDeployment.zsh](./【MacOS】AppDeployment.zsh/README.md) | 精确 App 身份核验、安装位置、事务备份恢复与清理 |
| [【MacOS】联合App管理.zsh](./【MacOS】联合App管理.zsh/README.md) | 将面板与本功能卸载资源装入联合 App，源码移走后仍可管理已安装功能 |

依赖 macOS 自带 zsh、Swift 编译器、Xcode、codesign、LaunchServices 和 PlugInKit。管理入口只在用户于面板点击操作按钮后构建并注册或卸载本项扩展，安装完成刷新 Finder；不会生成业务快捷入口，也不会执行内部目标脚本。取消、关闭或空选不执行安装 / 卸载。

构建缓存位于本包 `work/`，管理日志为系统临时目录中的 `JobsCommandShortcutCreatorManage.log`，面板另外保留完整会话日志；互斥锁为本包 `work/.manager-lock`。同包已有任务时停止重复执行，故障先查看日志，不并行运行第二次管理。需要单独复制时应完整保留本功能包，不只复制此目录。
