# Flutter 配置窗口终端资源

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、来源与许可证](#jobs-toc-heading-2)
- [二、终端桥与输出](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[terminal.html](./terminal.html) 仅供原生 WebKit 窗口加载，承接真正 PTY 的 ANSI 输出、fzf、键盘和窗口 resize；禁止网络连接及远程导航。显示滚动缓冲区为 50,000 行，完整输出另由原生窗口写入本机私有 `terminal.raw.log`，不以滚动缓冲区代替完整日志。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、来源与许可证</span><!-- jobs-toc:heading-end -->

随包固定 [xterm.js](https://github.com/xtermjs/xterm.js) `6.0.0` 与 `@xterm/addon-fit` `0.11.0`，均为 MIT。发布包来自 npm 官方注册源，按元数据的 SHA-512 `integrity` 核对后提取原始分发文件，第三方文件保持原样。版本、来源 URL、完整摘要分别见 [xterm.source.json](./xterm.source.json)、[addon-fit.source.json](./addon-fit.source.json)，许可证见 [xterm.LICENSE](./xterm.LICENSE) 和 [addon-fit.LICENSE](./addon-fit.LICENSE)。运行时不需要 Node.js、npm 或 CDN。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、终端桥与输出</span><!-- jobs-toc:heading-end -->

键盘、粘贴及终端查询由 xterm 的 `onData/onBinary` 交给本地 `pty` 桥，尺寸变化发送行列数；输出以 Base64 字节传入，避免把终端内容作为 JavaScript 源码解释。业务入口和状态协议见[上级脚本说明](../../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
