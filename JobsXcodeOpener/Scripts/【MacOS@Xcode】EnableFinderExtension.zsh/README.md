# 【MacOS@Xcode】EnableFinderExtension.zsh

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

此入口由本功能 Xcode Build Phase 调用，依据构建环境定位当前宿主与 Finder 扩展，处理登记、启用和刷新。它是构建钩子，不读取终端确认；缺少有效构建上下文时停止。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与依赖 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

从本功能 Xcode 工程执行既有构建流程。仅检查语法可运行：

```shell
/bin/zsh -n "./【MacOS@Xcode】EnableFinderExtension.zsh"
```

实际脚本：[./【MacOS@Xcode】EnableFinderExtension.zsh](./【MacOS@Xcode】EnableFinderExtension.zsh)；解释器为系统 `/bin/zsh`。资源以脚本位置解析，支持中文、空格和整体搬迁；不依赖启动工作目录。保留原功能的 Xcode / Swift、签名和系统权限要求，源码布局变更不代表已构建或安装。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、边界、日志与兼容 <a href="#前言">🔼</a> <a href="#🔚">🔽</a></span><!-- jobs-toc:heading-end -->

源码采用同名目录；发布 App、旧状态清单与联合管理器中的既有平铺资源名保持原协议。内部解析优先接受已发布平铺文件，再查找源码同名包装，拒绝链接替代的脚本。实际脚本路径和资源基准分别保留，不能以包装目录重建一个不存在的自身路径。

管理日志与逐项结果沿用上级面板及原脚本的路径；终端保护不写入日志。GUI worker 和支持库不增加重复阻塞确认。安装影响当前用户本功能的菜单与精确产物，卸载保留未选模块、源码和业务数据；运行前阅读上级功能说明。

验证范围为原解释器语法、隔离的源目录 / 发布目录寻址和受影响回归；未执行真实安装、卸载、登记、SDK 下载或构建。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
