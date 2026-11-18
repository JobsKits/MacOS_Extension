# JobsFileVisibility 所选项目隐藏／显示

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、行为与边界](#behavior)
- [二、独立安装与卸载](#management)
- [三、源码、构建与成品](#source-build)
- [四、验证范围](#validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

在 [**MacOS**](https://www.apple.com/macos/) 的 Finder 中选中文件或文件夹，右键使用 **“🙈 隐藏所选项目”** 或 **“👁️ 显示所选项目”**。支持单选及文件／文件夹混合多选，两项都是明确动作，重复执行不会反转状态。

点击后立即处理；成功不额外弹窗，失败按所选项汇总。只修改所选对象自身的 `UF_HIDDEN` 属性，不递归、不改名、不改变全局隐藏文件显示偏好。需要找回隐藏的项目时，可先用 Finder 的 `⌘⇧.` 显示隐藏项目，再选中并清除其隐藏属性。

## 一、<span id="behavior">行为与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 菜单支持普通文件、文件夹及侧边栏中的真实文件夹；背景与虚拟位置不显示。最多128项，安全 URL 编码后不超过32 KiB；无法读取、符号链接、FIFO 等特殊对象不能执行。混合选择包含无效项时菜单禁用，不悄悄缩小选择范围。
- “显示”表示清除隐藏属性。点开头名称、`.hidden` 列表或其它 Finder 规则仍可能影响最终可见性；不自动改名、不修改这些规则。点名称清除属性后会说明此限制。
- 右键时保存路径、设备号、inode 及类型快照，点击沿用该次选择。宿主以 `O_EVTONLY | O_NOFOLLOW` 打开句柄，复核身份后仅增减 `UF_HIDDEN`，保留其它 flags、内容和权限；末级路径被替换为链接时不会跟随。修改后读回验证并通知 Finder 刷新父目录。
- 单项失败继续处理其它项，汇总真实成功数与失败路径；已经成功的项不会因其它项失败而反向修改。遵守系统权限，不提权、不修改 TCC 或文件权限。只读0400文件可处理；无读取权限000文件无法取得安全句柄时报告失败，保留原属性。
- 异常／限制说明窗口可切换简体中文、繁体中文、藏文、英文、日文、法文、西班牙文、德文、俄罗斯文、韩文与跟随系统，并提供白天／黑夜／跟随系统主题。与现有管理面板共用当前用户偏好；切换保留结果并重建翻译。宿主处理 URL 队列、去重同次点击，空闲约一秒退出，不新增常驻服务。

## 二、<span id="management">独立安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

双击 [管理入口](./【MacOS】管理所选项目隐藏显示Finder扩展.command)或同名 App；也可在 [平台总面板](../README.md) 的“文件与通用工具”选择“隐藏 / 显示所选项目”。独立功能 ID 为 `file-visibility`，两项菜单共同属于这一安装单元。默认空选，取消或空选不执行；安装与卸载按钮是本轮管理操作的确认。

依赖 MacOS 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 与 MacOS SDK。包可整体复制改名后从任意工作目录运行，保留 App、Scripts 及工程；运行时不依赖旧源码路径。构建、签名、精确登记、两条安装路线和异常恢复均沿用现行管理事务：

- 默认勾选应用程序路线及安装后构建清理，可手动取消。应用程序路线将模块装入 `/Applications/Jobs自定义右键菜单.app`；构建路线保留本包 `work/DerivedData/Build/Products/Debug/JobsFileVisibility.app`。
- 宿主 ID 为 `com.jobs.filevisibility`，Finder 扩展 ID 为 `com.jobs.filevisibility.findersync`。安装只注册本功能，不修改任何业务文件；卸载只移除所选位置的本模块，保留文件隐藏属性、源码和其它菜单。
- 管理日志位于系统临时目录的 `JobsFileVisibilityManage.log`，面板另保留本次完整日志。空闲关闭可后台或退出；任务中关闭会继续执行并可从状态栏恢复。已打开的旧面板不热更新源码。

## 三、<span id="source-build">源码、构建与成品</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 入口 | 职责 |
| --- | --- |
| [JobsFileVisibility.xcodeproj](./JobsFileVisibility.xcodeproj/) | 可编辑／构建的宿主和 FinderSync targets，共享 Scheme `JobsFileVisibility` |
| `JobsFileVisibility/` | 请求队列、属性变更、错误汇总及多语言说明窗口 |
| `JobsFileVisibilityFinderSync/` | 文件／文件夹多选菜单、快照与精确宿主投递 |
| `Shared/` | 对象身份、URL 编码、十语言和系统 API 工厂 |
| [Scripts](./Scripts/README.md) | 管理面板完整源码、安装／卸载及联合 App 事务 |
| [Tests](./Tests/README.md) | 隔离真实属性、传参和失败保护验证 |
| [已构建宿主 App](./work/DerivedData/Build/Products/Debug/JobsFileVisibility.app/) | 本轮 Debug 成品，内嵌 FinderSync，arm64／x86_64 双架构；尚未安装 |

```shell
xcodebuild -project ./JobsFileVisibility.xcodeproj -scheme JobsFileVisibility \
  -configuration Debug -derivedDataPath ./work/DerivedData \
  ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' build
```

构建本身可能由 Xcode 自动产生系统登记。正式使用应通过管理面板执行安装／更新，不以编译成功代替精确启用和菜单验收。

## 四、<span id="validation">验证范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

隔离属性验证通过，涵盖文件／文件夹、多选请求、特殊路径、重复动作、不递归、保留正文／权限／其它flags、只读与权限失败、点文件不改名、链接与替换目标保护。双架构宿主与扩展构建、严格深度签名、脚本语法及管理映射验证通过；构建产生的精确临时路径登记已撤销，未启用此菜单、未改真实用户文件、未重启 Finder。真实右键显示和点击仍需安装后另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
