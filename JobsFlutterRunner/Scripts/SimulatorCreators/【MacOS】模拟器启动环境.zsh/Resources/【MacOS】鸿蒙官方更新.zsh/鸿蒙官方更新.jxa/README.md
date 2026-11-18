# 鸿蒙官方更新.jxa

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

供同包 Shell 调用的 JXA / Objective-C 桥接辅助程序，按既有操作参数读取和验证结构化数据，输出原有机器协议。它不是交互式用户入口；不加入自述、确认、终端配色或 URL 展示控制码。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与资源 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

实际源码：[./鸿蒙官方更新.jxa](./鸿蒙官方更新.jxa)。保留完整上级功能包，先阅读上级说明中的模式、参数、依赖及影响范围；本说明不把源码整理等同于已安装或已部署。

解释器为系统 `osascript -l JavaScript`。由同包调用者传递操作及资源参数；输出用于程序读取，不应额外拼接人类提示。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、路径、风险和验证 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

源码采用同名目录；Bundle、后台会话和旧状态清单中的原资源名称由发布复制阶段保留。实际自身文件与逻辑资源目录分别解析，支持目录整体搬迁、中文和空格路径及工程外启动目录。

安装、依赖获取、构建、清理、授权或配置写入均沿用原功能的保护与取消边界；不因为测试或路径迁移自动执行。日志保留原脚本或上级面板的位置与纯文本内容，详细模式见源码和上级功能说明。

已核对原解释器语法、源码及旧发布路径的隔离寻址和受影响测试；真实 SDK 获取、应用构建、设备和安装后菜单另验。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
