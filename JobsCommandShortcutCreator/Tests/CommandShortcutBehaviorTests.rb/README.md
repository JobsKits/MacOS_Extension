# `CommandShortcutBehaviorTests.rb`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#run)
- [二、结果与边界](#outputs)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

这是[脚本快捷入口隔离测试](../README.md)的运行器。它通过当前项目的相对位置定位生产源码，无须安装 App 或修改 Finder 状态。

## 一、<span id="run">运行方式</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在本目录执行：

```shell
ruby ./CommandShortcutBehaviorTests.rb
```

运行依赖 [**Ruby**](https://www.ruby-lang.org/) 标准库和 [**MacOS**](https://www.apple.com/macos/) 的 `xcrun swiftc`。先将真实语言模块复制到临时目录，仅把偏好域替换为本次 UUID 隔离域；再编译并运行[行为断言](../CommandShortcutBehaviorTests.swift/CommandShortcutBehaviorTests.swift)，最后对真实对话框及其工厂进行类型检查。

## 二、<span id="outputs">结果与边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 编译或断言失败时返回非零退出码，并输出实际诊断；成功时分别显示业务断言通过和对话框类型检查通过。
- 编译目录与运行夹具位于系统临时目录，完成后清理；独立测试偏好域也会删除，不修改实际管理偏好。
- 只执行测试创建的脚本；不注册扩展、不重启 Finder、不运行用户脚本，也不进行真实安装或卸载。
- 不显示真实命名对话框；取消与重试使用注入输入验证，真实鼠标交互与各语言视觉布局需要另行验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
