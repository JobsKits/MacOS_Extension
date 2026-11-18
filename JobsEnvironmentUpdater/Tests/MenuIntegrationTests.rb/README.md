# MenuIntegrationTests.rb

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行方式](#jobs-toc-heading-2)
- [二、验证边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

通过 [**Ruby**](https://www.ruby-lang.org/) Minitest 编译实际 Finder 菜单源码，使用真实 [**AppKit**](https://developer.apple.com/documentation/appkit) 菜单对象，只替换 Finder 控制器和宿主运输边界。测试不注册扩展、不打开宿主或 Terminal、不执行升级。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从工程根目录运行，需要 [**Xcode**](https://developer.apple.com/xcode/) 的 `xcrun swiftc` 和系统 Ruby：

```zsh
/usr/bin/ruby Tests/MenuIntegrationTests.rb/MenuIntegrationTests.rb
```

只在系统临时目录写入本次轻量编译和夹具，结束后回收。测试使用源码文件相对路径定位，可从其它工作目录调用本测试的实际路径。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 执行实际 `FinderSync` 初始化，验证 `/` 监控集合与桌面过滤分开承担职责。
- 使用真实菜单与菜单项核对桌面背景入口、标题、动作绑定和无业务副作用；选中项目、侧边栏、工具栏及未知菜单类型不显示。
- 普通目录、同名 `Desktop` 目录、桌面子目录及远程 URL 不显示；缺省桌面目标和指向实际桌面的符号链接别名按生产规则处理，普通目录的别名仍被拒绝。
- 此回归证明菜单提供器和过滤器共同执行的结果；Finder 的跨进程回调路由、沙盒签名及真实桌面显示仍需独立验收，不能以替身控制器通过宣称系统已显示菜单。

完整运输与私有资源快照回归见[上级测试说明](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
