# 【MacOS】ManageExtension.zsh

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与依赖](#jobs-toc-heading-2)
- [二、边界、日志与兼容](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本功能内部 GUI 后台管理入口，解析操作、功能范围、安装位置和停止请求，执行面板已经确认的安装 / 更新、卸载或构建产物清理。公开入口仍是功能目录中的 `.command` 与同名 App。首次打开面板不执行业务，空选、取消和参数不合法时停止。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与依赖 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

从上级公开管理入口打开面板，勾选本轮范围后点击安装 / 更新或卸载。后台 `--non-interactive` 参数只用于已确认的管理流程，不作为绕过确认的公开入口。

实际脚本：[./【MacOS】ManageExtension.zsh](./【MacOS】ManageExtension.zsh)；解释器为系统 `/bin/zsh`。资源以脚本位置解析，支持中文、空格和整体搬迁；不依赖启动工作目录。保留原功能的 Xcode / Swift、签名和系统权限要求，源码布局变更不代表已构建或安装。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、边界、日志与兼容 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

源码采用同名目录；发布 App、旧状态清单与联合管理器中的既有平铺资源名保持原协议。内部解析优先接受已发布平铺文件，再查找源码同名包装，拒绝链接替代的脚本。实际脚本路径和资源基准分别保留，不能以包装目录重建一个不存在的自身路径。

管理日志与逐项结果沿用上级面板及原脚本的路径；终端保护不写入日志。GUI worker 和支持库不增加重复阻塞确认。安装影响当前用户本功能的菜单与精确产物，卸载保留未选模块、源码和业务数据；运行前阅读上级功能说明。

验证范围为原解释器语法、隔离的源目录 / 发布目录寻址和受影响回归；未执行真实安装、卸载、登记、SDK 下载或构建。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
