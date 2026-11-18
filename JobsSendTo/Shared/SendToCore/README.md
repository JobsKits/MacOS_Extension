# SendToCore · 持久断点复制

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、公开后台接口](#api)
- [二、任务位置、锁与身份](#persistent-layout)
- [三、块检查点与恢复协议](#checkpoint-protocol)
- [四、排他发表、暂停与完成精简](#publication)
- [五、实现与验证边界](#verification)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

公开 `SendToCore.copy` 现使用持久任务引擎，支持进程被强制结束及机器重新启动后，经用户明确选择继续。它不是只保留窗口内的暂停状态。系统同步和硬件／服务器的真实持久化能力有边界，不能承诺死机前最后一个字节绝不重传。

只使用 MacOS 系统 Foundation、Disk Arbitration、CryptoKit 和公开 Darwin API；不扫描局域网、不发现未挂载设备、不自动挂载或处理凭据，不依赖其它仓库、Python、Node 或 Ruby。

## 一、<span id="api">公开后台接口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| API | 行为 |
| --- | --- |
| `volumes()` | 读取已挂载、可写的网络卷及能确认的非内部实体卷；排除 Disk Image／Virtual，不把 NAS 上的 APFS／ASIF 镜像当成实体外盘。 |
| `snapshotSources(_:)` / `canCopy(sources:destination:)` | 只读源快照、目录包含关系和当次对象身份预检；不替代复制时的持久身份和完整性验证。 |
| `copy(sources:destination:cancel:progress:)` | 先建立完整源块基线，再建立持久任务并执行；结果提供 `taskID` 和 `resumeAvailable`。准备阶段尚未写传输数据，若此时中断，需要重新建立快照。 |
| `pendingTasks()` | 列出未完成任务，包含损坏／未知账本的阻塞行；探测原任务锁是否正被占用。不会因为读取失败把任务伪装成空列表。 |
| `resume(taskID:cancel:progress:)` | 校验原任务、卷、源和已持久块后继续；不会按同名卷或文件长度盲接。已完成任务读取小收据，不重新复制。 |
| `discard(taskID:)` | 仅供用户明确选择放弃。先验证整个私有暂存清单，遇到未知内容或身份变化则保留并阻塞；不删除已发表文件。 |

这些接口是同步 worker，均应在后台运行；网络挂载查询、源预哈希和恢复校验可能较慢。`SendToProgress.phase == "preparing"` 表示建立源块校验清单；`copying` 表示实际传输。只报告真实已处理顶层项数和当前路径，不估算字节百分比；数据进度约 100ms 节流，宿主负责线程安全取消标志和主线程界面。

## 二、<span id="persistent-layout">任务位置、锁与身份</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 本机任务位于当前用户 `Application Support/Jobs/JobsSendTo/Transfers/<任务UUID>/`，不使用 TMP 保存恢复依据。任务目录 `0700`、账本 `0600`；保存源路径和校验信息，不保存网络密码、Cookie 或认证令牌。
- 目标卷使用 `.JobsSendTo-<任务UUID>/` 持久私有暂存，含已校验的 task nonce 所有权清单。旧版没有 journal 的临时目录不能自动领养。取消、失败及退出默认保留本机任务和目标暂存，供之后恢复或明确放弃。
- `node-N.json` 是只写一次的每节点源指纹／4 MiB SHA-256 基线；`progress-N.json` 是常量大小的块数和元数据状态；`top-N.json` 保存发表意图／事实。每块不重写整个历史哈希清单或整任务 JSON，避免大文件产生平方写放大。
- 每份账本带版本和内容 SHA 校验封装，临时文件独占创建，文件同步后原子替换并同步父目录；新任务目录的父项也在传输数据写入前同步。损坏、未知版本、越界或含非法路径的清单保留并阻塞。
- 独立 `flock` 文件的 inode 不随账本替换。崩溃由内核释放锁，不凭 PID／时间戳抢锁；列举、恢复、放弃均拒绝 UUID 目录链接，避免在外部目录创建锁或删除数据。
- 跨重挂身份以卷 UUID，或去用户信息后的可信挂载端点摘要及根 fileID，再加任务 nonce 核对；fsid／dev 只作辅助或当次句柄身份，不单独当成跨启动稳定证据。共享／导出路径保留大小写和 `@` 字符。持久证据不足、NAS 重挂后稳定 fileID 不成立时明确阻塞，不接管同名卷。

## 三、<span id="checkpoint-protocol">块检查点与恢复协议</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

1、复制数据前，扫描所选普通文件／目录，记录稳定 fileID、尺寸、mtime、ctime、内部链接文字，并建立每个文件的 4 MiB 源块 SHA-256。阶段可取消、有状态回调；没有写目标数据。源在快照期间发生变化则拒绝开始。

2、逐块重新读取源并核对基线，使用较小写入片段以响应暂停。完整块写入成功后先 `fsync`，再尝试 `F_FULLFSYNC`；数据同步成功后，才原子提交该文件的常量大小进度。同步错误不报告该块已持久。

3、恢复时先校验原卷、源对象及元数据，再从第一块重新验证目标已提交前缀的 SHA。文件长度和已写字节数不是完成证据；尾块不完整、块损坏或多余长尾会回退到第一个无效块，只重传此后内容。源中断期间被编辑／替换时阻塞，不能混合新旧数据。

4、数据完成后用 `fcopyfile(COPYFILE_METADATA)` 处理权限、ACL、时间和扩展属性。数据与元数据完成分别记账；元数据已施加但状态尚未落盘的中断可继续，包含 `0400` 文件和 `0500` 目录。只对已验私有暂存调整恢复所需权限，源权限不改变。系统错误回调立即 QUIT 并保留 errno，不在 ENOSPC／I/O／元数据失败时无限重写。

5、目录按节点记账，已完成子项不重传。内部符号链接只复制链接文字，不打开或遍历其目标；末级所选链接、特殊节点和嵌套挂载点拒绝。源／目标通过 no-follow 句柄和真实祖先核验，不能复制目录到自己或内部。

正常情况下最多重传尚未落稳的块；若硬件、NAS 或存储服务未兑现同步语义，恢复哈希会回退到首个损坏块或明确阻塞，不能保证所有已确认字节仍存在。`F_FULLFSYNC` 不支持时保留已完成的 `fsync` 能力说明；网络服务器应答不等于其物理介质已经抗断电落盘。

## 四、<span id="publication">排他发表、暂停与完成精简</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 内容验证后先持久保存 `pending` 发表意图：最终候选名、暂存 fileID、任务归属信息，再 `renameatx_np(RENAME_EXCL)`；目标父目录同步后保存 `published`。同名始终保留两份、不覆盖、不合并目录；重启后新出现的同名项也受排他操作保护。
- 崩溃落在 rename 成功而 journal 未提交之间时，恢复必须用原卷／nonce、记录的对象 fileID 和完整内容证明最终对象属于本任务，再补记事实。能写入时会在顶层副本使用任务 nonce 扩展属性辅助归属；不支持该属性时仍必须匹配稳定 fileID，不能只凭同名同内容领养。证据不足就阻塞，不另造重复副本。
- `0500` 目录跨父级发表所需的临时 owner-write 先记持久原权限；正常发表与中断恢复均精确还原，再提交完成事实。已发表文件不因后续暂停或失败回滚。多个源不是一个跨文件原子事务。
- 完成收据和 `completed` 状态持久成功后，自动移除已验证的空目标暂存、精简本机大 node／progress／top 账本，只留小型 `task.json`、`receipt.json` 和同一 `lock`。精简失败单列诊断并保留现场，不把已经完成的复制改成未完成。
- 明确放弃只清理身份匹配、账本已知的私有数据；存在用户新放入的未知内容会先阻塞并全部保留。为防 split-lock，最后保留小型 `discarded` 禁用收据和原 lock inode；不会删除或重新拷贝已发表文件。未完成的大账本随任务留存，位置和任务 ID 可核对，不是隐形 TMP 垃圾。

## 五、<span id="verification">实现与验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

当前生产实现为 `SendToPersistentEngine`、`SendToPersistentPlanner`、`SendToPersistentIO` 和持久模型；`SendToCore` 为公开门面。`SendToCopySession` 保留历史兼容组件测试及命名辅助，不是公开 copy 的执行路径。

当前生产路径、历史组件及独立真实子进程强杀测试的命令和边界见 [核心测试](../../Tests/SendToCoreTests.swift/README.md)与[崩溃恢复测试](../../Tests/SendToResumeCrashTests.swift/README.md)。所有任务存储和传输数据测试显式使用本轮独占系统临时目录，不写用户真实 Application Support，不重启真实机器，不写外接盘或 NAS。真实挂载枚举只有只读采样。

没有用真实磁盘填满或真实网络断连造故障。exFAT／FAT、SMB／AFP 的数据同步、元数据和排他 rename 仍须对应目标另验；不支持的系统能力如实失败并保留断点，不降级为可能覆盖或缺元数据的成功。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
