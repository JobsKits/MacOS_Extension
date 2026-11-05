# <span id="前言">管理面板主题与语言隔离验证</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、运行方式](#jobs-toc-heading-1)
- [二、覆盖与隔离边界](#jobs-toc-heading-2)

</details>
<!-- jobs-toc:end -->

---

> [PanelPreferencesTests.rb](./PanelPreferencesTests.rb) 编译实际面板源码，以原生 [**AppKit**](https://developer.apple.com/documentation/appkit) 控件和临时用户偏好域核对主题、语言、偏好保存与切换时的任务状态保留；不执行扩展安装或卸载。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在仓库根目录运行，需要 [**MacOS**](https://www.apple.com/macos/) 图形桌面、[**Ruby**](https://www.ruby-lang.org/) 和已有的 [**Xcode**](https://developer.apple.com/xcode/) 命令行工具；测试不安装依赖。

```shell
ruby ./Tests/PanelPreferencesTests.rb/PanelPreferencesTests.rb
```

默认编译产物与面板预览保存在临时目录，结束后清理。设置 `JOBS_PANEL_PREVIEW_DIR` 可将 `english-day.png` 和 `traditional-night.png` 保留到指定输出目录，供辅助检查；预览仅包含测试构造的面板状态，离屏绘制不含全部系统合成效果，完整画面仍需桌面实测。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">二、覆盖与隔离边界 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 核对黑夜、白天、跟随系统，以及简体中文、繁体中文、英文、跟随系统；默认值、保存与恢复在临时偏好域内验证，同时核对右上角布局、窗口缩放、窄窗回退，以及安装位置与两个清理控件同排、垂直居中和统一间隔。
- 核对系统首选界面语言的简繁中文识别与英文回退，以及系统区域通知、应用重新激活后的刷新；反复切换后保留功能勾选、当前状态、执行中标记和原始日志。
- 检查总面板、实际随包面板及联合 App 管理快照的源码一致性，独立包继续使用同一套偏好行为。
- 测试不改系统主题、系统语言或真实用户的面板偏好，不调用安装器、系统登记、卸载或文件管理器重启；原生控件隔离结果不能代替目标系统桌面的完整视觉验收。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
