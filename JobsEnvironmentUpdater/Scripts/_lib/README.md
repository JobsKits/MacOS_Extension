# update 随包依赖

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、模块与用途](#jobs-toc-heading-2)
- [二、维护边界](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

本目录保留原 `update` 所需的完整模块。运行时仅通过包内相对路径协作。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、模块与用途 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

| 模块目录 | 用途 |
| --- | --- |
| `【MacOS】FlutterSDK网络入口.zsh/` | SDK 下载统一入口 |
| `【MacOS】FlutterSDK命令适配.sh/` | 命令适配及环境绑定 |
| `【MacOS】FlutterSDK网络选路.zsh/` | 真实来源与进程网络路线 |
| `【MacOS】SDK获取重试.zsh/` | 下载重试与取消 |
| `jobs_git_network_strategy/` | Homebrew 所用 Git 选路包装与同包实施入口 |

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、维护边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

业务代码与原维护入口对应版本逐字节核验，来源路径只用于开发定位，不作为分发运行依赖；增删原 `update` 依赖时同步本目录、工程复制阶段、就近说明和运输测试。不改变原代理授权范围，不运行真实下载或更新来检验打包。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
