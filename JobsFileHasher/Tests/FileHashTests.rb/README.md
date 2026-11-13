# 文件指纹隔离验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与覆盖](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

`FileHashTests.rb` 使用 [**Ruby**](https://www.ruby-lang.org/) 的 Minitest 编译 [**Swift**](https://www.swift.org/) 业务夹具，验证摘要、文件边界、剪贴板调用顺序、URL 传输、私有终端载体和独立管理范围。不启动真实终端、不写系统剪贴板、不注册扩展或刷新 Finder。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与覆盖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从任意工作目录执行下列脚本的实际路径；需要本机 Xcode 命令行工具和系统 Ruby，无额外 gem。

```shell
ruby ./FileHashTests.rb
```

覆盖空文件、已知摘要、多块二进制、中文及引号换行路径、目录 / 多选 / 链接 / FIFO / 缺失文件拒绝、失败不调用剪贴板、剪贴板失败传播、URL 重复字段、过期选择复核、载体 700 / 600 权限与自清理，以及复制改名后的管理范围校验。真实 Terminal 自动化授权、Finder 菜单和剪贴板交互仍需安装后验收。

<!-- jobs-language-terminal-style-v1 -->

**终端配色保护：** `FileHashTests.rb` 直接运行时，在可可靠保存与恢复配色的交互终端中临时使用黑底白字和统一强调色；正常退出、失败及可捕获中断后恢复进入前的配色，保留原业务清理和退出状态。导入本文件不接管终端；无法可靠保护、纯文本模式或无交互终端时按纯文本约定降级。运行中另行修改的颜色会保留并报告冲突，强制终止后可按运行提示使用独立恢复入口。 此实现保留原解释器选项和预载状态；无可用 fork、Windows 或预载多线程时不重启脚本，以纯文本继续。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
