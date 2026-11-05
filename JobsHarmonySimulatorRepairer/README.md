# `JobsHarmonySimulatorRepairer`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、功能与范围](#capabilities)
- [二、安装与卸载](#installation)
- [三、直接使用](#usage)
- [四、备份、恢复与结果判断](#backup)
- [五、隔离验证](#verification)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

为 [**macOS**](https://www.apple.com/macos/) 系统桌面空白右键提供 **Harmony 模拟器检测与修复**。独立 App + [**Finder Sync Extension**](https://developer.apple.com/documentation/findersync)，通过可见 Terminal 使用 [**Huawei DevEco Emulator**](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-emulator-command-line) 官方命令处理本机已有实例。核心随聚合 App 打包，源码安装需保留相邻聚合目录。

当前菜单安装由 [JobsDesktopTools](../JobsDesktopTools/README.md) 统一承载。本目录的管理入口只启停 `harmony-simulator-repair` 这一叶；需要同仓 `JobsDesktopTools/` 源码。聚合扩展按固定顺序排列三项新建、两项修复和动态文件显示开关，保留逐叶选择；普通目录背景仅显示文件开关。安装产物统一在 `../JobsDesktopTools/work/DerivedData/Build/Products/Debug/JobsDesktopTools.app`，安装／卸载日志统一为系统临时目录 `JobsDesktopToolsInstall.log`。本目录原工程、旧 Bundle ID、旧 URL 和隔离回归仍保留，后文源码标识用于兼容实现参考，不是当前安装器注册目标。


**安装 / 卸载位置：** 面板提供“使用「应用程序」文件夹安装 / 卸载”复选框，默认不勾选。不勾选时沿用本地 `work` 内的构建产物；勾选时将所选功能统一安装到 `/Applications/Jobs自定义右键菜单.app`，面板同时显示这个联合 App 的名字。完整宿主及其扩展收在联合 App 内，不再为本轮所选功能生成其它顶层 App。安装到应用程序后，清理仓库构建输出或移走源码不影响已安装功能；构建目录模式仍须保留正在使用的 App。两种方式都保留各功能自身的工具链依赖。

**安装后清理：** 仅在“安装 / 更新”且勾选应用程序路线时，显示默认不勾选的“安装成功后清除此轮构建产物”。明确勾选后，只有当前模块部署、登记和提交全部成功才清理本轮对应的 DerivedData；构建目录路线及卸载模式隐藏并清空该选项。失败安装保留构建产物，清理失败会提示并保留已安装功能；不会整目录清理所有 `work`、其它模块或源码。

卸载按同一复选框选定的位置执行，所选位置没有 App 时保留另一位置及其功能配置；共享宿主仍有未卸载菜单时保留 App，最后一项移除后注销并删除该功能模块；联合 App 的最后一个模块移除后才删除外层 `Jobs自定义右键菜单.app`。切换位置安装会把登记切到新位置，构建目录中的另一份产物保留；所选功能的旧版顶层自有 App 在成功提交后收拢至联合 App，未知 App 不覆盖或删除。完整说明见[App 部署支持库](./Scripts/【MacOS】AppDeployment.zsh/README.md)。


**独立清理与停止：** 安装位置选择、显示中的自动清理复选框与红色“🧹 清除构建产物”按钮排在同一行，垂直居中、间隔统一。应用程序路线显示红底白字的“🧹 清除构建产物”按钮，安装 / 卸载页签均可单独清理当前勾选功能，不要求重新安装；没有勾选或正在执行任务时禁用。原“安装成功后清除此轮构建产物”复选框仍默认关闭，只在安装模式出现。构建目录路线隐藏两项清理控件。清理须核验已安装联合 App、精确扩展登记与来源占用，失败保留运行功能，不清理源码或其它模块。

安装中原操作按钮改为“停止安装”。点击只请求完成当前共享 App 安装单元后停止，不终止其编译、签名、登记或回滚；后续单元标记“未执行”，不计失败或已完成百分比。同一共享 App 的叶功能一起提交。清理使用独立计时，不覆盖安装或卸载耗时。

**App 管理授权：** 新版 GUI 从名称固定的 `Jobs右键菜单管理面板.app` 运行。若 macOS 拒绝修改联合 App，面板显示授权入口并停止后续安装；在“系统设置 → 隐私与安全性 → App 管理”中添加 / 启用实际负责的管理面板后重试。此权限用于允许 App 更新或删除其它 App，参见 [Apple 官方说明](https://support.apple.com/en-au/guide/mac-help/mchl211c911f/mac)。普通目录可写不能替代此授权，不使用提权运行整个安装器或修改 TCC 数据库。

## 一、<span id="capabilities">功能与范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 操作 | 行为与确认 |
| --- | --- |
| 只读诊断 | 检测官方 CLI 能力、已下载 Release 镜像、唯一实例身份、`isRunning`、实例配置与 SDK / HDC 版本；不写本工具日志。异常返回非零。 |
| 启动选中实例 | 再次核对同名同路径的官方登记，回车启动；轮询 `isRunning=true` 才报告运行状态通过。 |
| 保留数据冷启动修复 | 输入精确 `YES`；运行中先执行 `-stop NAME` 并等到 `isRunning=false`，再执行 `-start NAME -bootMode coldboot`，轮询运行状态。适用于快照或启动异常；保留安装的应用、上传文件等既有数据。 |
| 修复失效 SDK 路径 | 输入 `YES`，要求全部模拟器关闭；完整备份单一实例后，将缺失 / 失效的 `config.ini` SDK 路径指向同一 DevEco / CLT 内已通过 HDC 版本检测的 SDK。保留其余配置。 |

不下载或升级工具、接受许可、删除应用、清锁、清空用户数据或调整容量；不修改系统代理、全局 SDK 或 Shell 配置。未知官方字段、重复名称、不可靠路径、符号链接、失败退出码均停止。选中后固定官方 UUID、产品类型、系统版本及目录 / 配置的文件身份，确认期间同名重建也不能沿用旧请求。真机不在 Emulator 本地实例清单中，不会进入动作目标。

菜单仅在系统桌面空白处显示；普通目录背景、文件、多选、工具栏或侧边栏不提供。需要创建实例时使用[新建 Harmony 模拟器](../JobsHarmonySimulatorCreator/README.md)。

## 二、<span id="installation">安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

菜单安装与卸载统一使用 [图形管理入口](./【MacOS】管理Harmony模拟器检测修复Finder扩展.app)。直接打开面板，选择“安装 / 更新”或“卸载”并勾选当前范围内的功能；默认空选，点击操作按钮即确认。每项显示等待、正在安装 / 卸载、成功或失败；底部日志实时滚动，可选择复制或复制全部。运行中锁定选择和关闭入口，结束后保留结果与日志。首次打开或面板源码更新后会在后台编译，失败以桌面提示和启动日志说明。

原同名 `.command` 入口保留，终端只负责唤起独立 GUI，随后结束启动脚本；本次启动任务结束后自动关闭对应终端页，安装 / 卸载、进度与实时日志均由 GUI 后台处理。已有交互 Shell 中手工调用时保留原工作会话。内部实现为 `Scripts/ManageExtension.zsh`；完整仓内单功能入口使用总面板的受限范围。可独立复制的包须整体保留 `.command`、`.app`、Scripts、工程源码和资源。

启动器按自身位置定位配套文件，不依赖本机固定目录或启动时的工作目录。`.command` 会把当前包目录传给同名 App；直接打开 App 无法定位 `Scripts` 时，按提示选择同时包含同名 App 与 `Scripts/` 的原始目录，取消选择不会执行安装或卸载。

本入口转交 [JobsDesktopTools](../JobsDesktopTools/README.md)，只管理 `harmony-simulator-repair`，需要保留同仓聚合工程源码。旧宿主、扩展与 Xcode 工程仍供实现参考和隔离验证；常规菜单安装不再注册本目录的旧独立扩展。

需要 macOS 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 与 macOS SDK。安装成功后启用本入口对应功能并保留其它已装选择；卸载仅减去对应功能，仍有其它项时保留共享 App 和登记，最后一项才停用聚合扩展。源码、用户工程、SDK、模拟器、业务数据和既有业务配置保留；安装与卸载只管理菜单，不执行菜单业务。操作完成后刷新 Finder，请先结束 Finder 文件搬移。

安装 / 卸载日志为系统临时目录中的 `JobsDesktopToolsInstall.log`。

也可从 [总管理面板](../【MacOS】🧩管理Finder扩展.command) 选择一个或多个功能，在同一面板切换安装 / 更新或卸载。

## 三、<span id="usage">直接使用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

以下命令在本 README 所在目录运行。

```shell
/bin/zsh ./Scripts/RepairHarmonySimulator.zsh
```

只读检查全部或指定实例：

```shell
/bin/zsh ./Scripts/RepairHarmonySimulator.zsh \
  --check \
  --name JobsHarmony_Test
```

`--repair` 为默认交互模式；`--help` / `-h` 只显示帮助。多实例时按编号选择，回车默认第一项；动作菜单回车 / `q` 结束。SDK 修复和冷启动均需精确 `YES`，没有自动确认开关。

工具发现优先显式 `HARMONY_EMULATOR_BIN`，其次 `DEVECO_STUDIO_HOME` / `TOOL_HOME`，默认搜索常见 DevEco 安装、`~/Library/Application Support/JobsHarmonySimulator/clt-*/emulator/Emulator` 和 PATH。候选必须通过官方能力检查；显式坏路径或多个健康候选停止，避免误用 Android emulator 或切换 SDK。

交互日志位于系统临时目录的 `JobsHarmonySimulatorRepairer.XXXXXX/RepairHarmonySimulator.log`；宿主诊断为 `/tmp/JobsHarmonySimulatorRepairer.log`。`--check` 不创建本工具日志、备份或临时配置。

## 四、<span id="backup">备份、恢复与结果判断</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

SDK 修复只处理官方清单中路径尾部与名称一致的普通实例目录，配置须含唯一匹配 `name=`。重复 SDK 键、链接目录 / 内容、仍在运行或无法读取进程表时拒绝写入；保守要求所有 Harmony / Android 模拟器退出。预留完整备份容量加 1 GB 余量，备份保存到实例父目录的 `.<名称>.jobs-repair-backup.XXXXXX/instance/`，逐文件比较后再次核对身份、停机状态、原配置摘要，才原子替换失效 SDK 键。备份不自动删除。SDK 路径拒绝控制字符及非规范链接路径；发布前再次检查身份、停机与原配置摘要，外部变更则保留原文件、备份及候选配置。

恢复时先正常关闭对应模拟器并保留当前现场，再将备份 `instance/config.ini` 恢复到原实例；本功能只改这一份配置，不修改 userdata。若发现其他内容也已被外部操作改变，应先核对完整备份，避免覆盖后续用户数据。

冷启动不使用 `reset`，停止失败或状态未变为 false 时绝不继续启动；启动失败、实例路径变化、JSON 未知或状态轮询超时返回非零。`isRunning=true` 只证明官方报告实例运行，系统开机完成、HDC 连接和应用运行仍须窗口核对，不能据此断言所有模拟器问题均已修复。官方要求账号登录的版本可能不能通过 CLI 启动，应在 Device Manager 手动处理。

官方依据：[实例字段、停止与 coldboot 语义](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-emulator-command-line.md)。

## 五、<span id="verification">隔离验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
ruby ./Tests/RepairHarmonySimulatorTests.rb
ruby ./Tests/InstallerRegistrationTests.rb
```

测试使用假官方 CLI、临时实例和系统命令替身，覆盖只读、状态未知、冷启动顺序、停止失败、取消、SDK 完整备份及链接保护。共享请求、菜单范围、私有载体与宿主去重测试位于 `Tests/`；不注册扩展、不操作用户模拟器。源码回归与签名构建不替代 Finder 菜单、真实 DevEco 输出、许可和真实冷启动验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
