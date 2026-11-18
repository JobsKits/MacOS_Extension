# `Android 工程组件准备内核`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、来源与调用](#sources)
- [二、许可、状态与副作用](#effects)
- [三、验证边界](#validation)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

供 [**Flutter**](https://flutter.dev/) 运行环境准备模块加载的 [**Android**](https://developer.android.com/) 内部资源，不单独执行。完整功能入口与后台隔离边界见[运行环境准备说明](../../README.md)。

## 一、<span id="sources">来源与调用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- [SetupFlutterPlatform.zsh](./【MacOS】SetupFlutterPlatform.zsh/README.md) 复用[一键配置的工程组件内核](../../../../../../JobsFlutterTools/Scripts/Tools/【MacOS】SetupFlutterPlatform.zsh/【MacOS】SetupFlutterPlatform.zsh)，负责当前工程 compileSdk、build-tools、NDK、CMake、许可证及 `sdk.dir`。
- [AndroidSdkSupport.zsh](./【MacOS】AndroidSdkSupport.zsh/README.md) 复用[Android SDK 工具内核](../../../../../../JobsFlutterTools/Scripts/Tools/【MacOS】AndroidSdkSupport.zsh/【MacOS】AndroidSdkSupport.zsh)，提供 SDK／Java／Command-line Tools 的发现、下载、校验与必要补齐。
- 运行器在子 Shell 内加载资源，并提供日志、版本选择、有界命令及文件状态回调；不执行模拟器创建或启动入口。交付包内直接定位这两份资源，运行时不访问上游源码目录。

## 二、<span id="effects">许可、状态与副作用</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 读取当前工程及绑定 Flutter 的构建声明；动态版本不能可靠推导时交由键盘选择，不改写业务构建脚本。健康组件复用，缺失组件按既有来源和校验流程安装。
- 官方许可证由本人阅读并作答，拒绝、取消或缺少明确许可结果时停止；不通过 `yes` 管道自动接受。
- SDK Manager 可临时使用兼容工具 JDK；项目 [**Gradle**](https://gradle.org/) 继续使用原选项目 JDK。子 Shell 不覆盖父运行器日志、脚本路径或退出清理状态。
- 安装会写入选定 SDK／用户 Java 目录；`android/local.properties` 仅合并 `sdk.dir`，原文备份留在本轮准备目录，写前重新核对文件身份与内容，遇到并发修改保留现场。已有项目源码和第三方源码保持原样。

## 三、<span id="validation">验证边界</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

资源更新时核对同源逻辑与同名包装后的包内引用，执行语法及隔离回调验证；使用假 SDK、假下载与临时工程覆盖工具 JDK／项目 JDK、许可证、取消、组件缺失和配置备份，不为测试运行真实安装或模拟器。源码与替身通过不能代替真实工程、官方许可及设备构建验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
