# 【MacOS】RunFlutterProject.zsh

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与资源](#jobs-toc-heading-2)
- [二、路径、风险和验证](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

脚本名称：从终端运行 Flutter 项目或独立 Dart Demo。

调用方式：`/bin/zsh ./【MacOS】RunFlutterProject.zsh --project '/路径/工程/lib/demo.dart'`；不传参数时可手输或拖入项目目录、单个 `.dart` 后回车。自动定位最近的 Flutter `pubspec.yaml`，拒绝符号链接、嵌套非 Flutter 包及无可识别 `main()` 的文件；不会生成临时 Dart 入口或改写 Demo 源码。

选定文件作为 `-t` 参数传到后台 worker；会话标识包含项目、设备与入口，防止切换 Demo 时重连到另一个入口。项目根目录调用保留默认 `lib/main.dart` 语义，并继续使用原项目 / 设备会话键以兼容已有会话。目标开始前仍进行既有 SDK、环境、设备检查；脚本快照更新只对新发起的运行生效。

核心用途：先体检 iOS / Android / 鸿蒙环境，所选平台通过后独立后台运行 Flutter，并查看日志及控制热重载。

影响范围：Flutter 构建可更新项目依赖和构建目录；可启动已有设备，或复用桌面流程新建 iOS / Android / Harmony 模拟器。

运行提示：先回车确认；关闭终端只离开日志，输入 s 才停止后台任务。

选择方式：交互终端用已验证的fzf方向键选择；仅显式关闭 fzf 且具备交互终端时保留带返回入口的文本模式；非终端停止选择，不等待输入。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与资源 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

实际源码：[./【MacOS】RunFlutterProject.zsh](./【MacOS】RunFlutterProject.zsh)。保留完整上级功能包，先阅读上级说明中的模式、参数、依赖及影响范围；本说明不把源码整理等同于已安装或已部署。

解释器为系统 `/bin/zsh`。独立交互入口保留原自述、确认和日志；后台 worker、转发器和 source 库遵守其原调用协议。需要 SDK、Xcode、Dart 或其它工具的能力继续按原入口检查，目录包装不新增 Python / Node / Ruby 业务依赖。

仅检查语法：

```shell
/bin/zsh -n "./【MacOS】RunFlutterProject.zsh"
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、路径、风险和验证 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

键盘选择使用 ↑/↓ 或 Tab 导航、回车确认；默认停在取消行，Esc / Ctrl+C 取消。子层按 ← 返回真实上一层，仍有效的查询会保留；候选变化后清空失效查询。返回、取消和选择器失败均不启动所选业务。

健康 fzf 直接复用；仅调用方已经确认的交互流程在缺失或损坏时沿 Homebrew 依赖链准备并复检。临时网络失败持续重试，Ctrl+C 可结束；确定的本地、认证、许可或版本错误停止。选择器不向 Shell 启动文件写入配置。只读检查不修复；非终端不等待交互。供 source 的库仅注册能力，不在加载时安装或重复确认。

源码采用同名目录；Bundle、后台会话和旧状态清单中的原资源名称由发布复制阶段保留。实际自身文件与逻辑资源目录分别解析，支持目录整体搬迁、中文和空格路径及工程外启动目录。

安装、依赖获取、构建、清理、授权或配置写入均沿用原功能的保护与取消边界；不因为测试或路径迁移自动执行。日志保留原脚本或上级面板的位置与纯文本内容，详细模式见源码和上级功能说明。

已核对原解释器语法、源码及旧发布路径的隔离寻址和受影响测试；真实 SDK 获取、应用构建、设备和安装后菜单另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
