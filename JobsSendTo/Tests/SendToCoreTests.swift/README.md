# SendTo 核心生产路径与历史组件验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、当前生产路径](#production)
- [二、历史兼容组件](#legacy)
- [三、副作用与平台范围](#scope)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

当前公开 `SendToCore.copy/resume` 已使用持久引擎。`SendToPersistentCoreTests.swift` 直接验证同一生产 engine，只把本轮唯一临时目录作为隔离候选卷，并显式传入独占临时 `storeRoot`；不写用户真实 Application Support、外接盘、NAS 或旧任务。

## 一、<span id="production">当前生产路径</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在 `MacOS@Extension/JobsSendTo` 功能目录运行：

```shell
xcrun swiftc -warnings-as-errors Shared/SendToCore/*.swift \
  Tests/SendToCoreTests.swift/SendToPersistentCoreTests.swift \
  -o "${TMPDIR:-/tmp}/jobs-sendto-persistent-core-tests"
"${TMPDIR:-/tmp}/jobs-sendto-persistent-core-tests"
```

覆盖持久文件／目录冲突、内部链接不遍历、源原件和既有目标保留、源预哈希阶段、4 MiB 块暂停与保留、已提交坏块及伪长尾的校验回退、保留有效首块、源编辑阻塞、损坏 journal 阻塞行、未知暂存数据拒绝放弃、明确放弃的原 lock inode 保全、完成小收据精简和不重复拷贝、UUID 目录链接不在外部创建锁／删除外部数据。

同时验证卷根与子目录身份分开保存、子目录暂停后由新引擎续传、同名原文件保留、目录替换／链接及不完整卷根锚点拒绝、稳定卷移动挂载路径后恢复原相对目录，以及旧四字段根任务兼容。重复发送匹配完整源集合、稳定卷与目录锚点；源变化给出禁继续诊断。没有当前挂载目标时仍发现原任务，允许明确的继续或等待重连后从头意图；已挂载但权限受限与真正缺挂载的网络 errno 分开，权限故障不触发自动重挂。

进程强杀并新 exec 恢复、元数据／发表崩溃窗口、互斥等由[独立故障注入测试](../SendToResumeCrashTests.swift/README.md)验证。只终止测试自己创建的 worker，不重启机器或操作真实设备。

## 二、<span id="legacy">历史兼容组件</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
xcrun swiftc -warnings-as-errors Shared/SendToCore/*.swift \
  Tests/SendToCoreTests.swift/SendToCoreTests.swift \
  -o "${TMPDIR:-/tmp}/jobs-sendto-legacy-core-tests"
"${TMPDIR:-/tmp}/jobs-sendto-legacy-core-tests"
```

原测试保留普通文件／目录、属性、权限、链接、句柄安全及系统 copyfile 错误分类等历史组件覆盖。其直接构造 `SendToCopySession` 的取消清理合同属于旧组件，不是当前公开 API 的暂停／断点留存语义；通过这些历史测试不能替代持久引擎和崩溃恢复验收。

## 三、<span id="scope">副作用与平台范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

编译仅需 MacOS 系统 SDK 和 Swift；文件读写、权限调整、损坏块、用户新文件、坏清单与清理均限本轮新建独占临时目录。测试不安装扩展，不执行所复制的程序，不挂载或认证设备，不把进程 SIGKILL 当成已实际测试硬件断电。真实网络／外接盘的同步应答和文件系统能力另行验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
