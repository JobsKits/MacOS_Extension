# JobsDiskSpaceInfo：磁盘空间总览

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、容量与刷新](#capacity)
- [二、安装与卸载](#management)
- [三、源码与验证边界](#sources)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

在 [**macOS Finder**](https://support.apple.com/guide/mac-help/welcome/mac) 的文件、文件夹、多选、目录／桌面背景和侧边栏右键菜单显示一行磁盘信息，例如 `💽 磁盘剩余：123.45 GB / 1.00 TB（12.35%）`。点击这一行会打开独立 Terminal，先询问是否进行 Xcode 六组清理，再展示终端 clean 的六类范围；常规清理按回车确认，任意非空输入或输入结束取消。没有快捷键或子菜单，容量读取失败时仍能点击打开清理流程。

**本轮可运行成品：** [JobsDiskSpaceInfo.app](../work/FixedDesktopMenu-20261118/JobsDiskSpaceInfo.app) 与[源码 / 产物回执](../work/FixedDesktopMenu-20261118/receipt.json)对应，包含双架构宿主、FinderSync 与业务资源；仅完成隔离构建，安装和真实菜单验收另列。

**固定顺序背景菜单：** 应用程序中的联合 App 通过包内 `Contents/Resources/DesktopMenu.json` 指定唯一展示扩展，依次生成“新建文件 → 新建 iOS / Android / Harmony 模拟器 → Android / Harmony 模拟器检测与修复 → 显示 / 隐藏文件 → 更新开发环境（update）→ 磁盘剩余”；只显示已安装且适用的项目。各功能独立宿主、叶开关和安装 / 卸载边界保留。普通文件夹背景按同一顺序显示新建文件、文件显示开关和磁盘剩余。跨模块固定顺序需要将这四个模块均更新到支持清单的版本；独立构建目录路线继续使用原菜单。系统手动停用当前展示扩展会暂时隐藏整组背景菜单，重新启用或从面板安装 / 更新可恢复；从管理面板卸载模块时自动重选展示扩展。损坏清单、身份变化及过期点击不会派发业务。详见[右键菜单顺序资产盘点](../../项目相关报告/右键菜单顺序资产盘点.md)。

## 一、<span id="capacity">容量与刷新</span>

- 每次打开菜单重新枚举挂载，并同步查询系统当前可用字节数；不保存启动时、安装时或上一次的容量。汇总后计算 `总剩余 ÷ 总容量 × 100`，百分比固定保留两位小数。
- 不逐盘列举；共享同一 APFS 容器的卷只计一次，同容量时采用 Data 的完整样本，不拼接其它卷较大的旧余量。排除网络盘、文件镜像、RAM盘、只读卷及隐藏辅助挂载（系统根卷／Data 例外），不随选中目录切换统计范围。挂在本机路径上的 NAS 磁盘镜像也不增加本机容量；真实 APFS 合成容器和外接物理盘仍按规则统计。
- 读取失败时显示“磁盘空间无法读取”，仍可点击，不编造零容量或使用过期结果。容量采用十进制单位，显示值经过舍入，百分比按原始字节计算。受配额限制的卷与未公开挂载的卷按系统查询结果处理，不承诺原始物理盘容量。
- 剩余量采用系统可用空间口径，使用 `volumeAvailableCapacityForImportantUsage`，包含系统预计可清除的非必要资源与缓存；总量由同次 `volumeTotalCapacity` 查询取得。接口缺值、报错或负数时显示不可用，不退回原始空闲量。系统设置有自己的刷新时点，重新打开菜单后读取当前值。
- 菜单跟随系统语言，覆盖简体中文、繁体中文、藏文、英文、日文、法文、西班牙文、德文、俄罗斯文、韩文；使用 Finder 原生外观，随 Finder 的系统主题变化。管理面板支持独立切换上述十种语言及白天、黑夜和跟随系统主题。

<strong id="cleanup">点击与清理</strong>

固定顺序背景菜单的点击由 Finder 扩展主对象接收，再按该次菜单的 tag 快照转交磁盘工具宿主；文件、侧边栏与独立菜单继续使用本功能原入口。目标安装或上下文已变化时拒绝过期请求，重新右键后再操作。

清理失败会直接在终端显示具体系统原因及路径，同时保留日志；不会只提示“清理失败，请看日志”。

常规清理失败后会列出未完成步骤和日志，并询问是否继续；回车仅重试失败步骤，非空输入停止，EOF／取消不继续。每轮结果追加日志，成功步骤出队；缓存保留原失败候选身份，新生成或替换项不加入重试。前置 Xcode 分组普通失败仍进入常规清理，最终分别汇总两阶段；取消信号或 EOF 中止整个运行。

Xcode 阶段先问是否继续：回车进入，任意文字再回车跳过；只在接受后扫描 Device Support、Simulators、SwiftUI Previews、DerivedData、Archives 和 Caches 六组。每组使用 fzf，第一行默认为该组全部清理，也可选择单项／多项；展示最终准确范围后，回车执行，任意非空字符加回车取消本次 Xcode 清理并进入常规流程。阶段完成、跳过或普通失败后，进入常规 clean 的回车确认；Xcode 未完成状态保留到整体退出。具体路径、设备备份与差异见[独立脚本说明](./Scripts/【MacOS】清理磁盘空间.command/README.md)。

常规阶段展示与终端 `clean` 相同的完整功能和风险说明，再按回车确认；任意非空输入、EOF 或 `Ctrl+C` 取消。能力覆盖磁盘上的 zsh 历史／会话、非 macOS 构建 App 移废纸篓、开发 App 登记注销、实体缺失 iOS 模拟器备份注销、已有 Homebrew cleanup 和用户缓存选择。缓存面板首行“全选用户缓存”、第二行“跳过用户缓存清理”（默认焦点）；Enter 勾选、Space 确认；未勾选时 Space 选定当前行，有勾选时只提交原集合。默认跳过行仍可直接 Space 跳过，全选只展开本轮完整候选；选定后按内容与权限预检并确认准确范围；开发依赖／源码标记、只读、链接、异盘或检查不完整的候选保留。规则按当前电脑实际环境解析，不依赖特定用户名、工程或环境目录名。选中缓存和历史直接删除，不能自动恢复；正常 App、完整模拟器、共享 Runtime 和源码保留。Xcode 跳过／未选不会被后续清理绕过，不自动安装依赖、改变 tap 信任或提权。

缓存候选采用单项 10,000 项／64 层及操作间 5 秒检查预算；检查不完整即保留，不承诺中断单次阻塞系统 I/O。具体 fzf 按键、最终范围确认及并发保护见[独立脚本说明](./Scripts/【MacOS】清理磁盘空间.command/README.md)。

清理业务随 App 打包；宿主将其复制到私有临时快照，先以 `launch` 启动 Terminal，再由一次 `do script` 创建执行窗口，最后激活；不占用已有用户会话，不引用外部 clean。已经打开的清理终端可独立于原 App 继续运行；结束回收载体，保留诊断日志。确认后的旧阶段有本用户互斥锁，已有任务时拒绝重复清理；强制终止造成的遗留锁保留并报告。关闭菜单后重新右键才读取最新容量，不承诺立即刷新已经展开的旧菜单。

## 二、<span id="management">安装与卸载</span>

双击 [管理入口](./【MacOS】管理磁盘空间Finder扩展.command)或同名 App，在“文件与通用工具”中勾选“磁盘空间总览”，再点击安装／更新或卸载。默认空选，取消／关闭不执行操作；本功能标识为 `disk-space-info`，可单独管理，不需要安装其它业务功能。

完整仓库优先使用总面板；整体复制本目录后可使用随包面板和 worker。需要完整 Xcode、macOS SDK、Swift 编译器及系统 zsh，不需要第三方运行时。菜单最低支持 macOS 12。

面板首次默认勾选应用程序中的联合 App 和安装成功后清理构建产物，可手动取消。应用程序路线将完整宿主与扩展放入 `/Applications/Jobs自定义右键菜单.app`；构建目录路线使用本包 `work/DerivedData` 中的 App，须保留该产物。安装校验宿主／扩展身份和签名、登记并启用对应 Finder 扩展，最后刷新 Finder；先结束 Finder 中的复制／移动操作。App 管理授权缺失会明确报告，不提升整个安装器权限。

卸载仅移除所选位置的本功能登记与产物，保留其它功能、另一位置、源码和用户文件。独立清理只允许应用程序路线且通过归属／运行引用校验后清除此功能构建产物。后台日志为系统临时目录中的 `JobsDiskSpaceInfoManage.log`，面板另提供本次完整日志。详细参数见 [Scripts 说明](./Scripts/README.md)。

## 三、<span id="sources">源码与验证边界</span>

| 文件 | 职责 |
| --- | --- |
| [DiskSpaceSummary.swift](./Shared/DiskSpaceSummary.swift) | 每次实时采样、文件镜像识别、共享空间去重、格式化与可点击菜单工厂 |
| [FinderSync.swift](./JobsDiskSpaceInfoFinderSync/FinderSync.swift) | 接入三种 Finder 右键上下文，不依赖选中路径 |
| [AppDelegate.swift](./JobsDiskSpaceInfo/AppDelegate.swift) | 校验 UUID 请求并去重，安全转交 Terminal 后退出；安装初始化不清理 |
| [清理脚本](./Scripts/【MacOS】清理磁盘空间.command/README.md) | 完整独立的 Xcode 先行阶段与终端 clean 六类业务，确认后才写入 |
| [ManageExtension.zsh](./Scripts/【MacOS】ManageExtension.zsh/【MacOS】ManageExtension.zsh) | 限定功能范围的安装、卸载和清理 worker |

Bundle ID 为 `com.jobs.diskspaceinfo`，扩展 ID 为 `com.jobs.diskspaceinfo.findersync`。只读检查与隔离验证不执行真实安装／卸载、扩展注册或 Finder 重启；实际菜单显示仍需在管理面板安装／更新后验收。Windows 平行实现见 [Windows 功能目录](../../WindowsOS@Extension/JobsDiskSpaceInfo/README.md)。

双端入口、默认值、生命周期与验证状态见 [磁盘空间信息资产盘点](../../项目相关报告/磁盘空间信息资产盘点.md)。
