# ApplicationsLocationIntegrationTests.rb

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与范围](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

验证总管理器的构建目录 / 应用程序目录选择、参数校验、登记路径、部署提交与失败恢复，以及卸载不存在或不活跃副本时保留正在使用的功能配置。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本目录执行：

```shell
ruby ./ApplicationsLocationIntegrationTests.rb
```

使用项目既有的隔离系统操作替身与临时目录，不构建工程、不写入真实应用程序目录、不登记或卸载系统扩展，也不刷新 Finder。公共部署库的实际文件复制与回滚另由部署库测试验证。

<!-- jobs-language-terminal-style-v1 -->

**终端配色保护：** `ApplicationsLocationIntegrationTests.rb` 直接运行时，在可可靠保存与恢复配色的交互终端中临时使用黑底白字和统一强调色；正常退出、失败及可捕获中断后恢复进入前的配色，保留原业务清理和退出状态。导入本文件不接管终端；无法可靠保护、纯文本模式或无交互终端时按纯文本约定降级。运行中另行修改的颜色会保留并报告冲突，强制终止后可按运行提示使用独立恢复入口。 此实现保留原解释器选项和预载状态；无可用 fork、Windows 或预载多线程时不重启脚本，以纯文本继续。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
