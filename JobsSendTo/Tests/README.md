# JobsSendTo 隔离验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、验证入口](#tests)
- [二、验收边界](#limits)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

验证仅在系统临时目录建立自有夹具，或为请求测试使用不可执行的合成卷快照；不复制用户文件、不注册菜单、不挂载共享、不操作真实移动盘。具体断言数以当次输出及项目资产盘点为准。

## 一、<span id="tests">验证入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

| 测试 | 范围 |
| --- | --- |
| [SendToCoreTests.swift](./SendToCoreTests.swift/README.md) | 卷筛选、身份、安全关系、文件／目录复制、重名保留、链接、取消与失败 |
| [SendToTransportTests.swift](./SendToTransportTests.swift/README.md) | 特殊路径、strict请求、数量／长度边界、真实 principal 的 selector／tag运输 |
| [SendToResumeCrashTests.swift](./SendToResumeCrashTests.swift/README.md) | 真实 worker 强杀、新进程按同任务恢复、块／清单损坏、锁、替换与显式放弃边界 |
| [SendToRecoveryInterfaceTests.swift](./SendToRecoveryInterfaceTests.swift/README.md) | 原生恢复任务表、默认空选、busy保护、语言保留任务ID、继续／放弃／暂停关窗；存储与复制使用独占替身 |
| [SendToReconnectTests.swift](./SendToReconnectTests.swift/README.md) | 网络 errno、原卷证明、无 UI 后台重挂、八次预算、超时取消、迟到回调、请求去重与旧任务兼容；全部挂载与时钟隔离 |

各子目录 README 提供实际编译命令及副作用边界；从本功能根目录执行，保留对应核心源码。测试工具链需要系统 Swift 编译器及当前 MacOS SDK。

## 二、<span id="limits">验收边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

隔离夹具与模拟卷策略不代表真实 Time Capsule／慢 Wi-Fi／外接文件系统、掉盘时序或用户 Finder 点击已经验收。GUI 的空源只读预览不能证明数据复制通过；真实用户数据传输须单独取得明确目标与范围。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
