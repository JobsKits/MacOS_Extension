# <span id="前言">管理面板原生宿主身份隔离验证</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、运行与覆盖](#jobs-toc-heading-1)

</details>
<!-- jobs-toc:end -->

---

> [GUIHostIdentityTests.rb](./GUIHostIdentityTests.rb) 使用临时原生命令行程序代替面板，检查缓存 App 的固定身份、标准签名、真实执行路径和授权宿主环境。不会打开真实面板、安装扩展或修改隐私授权。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、运行与覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

依赖 [**Ruby**](https://www.ruby-lang.org/)、[**Xcode**](https://developer.apple.com/xcode/) 命令行工具和 [**macOS**](https://www.apple.com/macos/) 自带签名工具，不安装依赖。在仓库根目录运行：

```shell
ruby Tests/GUIHostIdentityTests.rb/GUIHostIdentityTests.rb
```

固定宿主为缓存目录内 `Jobs右键菜单管理面板.app`，标识 `com.jobs.finderextensions.managementpanel`，实际执行 `Contents/MacOS/JobsFinderManager`；导出 `JOBS_FINDER_RESPONSIBLE_APP` 供用户在系统设置中识别可授权的 App。测试覆盖外置缓存、原参数 / 标准输出、真实原生 Bundle 路径、标准 ad-hoc 签名、内容未变不重写、签名失败保留旧 App，以及同名非自有 App 拒绝覆盖。测试不自动授权、不使用管理员命令、不写系统应用程序目录。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
