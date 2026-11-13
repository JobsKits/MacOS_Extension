# <span id="前言">单包部署位置隔离验证</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

暂无章节。

</details>
<!-- jobs-toc:end -->

---

> 运行 `ruby PackageInstallLocationTests.rb`，验证默认构建目录与应用程序目录的参数、缺失副本、另一位置启用、共享叶、总面板构建路径、配置失败恢复与安装子 Shell 的退出顺序。所有 App 和配置均由临时目录夹具承接，系统登记及 Finder 刷新使用替身，不执行真实安装或卸载。

<!-- jobs-language-terminal-style-v1 -->

**终端配色保护：** `PackageInstallLocationTests.rb` 直接运行时，在可可靠保存与恢复配色的交互终端中临时使用黑底白字和统一强调色；正常退出、失败及可捕获中断后恢复进入前的配色，保留原业务清理和退出状态。导入本文件不接管终端；无法可靠保护、纯文本模式或无交互终端时按纯文本约定降级。运行中另行修改的颜色会保留并报告冲突，强制终止后可按运行提示使用独立恢复入口。 此实现保留原解释器选项和预载状态；无可用 fork、Windows 或预载多线程时不重启脚本，以纯文本继续。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
