# 四包 Finder principal 菜单动作验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行](#jobs-toc-heading-2)
- [二、覆盖与边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

验证 [**MacOS**](https://www.apple.com/macos/) [**Finder Sync**](https://developer.apple.com/documentation/findersync) 将复制菜单项的 action 发送给扩展 principal 后，能实际进入联合背景菜单的宿主运输。覆盖 JobsFileCreator、JobsDesktopTools、JobsEnvironmentUpdater 和 JobsDiskSpaceInfo，防止仅直接调用协调器的测试掩盖 principal 缺少 selector 的问题。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从 `MacOS@Extension` 运行：

```shell
ruby Tests/OrderedDesktopPrincipalTests.rb/OrderedDesktopPrincipalTests.rb
```

需要系统 [**Ruby**](https://www.ruby-lang.org/)、Minitest、[**Xcode**](https://developer.apple.com/xcode/) 命令行工具、AppKit 与 FinderSync SDK。每包使用独立临时目录，完整生产 `FinderSync.swift` 与本包共享源码一起编译；同文件测试 extension 只允许注入协调器，不替换生产 selector 或转发逻辑。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、覆盖与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 调用真实 principal 的 `menu(for:)`，菜单 target 必须为该 principal。
- 复制 `NSMenuItem` 后清除 target 和 representedObject，检查 `responds(to:)`，再由 `NSApplication.sendAction` 分发 action。
- 检查所有返回动作仅运输一次；磁盘入口必须生成 `jobsdiskspaceinfo://clean?id=UUID` 并投递给准确的 JobsDiskSpaceInfo 宿主路径。
- 重复票据不能再次启动业务；多种安装者优先级分别让四包担任唯一菜单输出者。
- 只读 Finder 上下文，宿主运输全部使用替身；不注册扩展、不发送真实 AppleEvents、不启动 Terminal、不运行 clean 或其它业务脚本。Finder 实际跨进程复制和已安装菜单仍由单独的目标桌面验收确认。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
