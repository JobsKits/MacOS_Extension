# JobsEnvironmentUpdater Tests

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行命令](#jobs-toc-heading-2)
- [二、范围与限制](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

验证菜单运输、路径和私有快照，不启动真实 Terminal，不执行升级、下载或安装。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行命令 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从工程根目录执行：

```zsh
/usr/bin/ruby Tests/MenuIntegrationTests.rb/MenuIntegrationTests.rb

xcrun swiftc Shared/EnvironmentUpdateRequest.swift \
  Shared/EnvironmentUpdateHost.swift Shared/EnvironmentUpdateContext.swift \
  Shared/EnvironmentUpdateFactories.swift \
  JobsEnvironmentUpdater/EnvironmentUpdateTerminalLauncher.swift \
  Tests/UpdateTransportTests.swift/UpdateTransportTests.swift \
  -o "${TMPDIR:-/tmp}/JobsUpdateTransportTests"
"${TMPDIR:-/tmp}/JobsUpdateTransportTests"
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、范围与限制 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

覆盖严格请求解析、仅桌面空白上下文、Shell／AppleScript安全引用、中文空格和引号路径、私有快照权限、源目录移除后的完整 `_lib` 关系、继承source模式／跳过自述变量清除、无 `-t`、退出码和快照清理、链接资源拒绝。Terminal 请求还核对单次创建、先提交命令再激活、不占用已有窗口和特殊路径的 AppleScript 编译。测试使用无业务的假载荷。真实包内原脚本仅检查帮助、无TTY拒绝与语法；真实升级及 Finder 菜单人工交互另验。

[菜单集成回归](./MenuIntegrationTests.rb/README.md)编译实际 `FinderSync` 源码并创建真实 AppKit 菜单，验证根监控注册、桌面背景与其它菜单类型过滤、普通目录／链接别名和动作绑定。Finder 控制器与运输使用替身，测试不会发起宿主或 Terminal 请求；该结果不能代替真实 Finder 菜单回调与目视验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
