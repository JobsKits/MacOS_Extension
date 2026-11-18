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

单一 Dock 身份回归通过 LaunchServices 实际启动临时 App，运行真实 `LaunchManager`、生产 GUI helper 和原生 regular 探针。除核对后台启动壳元数据与 native Bundle 路径／策略外，还断言普通 GUI 的原启动 PID 已退出、面板使用独立 PID 和自己的 `__CFBundleIdentifier`，避免旧 `exec` 继承启动身份而残留两个 Dock 项；仅统计一个 regular 进程不能覆盖这种问题。联合快照的 `JOBS_FINDER_GUI_WAIT=1` 另外核对监督方在面板运行时继续存活、native仍为独立 PID。临时 App 用例结束后精确注销；不把进程／身份检查冒充物理 Dock 交接的目视验收。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、运行与覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

依赖 [**Ruby**](https://www.ruby-lang.org/)、[**Xcode**](https://developer.apple.com/xcode/) 命令行工具和 [**macOS**](https://www.apple.com/macos/) 自带签名工具，不安装依赖。在仓库根目录运行：

```shell
ruby Tests/GUIHostIdentityTests.rb/GUIHostIdentityTests.rb
```

固定宿主为缓存目录内 `Jobs右键菜单管理面板.app`，标识 `com.jobs.finderextensions.managementpanel`，实际执行 `Contents/MacOS/JobsFinderManager`；导出 `JOBS_FINDER_RESPONSIBLE_APP` 供用户在系统设置中识别可授权的 App。内部兼容模式保留同步标准输出及退出码；GUI 模式单独覆盖独立启动、中文／空格 scope、等待标记、转交后返回，以及 LaunchServices 失败码传播。测试同时覆盖外置缓存、真实原生 Bundle 路径、标准 ad-hoc 签名、内容未变不重写、签名失败保留旧 App，以及同名非自有 App 拒绝覆盖。测试不自动授权、不使用管理员命令、不写系统应用程序目录。

<!-- jobs-language-terminal-style-v1 -->

**终端配色保护：** `GUIHostIdentityTests.rb` 直接运行时，在可可靠保存与恢复配色的交互终端中临时使用黑底白字和统一强调色；正常退出、失败及可捕获中断后恢复进入前的配色，保留原业务清理和退出状态。导入本文件不接管终端；无法可靠保护、纯文本模式或无交互终端时按纯文本约定降级。运行中另行修改的颜色会保留并报告冲突，强制终止后可按运行提示使用独立恢复入口。 此实现保留原解释器选项和预载状态；无可用 fork、Windows 或预载多线程时不重启脚本，以纯文本继续。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
