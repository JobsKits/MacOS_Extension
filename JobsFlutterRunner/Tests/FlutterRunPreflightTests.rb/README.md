# Flutter 运行前体检隔离测试

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

使用临时工程、工具链及实际 JXA 清单读取，验证 [**Flutter**](https://flutter.dev/) 运行门禁；不会运行本机 Flutter、下载 SDK 或启动设备。

## 一、<span id="run">运行与覆盖</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
ruby ./FlutterRunPreflightTests.rb
```

可通过 `JOBS_PREFLIGHT_TEST_HELPER` 指定完整模块路径，对聚合包副本运行同一组隔离测试；默认核验独立运行器。

覆盖函数内加载后仍可调用、健康三端、Android 许可证缺项与 iOS 独立通过、错误及超时、缺少平台／工具／快照、错误 SDK 依赖索引、FVM 声明与实际版本不符、菜单停留期间的配置变化与目标工具链复核、原生插件缺少鸿蒙支持、联邦平台实现排除、未知平台和未体检拒绝；同时核对不调用 Flutter Shell 引导、不下载 SDK、不运行应用。

连接发现另覆盖完整编译工具链缺失时的显式 SDK HDC、数字版本目录歧义、USB 超时／无效 plist 时保留 HDC、HDC 失败原文及退出码保留、未授权／离线状态提示、取消退出码传播、物理身份精确去重、仅品牌节点不误认鸿蒙，以及原目标的唯一受支持 Flutter 身份复核。测试只使用临时文件与假工具，不连接设备或安装 SDK。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
