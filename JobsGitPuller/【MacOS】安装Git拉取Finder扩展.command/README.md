# 安装 Git 拉取 Finder 扩展

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、运行与影响](#jobs-toc-heading-2)
- [二、日志与排查](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

[独立安装入口](./【MacOS】安装Git拉取Finder扩展.command) 只构建并启用“拉取 Git 到最新”右键菜单。需要完整 [**Xcode**](https://developer.apple.com/xcode) 与 macOS SDK；安装过程不拉取目标 [**Git**](https://git-scm.com/) 仓库。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、运行与影响 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

双击同目录 `.command` 或从 Terminal 执行。首屏内置自述展示源码、产物、范围和日志；直接回车跳过，输入任意字符后回车才开始安装，`Ctrl+C` 取消。没有可交互输入时停止。

确认后在 `../work/DerivedData` 构建 `JobsGitPuller.app`，以 `JOBS_SKIP_FINDER_EXTENSION_BUILD_PHASE=1` 阻止构建阶段重复注册。构建成功后注册并启用 `com.jobs.JobsGitPuller.FinderSyncExtension`，启动后台宿主并重启 Finder。保留构建产物原位置，安装前保存 Finder 中正在进行的文件工作。

后台宿主没有管理窗口，收到文件夹请求后转交 Terminal，再自动退出。Git 拉取、提交和舍弃未提交内容的交互在右键动作中进行；详见 [工程说明](../README.md)。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、日志与排查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

安装日志为系统临时目录中的 `JobsGitPullerInstall.log`。构建失败先核对 Xcode 选择、首次启动和签名设置；脚本不会更改开发者目录或安装 Xcode。菜单未出现时，在系统设置的 Finder 扩展页检查开关；首次拉取时允许宿主控制 Terminal。

卸载使用 [独立卸载入口](../【MacOS】卸载Git拉取Finder扩展.command/README.md)，核对 App 路径后输入 `YES` 才删除产物和刷新 Finder。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
