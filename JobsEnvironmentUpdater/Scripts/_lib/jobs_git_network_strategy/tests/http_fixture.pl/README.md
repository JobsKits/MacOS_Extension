# `http_fixture.pl`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、目录与调用](#jobs-toc-heading-2)
- [二、验证边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本工程开发回归或隔离夹具；只按当前源码说明运行，需保留相邻生产脚本和测试资源。实际解释器：Perl；平台前缀不替代外部依赖要求。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、目录与调用 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[实际源码](<./http_fixture.pl>)与本说明在同名目录中；工程根目录、资源和测试基准从实际脚本位置解析，不依赖当前工作目录。终端可见 alias 保持原名称，内部实现文件按平台和角色包装。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、验证边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在本目录只读检查原生语法：

```shell
perl -c './http_fixture.pl'
```

测试参数、临时目录和假命令边界见源码自述；source 模块不直接当安装入口运行。语法通过不等于真实环境安装、卸载或网络行为通过。覆盖及例外见配置总仓 `项目相关报告/脚本统一审查.md`。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
