# <span id="前言">联合 App 内置管理资源</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、管理资源与边界](#jobs-toc-heading-1)
- [二、生成资源快照同步](#jobs-toc-heading-2)
- [三、隔离验证](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

> [【MacOS】联合App管理.zsh](./【MacOS】联合App管理.zsh) 是部署流程调用的函数库，为 `Jobs自定义右键菜单.app` 装配管理资源。打开联合 App 默认进入「应用程序」路线的卸载面板；源码目录移走后仍能管理已装功能。此函数库不构建、不登记、不卸载扩展。

**面板偏好：** 内置管理面板右上角同样提供“黑夜 / 白天 / 跟随系统”和“简体中文 / 繁体中文 / 英文 / 跟随系统”，默认跟随系统，选择即时生效并保存在当前用户偏好中，与源码总面板和随包面板共用。窄窗无法与标题同排时，工具组移至标题下一行并保持右对齐。主题跟随原生系统外观；系统语言在区域变化通知或窗口重新激活时重新读取。切换保留功能勾选、执行任务和已有日志；后台工具原始日志保留原文。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、管理资源与边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

调用 `jobs_prepare_combined_manager_resources 容器绝对路径`。仅接受名称 `Jobs自定义右键菜单.app`、固定身份 `com.jobs.finderextensions.manager` 且无链接跳转的容器，先在同卷暂存，再替换 `Contents/Resources/ManagerRoot`；准备失败保留原管理目录。

全仓部署带入十个实际安装单元的管理脚本与部署库；单包部署只带入本包，并合并保留其它已安装单元的管理文件。不会复制业务 `Tools`、工程源码或开发机路径。资源入口 `Contents/Resources/ManageInstalledExtensions.zsh` 从自身位置定位；原生面板编译缓存写到用户的 `Library/Caches/JobsFinderExtensions/Management`，不修改 App 内文件。缺少工程源码时安装 / 更新会明确失败，卸载不要求工程源码。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">二、生成资源快照同步 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

`Resources/RootWorker.txt`、`PanelSource.txt`、`GuiBootstrap.txt` 是标准根管理器、面板和启动支持库的文本快照，不另行维护业务逻辑。每次标准源变更后刷新对应快照，再将完整同名函数库包同步到功能包；应在标准源最终修改后检查逐字节一致，不能把旧快照反向覆盖标准源。

在仓库根目录更新快照：

```shell
cp Scripts/ManageFinderExtensions.zsh Scripts/【MacOS】联合App管理.zsh/Resources/RootWorker.txt
cp Scripts/SelectFinderExtensionFeatures.swift Scripts/【MacOS】联合App管理.zsh/Resources/PanelSource.txt
cp Scripts/FinderManagerGUI.zsh Scripts/【MacOS】联合App管理.zsh/Resources/GuiBootstrap.txt
```

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">三、隔离验证 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

[CombinedManagerResourcesTests.rb](../../Tests/CombinedManagerResourcesTests.rb/CombinedManagerResourcesTests.rb) 使用临时伪 App 与假 GUI 缓存，覆盖完整装配、单包合并、源码移走后入口和缓存定位、链接 / 非自有容器拒绝及失败保留旧资源；不打开真实面板、不执行安装、清理或系统登记。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
