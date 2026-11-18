# SendTo 网络共享重连回归

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行](#run)
- [二、覆盖与限制](#coverage)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

使用生产重连协调器、模型与 NetFS 请求包装；所有时钟、挂载查询、重挂、界面交付和取消 API 均使用隔离注入，不操作真实网络共享或用户任务。

## 一、<span id="run">运行</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

从功能根目录运行：

```shell
xcrun swiftc -warnings-as-errors Shared/SendToCore/*.swift \
  JobsSendTo/SendToReconnect/*.swift \
  Tests/SendToReconnectTests.swift/SendToReconnectTests.swift \
  -o "${TMPDIR:-/tmp}/JobsSendToReconnectTests"
"${TMPDIR:-/tmp}/JobsSendToReconnectTests"
```

## 二、<span id="coverage">覆盖与限制</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

覆盖明确 errno 分类、混合失败拒绝、无凭据且摘要绑定的共享地址、中文／空格／百分号／IPv6／端口、旧持久证明兼容、系统挂载枚举失败、首次离线挂载失败后真正重挂成功并再验原卷、已有挂载重复恢复的共享八次预算、权限立即停止、同路径替换、超时撤销挂载、挂载与元数据迟到回调、取消后已排队 ready 不再续接、任务／端点去重及旧任务缺重连提示。

NetFS 句柄包装另验证 cancel-before-attach、重复取消、重复完成和已完成后迟到 attach；取消函数注入，不触发真实系统挂载。测试证明的是生产控制流和隔离竞态边界，不能替代真实 [**MacOS**](https://www.apple.com/macos/) 共享认证、断网、重新挂载或 NAS 介质持久性验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
