# JobsSendTo 发送到外部磁盘或网络卷

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、使用与复制边界](#usage)
- [二、重启后的任务恢复](#recovery)
- [三、设备列表、语言与主题](#interface)
- [四、独立安装与卸载](#management)
- [五、源码、工程与成品](#source)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

在 [**MacOS Finder**](https://support.apple.com/guide/mac-help/welcome/mac) 选中文件或文件夹，右键打开 **“📨 发送到”**，再点已挂载的 U 盘、移动硬盘或时间胶囊共享卷，即开始复制。支持单选及多选；保留源件，同名自动编号为另一份，不覆盖目的地已有项目。Windows 使用系统自带“发送到”，本功能仅提供 MacOS 工程。

没有设备时，子菜单提供明确空态和“重新扫描并选择…”入口。先插入外部磁盘，或在 Finder 手动连接共享卷，再重新扫描；不自动寻找局域网设备、不代填账号、不自动挂载。首次后台扫描期间需关闭再重开子菜单；也可直接打开选择窗口等待扫描结果。

## 一、<span id="usage">使用与复制边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 只列已经挂载且可写的外部／可移除磁盘或网络卷。内部／系统卷、只读卷及本地磁盘镜像不冒充外接实体磁盘；NAS 上的本地 ASIF／APFS 镜像同样不列为外设。时间胶囊列的是它已挂载的共享根目录。
- 每次操作复制到目标卷根目录；最多128项、编码 URL 总长不超过64 KiB。普通文件和文件夹支持多选；顶层符号链接、特殊设备、重复路径和源对象已替换等情况拒绝。文件夹内部链接按链接本身复制，不跟随进入其它目录。
- 已在目标根目录的对象、源目录自身或内部目的地等危险／无效关系不执行。菜单先做无 I/O 的路径筛选；宿主后台重新枚举真实可写候选、核对卷路径与身份，核心再做源／目标身份及目录祖先检查。
- 复制在后台执行，窗口区分“校验源数据／准备断点”和实际复制，显示当前路径及已处理项目计数。没有准确总字节数时使用活动指示，不伪造百分比；完成后分别显示成功、失败和停止结果。源件不移动、不删除。
- 大文件可中途暂停，默认保留已完成副本、未发布临时数据和可用断点；暂停不再删除续传数据。磁盘拔出、网络中断、权限或空间不足会保留真实失败原因及任务，不自动重新复制已成功项目。
- 文件在其复制读取期间被编辑或替换会使该项失败；整个目录不是同一瞬间的原子快照，需要一致备份时应先停止修改源件。
- 关闭正在复制的窗口会先请求暂停，等断点保存后关闭；请求退出会等待本会话任务暂停落盘后退出。已经明确开始的放弃清理会等待安全收尾。不新增后台服务或开机启动，未完成任务不会随关窗删除。

## 二、<span id="recovery">重启后的任务恢复</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

死机或进程退出后，重新挂载原来的设备／共享卷，再手动打开 `JobsSendTo.app`。App 从本机持久记录读取“未完成任务”，默认空选、不自动恢复。列表显示任务状态、已完成数、更新时间；选中后可查看原目标、源路径及诊断，点击“继续原任务”按原任务 ID 续接，不依赖旧右键 URL 或上次进程内存。

- 本机任务目录从当前用户 Application Support 动态解析，默认为 `~/Library/Application Support/Jobs/JobsSendTo/Transfers`；账本与块校验数据在本机，未发布的数据留在原目标卷本任务的私有目录。不能删除或移动这些恢复资料后还期待继续。
- 已确认完成的项目不重新复制；大文件只继续未确认完成的块，继续前校验已保存前缀、源基线、目标卷稳定身份、任务 nonce 与临时对象归属。未记账的尾部不冒充已完成进度。
- 新任务先读取源数据建立块校验基线，大文件可能需要较长准备时间，窗口会明确显示该阶段；准备阶段停止且尚未建立任务时，不会虚称存在可恢复断点。
- “刷新任务列表”重读本机记录；“重扫已挂载目标”只发现当前挂载卷，继续时仍核验原目标，不能把同名设备当原设备，也不会静默改成从零的新任务。
- 源或目标变更、断点损坏、缺少归属依据等会阻止续接并保留记录，按诊断修复后再继续。损坏任务显示为待处理／读取失败，不能当作无任务。另一个窗口或进程持有本任务锁时，继续和放弃均禁用，核心再次核验跨进程锁。
- 只有明确选择 **“放弃并清理临时数据”**，并在默认取消的范围对话框中再次确认，才清除本任务可证明归属的未发布临时数据并从未完成列表移除；保留少量停用收据与原任务锁记录，防止旧任务重复接管，源件和已完成副本保留。归属未知、目标变更或核验失败时停止并报告，不扩大清理范围。
- 旧版中断若没有本机持久账本，不能自动领养旧临时目录或凭同名文件推算断点；它们不会出现在可恢复任务列表，也不会被本功能顺手删除。这里的持久恢复适用于新版建立的任务。

此设计提供持久断点和崩溃后的重新校验；真实整机断电、设备损坏和 NAS 服务器介质持久性仍受系统及服务端能力影响。隔离进程强杀测试不能代替目标设备断电验收，具体实现与限制见[复制核心说明](./Shared/SendToCore/README.md)及[崩溃测试](./Tests/SendToResumeCrashTests.swift/README.md)。

## 三、<span id="interface">设备列表、语言与主题</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

卷扫描及源快照都在后台，Finder 菜单回调使用内存快照，不等待慢 Wi-Fi 共享的元数据请求。挂载／卸载事件和15秒缓存期限触发后台刷新；扫描失败与没有设备分别提示。子菜单已经打开时不会伪称实时插入新设备，请关闭重开，或进入选择窗口点击重新扫描。缓存中的卷或源文件若随后被替换，实际复制会拒绝；重新扫描可取得新快照。

复制窗口具备完整空态说明和重新扫描按钮；没有合适目的地或没有源件时禁用新复制。直接打开 App 进入恢复中心；没有未完成任务时显示完整空态、刷新入口及通过 Finder 发起新复制的说明，不自动复制。原进度窗口也提供“未完成任务”入口。

业务窗口和管理面板共用当前用户的语言／主题偏好：简体中文、繁体中文、藏文、英文、日文、法文、西班牙文、德文、俄罗斯文、韩文与跟随系统；白天、黑夜、跟随系统。切换保留任务、当前选择、进度和结果。真实路径、卷名及系统错误诊断保留原文；结果区域可选中复制并使用 `⌘A`／`⌘C`。

## 四、<span id="management">独立安装与卸载</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

双击 [公开管理入口](./【MacOS】管理发送到Finder扩展.command)或同名 App，也可从[平台总面板](../README.md)选择“发送到外部磁盘或网络卷”。功能 ID 为 `send-to`，独立宿主 `JobsSendTo.app`，扩展 `com.jobs.sendto.findersync`；两种入口都只管理本端这一安装单元。

依赖 MacOS 12+、完整 [**Xcode**](https://developer.apple.com/xcode/) 和 MacOS SDK。管理面板默认空选，点击安装／更新或卸载后才执行；空选和取消不改变系统。默认勾选应用程序路线和安装成功后构建清理，可手动取消。应用程序路线将模块装入 `/Applications/Jobs自定义右键菜单.app`；构建路线保留本包 `work/DerivedData/Build/Products/Debug/JobsSendTo.app`。

卸载仅移除所选位置的本模块，保留全部源件、已复制内容、未完任务记录、其它菜单和源码；不卸载磁盘、不退出共享账户。任务清理仅通过上述显式放弃入口，不由安装／卸载代做。日志位于系统临时目录 `JobsSendToManage.log`，管理面板另保留完整会话日志。管理源码、安装事务和路径说明见 [Scripts](./Scripts/README.md)。

## 五、<span id="source">源码、工程与成品</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 位置 | 职责 |
| --- | --- |
| [JobsSendTo.xcodeproj](./JobsSendTo.xcodeproj/) | 可编辑／编译／运行的宿主与 FinderSync targets，共享 Scheme `JobsSendTo` |
| `JobsSendTo/` | URL 队列、十语言进度／暂停窗口、恢复任务中心、真实结果与当前用户偏好 |
| `JobsSendToFinderSync/` | 实际 principal 提供全部子菜单 selector，tag 绑定原请求与异步缓存 |
| `Shared/SendToCore/` | 卷候选、持久账本、源块基线、检查点、跨进程锁、恢复、显式放弃及排他发布 |
| `Shared/SendToRequest/` | URL 字段白名单、数量／长度边界、源／卷身份运输 |
| [Scripts](./Scripts/README.md) | 完整可修改管理界面源码、构建、安装／卸载与联合事务 |
| [Tests](./Tests/README.md) | 临时夹具核心验证及真实 principal selector／运输回归 |
| [当前宿主 App 成品](./work/ReconnectDestination-20261118/DerivedData/Build/Products/Debug/JobsSendTo.app/) | 当前已验双架构 Debug App，内嵌 FinderSync；已安装版本与实际菜单状态见[中央资产盘点](../../项目相关报告/发送到设备资产盘点.md#current-destination-reconnect) |

```shell
xcodebuild -project ./JobsSendTo.xcodeproj -scheme JobsSendTo \
  -configuration Debug -derivedDataPath ./work/DerivedData \
  ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' build
```

包整体复制时保留工程、源码、App 和 Scripts，相对路径由实际包位置解析。Xcode 编译可能自动登记临时产物；正式使用请通过管理面板安装／更新并核验精确启用路径。源码验证、目标 App 构建、系统登记、真实右键交互和真实设备传输分别记账，不互相代替。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
