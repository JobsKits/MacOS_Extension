# 安装 Flutter 依赖提取 Finder 扩展

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、流程与确认](#jobs-toc-heading-2)
- [二、边界与排查](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

> 双击同目录 [安装脚本](./【MacOS】安装Flutter依赖提取Finder扩展.command)，独立构建并启用“提取 Flutter 第三方依赖”右键菜单。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、流程与确认 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1、先显示固定自述、源码、产物和日志位置；直接回车跳过，输入任意字符后回车才安装，`Ctrl+C` 取消。

2、检查完整 [**Xcode**](https://developer.apple.com/xcode/) 与 macOS SDK。编译上一级工程时跳过自动 Build Phase 注册，再由本入口统一注册、启用扩展、打开后台宿主并刷新 Finder。

3、产物保存在工程目录的 `../work/DerivedData/Build/Products/Debug/`；系统通过该路径启动扩展，不能当作普通缓存直接删除。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、边界与排查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

安装只处理本工程和固定 Bundle ID，不提取用户项目、不运行 `pub get`、不安装 Flutter / Dart。安装日志在系统临时目录 `JobsFlutterDependencyExtractorInstall.log`。若菜单未出现，到系统设置的 Finder 扩展设置核对启用状态；首次操作可能请求允许后台宿主控制 Terminal。

提取范围、资源要求及卸载方式见 [工程说明](../README.md)。本目录入口只做语法和隔离构建验证时不会真实执行安装。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
