# JobsPermanentDeleter 永久删除所选项目

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

在 [**MacOS**](https://www.apple.com/macos/) Finder 选中文件／文件夹，右键选择 **“🗑️ 永久删除（不经过回收站）”**。支持多选及文件／文件夹混选。二次确认框列出完整路径，**左侧“确认”红底白字，右侧“取消”蓝底白字**。默认取消，回车、Esc 或关闭窗口均取消；只有明确点击确认才执行。文件夹递归删除，不能通过回收站恢复。

## 一、<span id="behavior">行为与保护</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

- 只接收当前菜单的不可变选择快照，最多128项，URL 载荷最多32 KiB。不查询点击后的新选择；重叠父子选择、根目录、当前用户根目录、关键系统目录和卷根目录被拒绝。空白／虚拟位置不显示；包含无效对象时整项禁用。
- 普通文件直接删除，文件夹包含全部后代。符号链接只删除链接自身，不穿透到链接目标。特殊设备／FIFO 不支持；递归遇到不支持项、权限错误或挂载边界时停止该项，汇总错误。遵守原权限，不提权、不修改 TCC 或清除文件保护属性。
- 菜单生成时记录根目标及父目录的设备号／inode／类型。确认后重新核对，以逐级 `O_NOFOLLOW` 打开父目录，再将根目标移到同父目录新建的0700私有暂存目录，复核身份后才遍历删除。暂存不属于回收站，不承诺恢复；普通失败尽力以无覆盖方式把剩余内容还原原位，原名被占用则明确报告剩余内容的完整暂存路径及可能部分删除的事实。
- 删除并非事务或备份，已删除内容无法由本工具恢复。递归期间仍被其它程序写入、同用户恶意并发替换、进程强制终止或断电不提供原子恢复保证；不要在其它程序正在修改目标时使用。文件系统本身的错误保留原文，便于核查。
- 删除在后台执行，进度窗口等待真实结果；过程中退出请求被拦截，结果窗口分别汇总成功项和失败路径。请求队列对同次 UUID 去重，空闲约一秒退出，不新增常驻服务。
- 确认框完整支持简体中文、繁体中文、藏文、英文、日文、法文、西班牙文、德文、俄罗斯文、韩文及跟随系统；主题提供白天／黑夜／跟随系统。共用管理面板的当前用户偏好，切换只重建确认框，不执行删除。

## 二、<span id="management">安装与卸载</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

打开 [管理入口](./【MacOS】管理永久删除所选项目Finder扩展.command)或同名 App，或在 [平台总面板](../README.md)“文件与通用工具”选择“永久删除所选项目”。功能 ID 为 `permanent-delete`，独立工程、宿主及 FinderSync 不依赖其它功能业务。默认空选，取消／空选不执行；管理按钮是安装／卸载确认，右键删除另有上述二次确认。

依赖 MacOS 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 与 MacOS SDK。默认应用程序路线装入 `/Applications/Jobs自定义右键菜单.app` 的独立模块，并可安装后清理本轮构建产物；构建路线保留本包 `work/DerivedData/Build/Products/Debug/JobsPermanentDeleter.app`。宿主 ID 为 `com.jobs.permanentdeleter`，扩展 ID 为 `com.jobs.permanentdeleter.findersync`。安装／卸载只管理本模块，不删除业务文件，不更改其它菜单。

包可整体复制／改名，从任意工作目录运行；保留工程、App、Scripts 及资源。管理日志为系统临时目录的 `JobsPermanentDeleterManage.log`，面板保留独立完整日志。管理面板空闲关闭可退后台或退出；执行中关闭继续后台完成，可从状态栏恢复。

## 三、<span id="source-build">源码、构建与成品</span> <a href="#前言">🔼</a> <a href="#🔚">🔽</a>

| 入口 | 职责 |
| --- | --- |
| [JobsPermanentDeleter.xcodeproj](./JobsPermanentDeleter.xcodeproj/) | 可编辑／构建的宿主和 FinderSync targets，共享 Scheme `JobsPermanentDeleter` |
| `JobsPermanentDeleter/` | 请求队列、二次确认框、删除服务和结果汇总 |
| `JobsPermanentDeleterFinderSync/` | 所选项菜单、选择快照与精确宿主投递 |
| `Shared/` | 对象身份、URL 编码、十语言和系统 API 工厂 |
| [Scripts](./Scripts/README.md) | 完整管理面板、安装／卸载及联合 App 事务源码 |
| [Tests](./Tests/README.md) | 隔离删除、替换保护、原生确认框及后台完成回归 |
| [已构建宿主](./work/DerivedData/Build/Products/Debug/JobsPermanentDeleter.app/) | 当前源码的 arm64／x86_64 双架构 Debug 成品，内嵌 FinderSync；未安装 |

```shell
xcodebuild -project ./JobsPermanentDeleter.xcodeproj -scheme JobsPermanentDeleter \
  -configuration Debug -derivedDataPath ./work/DerivedData \
  ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' build
```

管理 App 启动壳与 `Scripts/ManagementPanel.swift`、原生编译入口及完整资源共同构成可运行管理包。确认框的[临时夹具预览](./work/ConfirmationPreview.png)仅用于检查布局，不代表真实文件被选中或删除。构建回执为 `work/BuildReceipt.json`。最终验证和成品摘要以中央 [资产盘点](../../项目相关报告/永久删除资产盘点.md)为准；真实安装、Finder 菜单显示和点击单独验收，不以构建或隔离测试冒充。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
