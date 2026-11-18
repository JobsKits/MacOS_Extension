# SendTo 独立进程崩溃恢复验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行](#run)
- [二、故障点与保护验证](#coverage)
- [三、验证边界](#limits)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

对 [**MacOS**](https://www.apple.com/macos/) 生产持久复制引擎执行真正的进程崩溃回归：独立 worker 到达指定阶段后 `SIGSTOP`，父进程确认故障点并发送 `SIGKILL`，再启动全新 worker 恢复同一个任务。不会重启机器、挂载磁盘或写入真实外部设备。

## 一、<span id="run">运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在 `JobsSendTo` 根目录运行：

```shell
xcrun swiftc Shared/SendToCore/*.swift \
  Tests/SendToResumeCrashTests.swift/SendToResumeCrashTests.swift \
  -o "${TMPDIR:-/tmp}/JobsSendToResumeCrashTests"
"${TMPDIR:-/tmp}/JobsSendToResumeCrashTests"
```

需要 [**Xcode**](https://developer.apple.com/xcode/) 命令行工具、[**Swift**](https://www.swift.org/) 与当前系统 SDK。每个场景在唯一的 `JobsSendToResumeCrash-*` 临时目录建立源件、目的地、账本、事件记录及子进程日志，结束后只清理这些夹具。worker 的 `--worker` 参数由测试自身使用，无需手工启动。

## 二、<span id="coverage">故障点与保护验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 在块中途、已耐久 checkpoint、发表意图落盘及 rename 成功但最终状态尚未提交处强杀；新进程恢复后逐文件 SHA-256 必须一致，不重复生成同名副本。已发表内容被修改时保留并阻塞；已发表事实完好而源件后来删除时仍可补记，不重造源件或目标副本。
- 验证已耐久前缀不从零重写、未记账尾部不被当作进度，目录中已经完成的子文件不重复传输。
- 分别在 `0400` 文件及 `0500` 目录的元数据已施加但完成标记尚未落盘时强杀；另覆盖只读目录为 rename 临时授写后强杀、只读 stage 发生坏块后回退修复。恢复成功后源权限及最终目标权限必须保持原值。
- 以有效 SHA envelope 的测试账本改变旧挂载期 dev／fsid，保留稳定卷证明、nonce、inode 和内容基线，验证恢复不依赖旧挂载编号。这是重新挂载逻辑夹具，不是实际卸载或重新挂载设备。
- 源修改、目标目录替换、损坏块、损坏任务清单、校验正确但包含越界路径的节点计划必须安全处理；坏任务应保留为带诊断的阻塞项。
- 未知 stage 内容、改变的 owner nonce、旧无 journal 目录不能被领养或删除；显式放弃只清理已证明归属的临时数据，保留源件、无关数据及用于防重复接管的小禁用收据与同一锁对象。
- 另一个 worker 持锁时不能并发接管；强杀原 worker 后由操作系统释放锁，无需删除锁文件或按 PID 抢占。默认取消保留未完任务，之后可继续。

## 三、<span id="limits">验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

测试只把候选卷发现替换为本轮临时目的地，其余生产块读取／写入、hash 验证、journal 同步、nonce、身份、锁和排他发表流程均真实执行。当前系统卷的 UUID 证明仍按生产方法读取；不使用真实外盘或网络共享造故障。

`SIGKILL` 保留内核页缓存，证明的是进程崩溃恢复，不能单凭此宣称真实断电、整机崩溃或 NAS 硬件持久性已经验收。数据同步先于 checkpoint、journal 原子替换及目录同步的顺序须结合生产源码审阅；SMB／AFP、掉盘、服务器断电和不同文件系统能力另行验证。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
