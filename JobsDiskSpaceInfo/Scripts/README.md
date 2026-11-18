# JobsDiskSpaceInfo 管理脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、文件职责](#files)
- [二、参数与行为](#options)
- [三、只读检查](#checks)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录提供“磁盘空间总览”的安装／更新、卸载管理及独立磁盘清理业务；容量仍在 Finder 扩展中直接读取，不通过 Shell 采样。公开入口为上级 [管理脚本](../【MacOS】管理磁盘空间Finder扩展.command)与同名 App。默认打开 GUI，不直接修改系统。

## 一、<span id="files">文件职责</span>

| 文件 | 职责 |
| --- | --- |
| [【MacOS】清理磁盘空间.command](./【MacOS】清理磁盘空间.command/README.md) | 点击容量行后独立 Terminal 启动；Xcode 准确范围回车执行、非空跳过，普通失败仍进入常规六类回车确认；缓存首行全选、次行默认跳过，最终汇总两阶段 |
| `./【MacOS】ManageExtension.zsh/【MacOS】ManageExtension.zsh` | 校验 `disk-space-info` 范围；完整仓转交总管理器，独立包执行构建、身份／签名校验、登记、启停、精确卸载与清理，并在全部后处理后核验本项登记稳定 |
| `./【MacOS】FinderManagerGUI.zsh/【MacOS】FinderManagerGUI.zsh` | 从当前包定位资源，按需编译缓存并运行面板；失败显示错误与启动日志 |
| `ManagementPanel.swift` | 默认空选的原生面板，含状态、计时、进度、可复制日志、十种语言及白天／黑夜／跟随系统主题 |
| [AppDeployment.zsh](./【MacOS】AppDeployment.zsh/README.md) | 联合 App 发布、身份校验、失败恢复及构建残留清理 |
| [联合App管理.zsh](./【MacOS】联合App管理.zsh/README.md) | 将管理资源随联合 App 交付，支持源码移走后的管理 |

管理面板复用当前用户偏好域 `com.jobs.finderextensions.managementpanel.preferences`；主题／语言变更即时生效并保存，保留勾选、操作状态、日志和布局。Finder 菜单独立跟随系统语言与外观；原始工具日志保留原文。管理器从自身路径解析所有资源，不依赖启动工作目录或开发机位置。

## 二、<span id="options">参数与行为</span>

| 参数 | 行为 |
| --- | --- |
| 无参数 | 打开 GUI，由用户选择并确认；关闭或空选不执行 |
| `--action install` / `uninstall` / `cleanup` | 后台操作，必须配合 `--non-interactive` 显式传入；普通公开入口仍只打开 GUI |
| `--features disk-space-info` / `--scope disk-space-info` | 仅允许本功能，未知 ID 在写入前拒绝 |
| `--install-location build` / `applications` | 内部 worker 默认 build；GUI 首次默认 applications，用户可取消 |
| `--cleanup-build-products` | 仅限成功安装到 applications 后清理本轮构建输出；默认后台不清理 |
| `--skip-finder-restart` | 内部调用由上级统一刷新 Finder |
| `--stop-request-file PATH` | 完成本轮安装单元后停止，保留未处理项 |
| `--help` | 只显示帮助，不构建、登记或卸载 |

应用程序路线将签名宿主和扩展收进 `/Applications/Jobs自定义右键菜单.app`，构建仍在本包 `work/DerivedData`。构建目录路线须保留其 App；卸载只处理所选位置经身份核验的本模块，保留其它模块、另一位置及所有业务文件。独立清理需 applications 路线并通过归属、登记与引用校验；失败保留产物。管理器使用本包 `work/.manager-lock` 防止并发；不按名称清理未知来源文件。

提交前失败进入既有恢复流程；`commit` 在释放旧备份前精确注销 `previous.app` 旧副本。文件提交、用户选择的构建清理及最终刷新结束后，独立管理器仅对本项精确目标执行连续 60 秒登记稳定核验，总观察预算 150 秒、每个 ID 最多定向恢复 2 次；每次恢复完成后 5 秒只读等待，约每 10 秒报告进度，全部通过后才发送 `succeeded`。完整仓的总管理器让本轮所有安装单元共享同一观察窗口，不逐项增加 60 秒。来源或目标节点变化、另一位置同 ID 启用、系统查询失败即停止，不覆盖外部并发选择；取消码 `129`／`130`／`143` 原样停止，不继续修复或下一个单元。预算在操作之间检查，不承诺中断内核 I/O。普通构建清理失败沿既有策略保留已提交 App 并记录警告，不冒充清理成功；最终登记核验失败仍返回失败。后台完整日志保留在系统临时目录 `JobsDiskSpaceInfoManage.log`，面板保存本次完整会话日志并允许复制；源码与只读回归通过不代表已安装菜单已更新。

## 三、<span id="checks">只读检查</span>

```shell
/bin/zsh -n ./【MacOS】ManageExtension.zsh/【MacOS】ManageExtension.zsh
/bin/zsh -n ./【MacOS】FinderManagerGUI.zsh/【MacOS】FinderManagerGUI.zsh
/bin/zsh ./【MacOS】ManageExtension.zsh/【MacOS】ManageExtension.zsh --help
```

这些命令不安装／卸载、不注册扩展或重启 Finder；功能行为及采样口径见 [功能说明](../README.md)。
