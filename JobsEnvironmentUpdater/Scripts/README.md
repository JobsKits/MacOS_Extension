# JobsEnvironmentUpdater Scripts

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、资源清单](#jobs-toc-heading-2)
- [二、运行与边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录同时提供独立管理器及随包 `update` 的完整资源。公开管理入口位于[上级目录](../README.md)。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、资源清单 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 入口 | 职责 |
| --- | --- |
| [update](./【MacOS】update.command/README.md) | 完整更新脚本；无参数默认低打扰，显示自述后自动维护，最多启动阶段系统密码，保留日志及未完成汇总 |
| [_lib](./_lib/README.md) | 四个 SDK／网络模块与 Git 选路包装器 |
| [ManageExtension](./【MacOS】ManageExtension.zsh/README.md) | 本项安装／更新、卸载及构建产物清理 |
| [FinderManagerGUI](./【MacOS】FinderManagerGUI.zsh/README.md) | 面板编译及启动 |
| [AppDeployment](./【MacOS】AppDeployment.zsh/README.md) | 精确身份部署、登记、恢复及清理 |
| [联合App管理](./【MacOS】联合App管理.zsh/README.md) | 联合安装的资源与独立快照 |
| `ManagementPanel.swift` | 与总管理面板同源的原生界面，按 `environment-update` 限定范围 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

Xcode 将 `【MacOS】update.command/` 与 `_lib/` 复制到宿主 `Contents/Resources/Scripts/`，保持相对关系。菜单启动器再复制至本轮私有快照，更新终端不依赖源码目录、其它安装单元或原 `JobsMacEnvVarConfigs`。直接运行帮助不会更新工具：

```zsh
/bin/zsh ./【MacOS】update.command/【MacOS】update.command --help
```

安装与实际升级是两个独立动作；管理器初始化宿主不会启动升级。菜单副本与终端 `update` 均无参数默认低打扰，显示自述后自动维护，启动时可能需要一次管理员密码，后续使用 `sudo -n`；不等待逐项或收尾重试确认，不自动打开下载页面。普通子命令使用输入结束，已知确认点自动回答；缺失、认证或权限阻塞汇总为未完成并继续其它项目。收尾直接退出，需要再试时重新执行 `update`，`Ctrl+C` 可中止本轮。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
