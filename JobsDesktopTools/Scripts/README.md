# 桌面菜单安装管理

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、参数](#arguments)
- [二、业务资源](#resources)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

`ManageDesktopTools.zsh` 接收 `install|uninstall` 和明确的叶功能 ID，统一管理六个桌面菜单。完整功能、配置、事务、日志和验证见[聚合包说明](../README.md)。

## 一、<span id="arguments">参数</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

支持 `ios-simulator-create`、`android-simulator-create`、`harmony-simulator-create`、`android-simulator-repair`、`harmony-simulator-repair` 和 `hidden-files-toggle`。可一次传多个 ID；空选、未知项和错误操作在构建或写配置前停止。

`--non-interactive` 表示调用方已经确认安装范围；`--install`／`--uninstall` 为旧入口兼容参数。`--skip-finder-restart` 只跳过本层 Finder 刷新，不跳过构建、签名和登记核对。未显式授权无交互运行时，必须从交互终端阅读说明后回车确认。

## 二、<span id="resources">业务资源</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

管理器不会执行 `Resource/` 中的模拟器脚本，不会打开宿主 URL。安装完成后，用户点击菜单才由宿主调用本包业务；五份脚本的来源与摘要见 [SourceManifest.json](../SourceManifest.json)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
