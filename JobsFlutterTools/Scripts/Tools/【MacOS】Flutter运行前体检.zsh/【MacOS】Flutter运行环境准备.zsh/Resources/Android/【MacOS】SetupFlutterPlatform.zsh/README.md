# `Android 工程组件内核`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、来源与职责](#responsibility)
- [二、许可、副作用与验证](#boundaries)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[SetupFlutterPlatform.zsh](./【MacOS】SetupFlutterPlatform.zsh) 是 [**Flutter**](https://flutter.dev/) 运行器随包携带的内部函数模块，仅由[运行环境准备器](../../../README.md)加载，不作为独立安装或启动入口。

## 一、<span id="responsibility">来源与职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 来源为[统一工具包的成熟内核](../../../../../【MacOS】SetupFlutterPlatform.zsh/【MacOS】SetupFlutterPlatform.zsh)；本包按“同名目录＋同名脚本”运输，包内引用跟随实际资源结构，运行时不访问来源仓库。
- 读取当前工程 compileSdk、build-tools、NDK、CMake，核验官方许可并合并本机 sdk.dir。上层提供日志、选择、命令及文件状态回调，实际副作用在明确调用对应准备函数后发生。
- 仅使用既有系统 Shell 与工具依赖，不新增 [**Python**](https://www.python.org/)／[**Node.js**](https://nodejs.org/) 作为运行前提；具体下载与校验范围见[工程组件资源说明](../README.md)。

## 二、<span id="boundaries">许可、副作用与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 仅合并当前工程 `android/local.properties` 的 `sdk.dir`，保留原文备份；写前复核文件身份与内容，遇到并发变化停止。动态版本交由上层键盘选择，不改写业务构建脚本。
- 官方许可证保留本人阅读与选择；拒绝、取消、权限问题或复检失败明确停止，不把命令退出码零单独当作环境已就绪。
- 子 Shell 内的工具 JDK 可按 SDK Manager 要求切换；返回运行器后保留原选项目 [**Gradle**](https://gradle.org/) JDK。原工程、SDK 及第三方源码不因加载模块被改写。
- 维护时执行语法、包内引用和假工具隔离验证；假 SDK、临时工程及文档往返不代表真实安装、官方授权或设备构建验收通过。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
