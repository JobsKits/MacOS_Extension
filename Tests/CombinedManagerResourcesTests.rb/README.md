# <span id="前言">联合 App 管理资源隔离验证</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、运行方式](#jobs-toc-heading-1)

</details>
<!-- jobs-toc:end -->

---

> [CombinedManagerResourcesTests.rb](./CombinedManagerResourcesTests.rb) 在临时伪 App 中验证管理资源装配与合并，移走源目录后通过假 GUI 缓存核验相对入口和参数。不会启动真实面板、构建、安装、清理或登记任何扩展。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

依赖 [**macOS**](https://www.apple.com/macos/)、[**Ruby**](https://www.ruby-lang.org/) 和系统工具，不安装依赖。在仓库根目录运行：

```shell
ruby Tests/CombinedManagerResourcesTests.rb/CombinedManagerResourcesTests.rb
```

覆盖完整十单元管理文件、源文本快照、独立包更新保留其它功能、源树移走后默认 Apps 卸载入口、用户缓存位置、固定容器身份、符号链接拒绝与暂存失败保留旧目录。

<!-- jobs-language-terminal-style-v1 -->

**终端配色保护：** `CombinedManagerResourcesTests.rb` 直接运行时，在可可靠保存与恢复配色的交互终端中临时使用黑底白字和统一强调色；正常退出、失败及可捕获中断后恢复进入前的配色，保留原业务清理和退出状态。导入本文件不接管终端；无法可靠保护、纯文本模式或无交互终端时按纯文本约定降级。运行中另行修改的颜色会保留并报告冲突，强制终止后可按运行提示使用独立恢复入口。 此实现保留原解释器选项和预载状态；无可用 fork、Windows 或预载多线程时不重启脚本，以纯文本继续。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
