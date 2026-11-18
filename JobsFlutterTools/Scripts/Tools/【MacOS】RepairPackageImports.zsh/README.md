# 【MacOS】RepairPackageImports.zsh

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

脚本名称：修复 Dart 相对 import 为 package 引用。

核心用途：按引用文件的位置解析相对 import，只转换实际指向本项目 lib 的引用。

影响范围：选定 Flutter 项目内的普通 Dart 源码；跳过第三方、生成代码和符号链接。

运行提示：先回车查看计划，再输入 YES 才备份并写入；--check / --dry-run 全程只读。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与资源 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

实际源码：[./【MacOS】RepairPackageImports.zsh](./【MacOS】RepairPackageImports.zsh)。保留完整上级功能包，先阅读上级说明中的模式、参数、依赖及影响范围；本说明不把源码整理等同于已安装或已部署。

解释器为系统 `/bin/zsh`。独立交互入口保留原自述、确认和日志；后台 worker、转发器和 source 库遵守其原调用协议。需要 SDK、Xcode、Dart 或其它工具的能力继续按原入口检查，目录包装不新增 Python / Node / Ruby 业务依赖。

仅检查语法：

```shell
/bin/zsh -n "./【MacOS】RepairPackageImports.zsh"
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、路径、风险和验证 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

源码采用同名目录；Bundle、后台会话和旧状态清单中的原资源名称由发布复制阶段保留。实际自身文件与逻辑资源目录分别解析，支持目录整体搬迁、中文和空格路径及工程外启动目录。

安装、依赖获取、构建、清理、授权或配置写入均沿用原功能的保护与取消边界；不因为测试或路径迁移自动执行。日志保留原脚本或上级面板的位置与纯文本内容，详细模式见源码和上级功能说明。

已核对原解释器语法、源码及旧发布路径的隔离寻址和受影响测试；真实 SDK 获取、应用构建、设备和安装后菜单另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
