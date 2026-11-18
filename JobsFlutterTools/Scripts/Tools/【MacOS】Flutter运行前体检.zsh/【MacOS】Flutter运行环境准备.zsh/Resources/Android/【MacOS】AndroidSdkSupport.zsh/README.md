# `Android SDK 工具内核`

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

[AndroidSdkSupport.zsh](./【MacOS】AndroidSdkSupport.zsh) 是 [**Flutter**](https://flutter.dev/) 运行器随包携带的内部函数模块，仅由[运行环境准备器](../../../README.md)加载，不作为独立安装或启动入口。

## 一、<span id="responsibility">来源与职责</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 来源为[统一工具包的成熟内核](../../../../../【MacOS】AndroidSdkSupport.zsh/【MacOS】AndroidSdkSupport.zsh)；本包按“同名目录＋同名脚本”运输，包内引用跟随实际资源结构，运行时不访问来源仓库。
- 提供 SDK、Java、Command-line Tools 与组件的发现、下载和能力核验函数。上层提供日志、选择、命令及文件状态回调，实际副作用在明确调用对应准备函数后发生。
- 仅使用既有系统 Shell 与工具依赖，不新增 [**Python**](https://www.python.org/)／[**Node.js**](https://nodejs.org/) 作为运行前提；具体下载与校验范围见[工程组件资源说明](../README.md)。

## 二、<span id="boundaries">许可、副作用与验证</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- 复用健康候选，仅为当前流程补齐所需 SDK／用户 Java／工具组件；下载保留来源、摘要、日志和可取消重试，不修改全局 PATH、代理或 Shell 配置。提供模拟器相关函数不代表加载时执行；工程组件准备不调用模拟器创建、启动或镜像下载入口。
- 官方许可证保留本人阅读与选择；拒绝、取消、权限问题或复检失败明确停止，不把命令退出码零单独当作环境已就绪。
- 子 Shell 内的工具 JDK 可按 SDK Manager 要求切换；返回运行器后保留原选项目 [**Gradle**](https://gradle.org/) JDK。原工程、SDK 及第三方源码不因加载模块被改写。
- 维护时执行语法、包内引用和假工具隔离验证；假 SDK、临时工程及文档往返不代表真实安装、官方授权或设备构建验收通过。

最终写操作沿用一次确认：默认取消，方向键选择明确执行项后回车才创建 / 切换；← 返回上一个系统映像或版本选择，取消不执行最终写入。

键盘选择使用 ↑/↓ 或 Tab 导航、回车确认；默认停在取消行，Esc / Ctrl+C 取消。子层按 ← 返回真实上一层，仍有效的查询会保留；候选变化后清空失效查询。返回、取消和选择器失败均不启动所选业务。

健康 fzf 直接复用；仅调用方已经确认的交互流程在缺失或损坏时沿 Homebrew 依赖链准备并复检。临时网络失败持续重试，Ctrl+C 可结束；确定的本地、认证、许可或版本错误停止。选择器不向 Shell 启动文件写入配置。只读检查不修复；非终端不等待交互。供 source 的库仅注册能力，不在加载时安装或重复确认。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
