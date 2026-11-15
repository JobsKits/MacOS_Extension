# `CommandShortcutBehaviorTests.swift`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行入口](#run)
- [二、断言范围](#behavior)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本文件是[脚本快捷入口测试](../README.md)的可执行行为断言。它编译生产服务、请求、目录资格、控制器和语言模块；真实对话框由硬失败替身隔离，输入及 Finder 定位必须通过测试注入。

## 一、<span id="run">运行入口</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

请通过配套运行器编译，不要单独运行此源码：

```shell
ruby ../CommandShortcutBehaviorTests.rb/CommandShortcutBehaviorTests.rb
```

运行器会创建独立的测试偏好域；测试确认该域带有专用 UUID 前缀后，才验证语言与主题，结束时删除测试域。全部文件写入和脚本运行只发生在自行创建的临时夹具中。

## 二、<span id="behavior">断言范围</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

包目录遵循 `脚本.command/脚本.command` 同名结构。测试检查同级入口、可执行权限、原文保护、名称冲突、并发排他、参数与退出码、整组搬移、源缺失和链接替换、请求格式、取消与重试，以及十语映射和三主题状态。目录位置按文件系统身份核对，兼容系统临时目录的 `/var` 与 `/private/var` 等价路径。

这些断言不会验证真实 Finder 菜单可见性、系统扩展登记、真实对话框布局或跨机分发。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
