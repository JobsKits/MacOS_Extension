# [**Git**](https://git-scm.com/) 动态代理桌面入口脚本

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与验证](#run)
- [二、日志与卸载边界](#logging)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[ManageExtension.zsh](./ManageExtension.zsh) 是本功能的内部管理器，由上级 `.command` 启动器唤起的独立 App 调用；启动器结束后，安装 / 卸载确认、逐项状态和实时日志都在 GUI 内处理。正常使用从上级管理入口进入，后台非交互参数仅由面板提交已确认的计划。

本目录由 Jobs 维护，只服务 [JobsGitProxyConfigurator](../README.md)。**扩展安装与用户 Git 配置是两层独立动作**：前者注册菜单，后者必须在 [**Terminal**](https://support.apple.com/guide/terminal/welcome/mac) 由用户确认。

| 文件 | 职责与边界 |
| --- | --- |
| [ConfigureGitDynamicProxy.command](./ConfigureGitDynamicProxy.command) | 完整自包含的规范源副本，随 App 打包；无参数保留回车安装、C 检查、R 恢复，`--check` 只读。菜单不会传入 `--install` 绕过确认。 |
| [EnableFinderExtension.zsh](./EnableFinderExtension.zsh) | [**Xcode**](https://developer.apple.com/xcode/) 构建后可注册、启用本扩展并刷新 [**Finder**](https://support.apple.com/guide/mac-help/welcome/mac)；外层安装器或隔离构建通过 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 跳过。该开关只控制本脚本，Xcode 仍可能通过自带步骤登记宿主 URL。 |

业务副本与[独立入口](../../../../JobsCommand@Gits/MacOS/【MacOS】🌐双击配置Git动态代理.command/README.md)保持整文件字节一致。宿主把资源复制到独立私有临时目录，再通过安全单行命令交给 Terminal；不从源仓库路径运行，不接受外部脚本或路径参数。临时副本完成后清理，用户安装生成的 Git 入口和快照保留。


**安装位置参数：** 总 worker 与单功能 worker 接受 `--install-location build|applications`，默认 `build`。GUI 将“使用「应用程序」文件夹安装 / 卸载”的勾选状态作为明确参数传入，执行期间锁定该选择。不勾选时登记本地构建目录，勾选后通过[部署库](./【MacOS】AppDeployment.zsh/README.md)将完整签名功能模块收进 `/Applications/Jobs自定义右键菜单.app` 再登记；构建器始终写原来的构建目录。缺少目录写权限、同名 App 身份不符、复制或签名校验失败均报告失败，不隐式切回另一位置。

可选布尔参数 `--cleanup-build-products` 仅接受 `--action install --install-location applications`，其它组合在业务前报错。默认不清理；UI 仅在应用程序安装模式显示清理选项，退出该组合就清空。成功提交之后才核验并清理该模块本轮 DerivedData，清理错误进入日志而不回滚已成功安装的联合 App。

安装 / 更新切换登记位置而保留其它位置文件；卸载只处理本次位置，缺失副本不改另一位置的功能配置。共享宿主最后一叶移除后才注销并删除该模块，联合 App 中最后一个模块移除后才删除 `Jobs自定义右键菜单.app`。原有 SDK、业务文件与源码不删除。未使用 `--manager` 的旧选择预览模式保持原计划格式，不提供位置复选框。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## 一、<span id="run">运行与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录手动使用业务副本：

```shell
/bin/zsh ./ConfigureGitDynamicProxy.command
/bin/zsh ./ConfigureGitDynamicProxy.command --check
```

默认入口必须有可交互终端。`--install` 是独立脚本提供的明确无交互安装授权，**桌面右键不使用该参数**；R / `--restore` 按精确快照恢复，遇到后续冲突停止。业务影响范围和日志详见完整脚本的运行时自述。

从工程目录运行隔离回归：

```shell
/bin/zsh ../Tests/run.zsh
```

测试验证资源一致性、固定 URL、真实 Home/Desktop、普通目录与选中项拒绝、两种 URL 回调去重、Shell 特殊字符往返、私有文件权限、标准退出码与清理，以及固定 Bundle ID 注册与卸载。系统注册、Terminal 和 Finder 刷新使用替身，不动真实 Git 配置。

## 二、<span id="logging">日志与卸载边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

构建后启用日志是系统临时目录中的 `JobsGitProxyConfiguratorBuildPhase.log`；宿主派发日志是 `JobsGitProxyConfigurator.log`。用户 Git 配置快照与脱敏审计由完整业务脚本保存在用户 Application Support 的专用目录。菜单卸载只移除固定扩展和核验 App，不能删除业务配置或代替业务恢复。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
