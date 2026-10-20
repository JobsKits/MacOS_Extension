# 卸载 Flutter 依赖提取 Finder 扩展

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、流程与确认](#jobs-toc-heading-2)
- [二、保留内容与日志](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

> 双击同目录 [卸载脚本](./【MacOS】卸载Flutter依赖提取Finder扩展.command)，只处理 `com.jobs.JobsFlutterDependencyExtractor.FinderSync` 对应的 Finder 扩展。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、流程与确认 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

先阅读内置自述并按回车，脚本查询该扩展真实注册路径、核对 App 名称与 Bundle ID，列出拟注销与删除清单。**只有精确输入大写 `YES` 才继续**；其它输入取消，`Ctrl+C` 可终止。

卸载会停用并注销固定扩展、停止对应宿主和扩展进程、删除二次核验通过的 App 产物，然后刷新 Finder。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、保留内容与日志 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

保留源码、Flutter 项目、已提取目录及运行日志，不卸载 Dart / Flutter。日志在系统临时目录中，以本脚本名加 `.log` 命名。若发现 App 核验发生变化立即停止，避免误删其他应用。

更多能力与安装位置见 [工程说明](../README.md)。普通验证不执行此卸载脚本。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
