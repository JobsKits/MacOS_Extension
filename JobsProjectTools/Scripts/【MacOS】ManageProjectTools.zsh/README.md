# 【MacOS】ManageProjectTools.zsh

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

本功能随包原生 Shell 工具。按原有参数与调用协议执行，资源以自身来源位置定位；被 source 的库只提供原有定义或显式初始化，不接管调用者的交互和终端。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与资源 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

实际源码：[./【MacOS】ManageProjectTools.zsh](./【MacOS】ManageProjectTools.zsh)。保留完整上级功能包，先阅读上级说明中的模式、参数、依赖及影响范围；本说明不把源码整理等同于已安装或已部署。

解释器为系统 `/bin/zsh`。独立交互入口保留原自述、确认和日志；后台 worker、转发器和 source 库遵守其原调用协议。需要 SDK、Xcode、Dart 或其它工具的能力继续按原入口检查，目录包装不新增 Python / Node / Ruby 业务依赖。

仅检查语法：

```shell
/bin/zsh -n "./【MacOS】ManageProjectTools.zsh"
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、路径、风险和验证 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

源码采用同名目录；Bundle、后台会话和旧状态清单中的原资源名称由发布复制阶段保留。实际自身文件与逻辑资源目录分别解析，支持目录整体搬迁、中文和空格路径及工程外启动目录。

项目根目录从实际脚本位置解析，源码同名包装与已发布平铺目录都返回功能包根目录。路径层级递减使用赋值，递减到零仍属于正常初始化，不触发严格模式的失败退出；九项 IDE／[**Git**](https://git-scm.com/) 菜单共用本入口，单元失败时所选菜单一起标记失败，详细原因以本轮日志为准。

配置读取拒绝未知、重复、链接或超长内容；已下线的 `git-sourcetree` 仍接受显式卸载兼容，但不再计为当前启用功能，也不会阻止最后一项现行功能卸载后移除共享模块。再次卸载已关闭的功能时，上级管理面板按“未安装，无需卸载”单独显示和统计。

安装、依赖获取、构建、清理、授权或配置写入均沿用原功能的保护与取消边界；不因为测试或路径迁移自动执行。日志保留原脚本或上级面板的位置与纯文本内容，详细模式见源码和上级功能说明。

已核对原解释器语法、源码及旧发布路径的隔离寻址和受影响测试；真实 SDK 获取、应用构建、设备和安装后菜单另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
