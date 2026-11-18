# 网络共享重连协调器

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、后台重连与错误边界](#behavior)
- [二、界面接口](#api)
- [三、隔离验证](#verification)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

协调器只续接当前窗口已授权的原任务；不创建另一复制任务，不读取用户连接脚本，不保存用户名、密码或共享凭据。界面接入由上级 `SendToWindowController` 负责，复制和持久状态仍由 `SendToCore.resume` 校验。

## 一、<span id="behavior">后台重连与错误边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `isReconnectable` 只接受具有任务断点、未取消且全部失败均为明确网络 POSIX 错误的网络目标。权限、磁盘满、源变更、清单／校验失败及未知错误不依据诊断文字猜测为断网。
- `start` 对原卷稳定证明做后台读取；卷仍在时交回原任务重新验证。卷缺失时，仅使用持久证明里去凭据、且摘要一致的 SMB／AFP 地址，调用公开 [**NetFS**](https://developer.apple.com/documentation/netfs) 的 `NetFSMountURLAsync`。
- 自动重挂强制 `kNAUIOptionNoUI`，用户名／密码参数均为空；系统既有认证不能满足时停止，保留断点。自动流程不反复唤起文件管理器或登录弹窗；`requestInteractiveConnection` 只供用户显式点击连接入口时调用。
- 新挂载返回成功不等于原卷已恢复，必须再次扫描并匹配稳定卷证明；随后仍只对原任务 ID 调用 `Core.resume`，检查原目标子目录 inode、源基线、暂存 nonce、块数据和锁。
- 单个窗口内同一任务共享最多八次自动尝试，跨“挂载存在→恢复再次网络失败”的自动重入不重置预算。延迟为 1／2／4／8／15／30 秒封顶；已失败的挂载调用还受独立超时约束，不能把纯退避时长当总耗时。只有用户显式再次尝试才调用 `resetRetryBudget`。
- 元数据读取与挂载各有 12 秒 watchdog；挂载超时会取消公开异步请求，继续有界退避。元数据读取超时停止自动流程；系统调用本身可能迟到，generation 检查会丢弃结果。取消、关闭或退出取消定时器／挂载请求，晚到回调不会续传或再重挂。同一进程的同一任务／共享端点不能并行启动另一协调器。
- 旧任务没有原始重连地址时仍能读账本、等待系统手动恢复原挂载，不反向猜测摘要或接管同名共享。

## 二、<span id="api">界面接口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 入口 | 职责 |
| --- | --- |
| `Dependencies.live(openShare:)` | 默认后台 probe、无 UI NetFS 挂载、定时器和主线程事件交付；显式系统连接由宿主注入。 |
| `start(taskID:proof:onState:onReady:)` | 申请当前任务／端点租约，发出 checking／mounting／waiting／ready／stopped。已有活动或预算用完返回 false。 |
| `cancel()` | 立即使本轮 generation 失效，撤销定时器及尚在进行的异步挂载。 |
| `requestInteractiveConnection(proof:completion:)` | 只在无自动活动且用户明确点击时打开经过摘要核验的系统共享地址。 |
| `resetRetryBudget(taskID:)` | 仅无活动时重置该任务自动预算；不能在自动失败回调中调用。 |

`ready` 只表示原卷证明就绪，调用者不得省略 `Core.resume` 的完整校验。界面必须显示当前状态／次数，提供停止和失败后再次尝试入口，不能把 waiting 状态显示成已重连。

## 三、<span id="verification">隔离验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

[重连回归](../../Tests/SendToReconnectTests.swift/README.md)注入时钟、挂载探针、无 UI 挂载和交付队列，不断开／挂载真实 NAS，不复制用户数据。生产 NetFS 适配器实际编译；其请求句柄取消与幂等完成使用注入函数验证，真实服务器认证与重新挂载另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
