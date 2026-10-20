# 安装 Flutter 运行 Finder 扩展

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#%E5%89%8D%E8%A8%80)
- [一、执行流程](#jobs-toc-heading-2)
- [二、日志与卸载](#jobs-toc-heading-3)

</details>
<!-- jobs-toc:end -->

---

## 🔥 <span id="前言">前言</span>

双击同目录的 `【MacOS】安装Flutter运行Finder扩展.command`，独立构建、注册并启用[运行 Flutter 项目](../README.md)菜单。要求完整 Xcode 与工程源码，不安装 Flutter、Homebrew 或 iOS runtime。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、执行流程 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

先展示源码、产物和影响；直接回车跳过，输入任意字符后回车安装，Ctrl+C 取消。确认后检查 Xcode 与 SDK，构建 `../JobsFlutterRunner.xcodeproj`，把产物保存在 `../work/DerivedData/`，仅注册 `com.jobs.JobsFlutterRunner.FinderSyncExtension` 并重启 Finder。

首次运行菜单可能触发宿主控制 Terminal 的自动化授权。请允许所需权限；宿主在后台转发完后退出，没有单独管理窗口。设备选择、日志、停止与 iOS 初始化均在后续项目右键动作中进行，安装器不会启动 Flutter 项目。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、日志与卸载 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

日志为系统临时目录中的 `JobsFlutterRunnerInstall.log`。构建失败先按日志修复 Xcode 与签名；菜单未显示时在系统扩展设置启用 Finder 扩展，再重新右键。已注册 App 应保留原路径；删除前先运行[独立卸载入口](../【MacOS】卸载Flutter运行Finder扩展.command/README.md)。

脚本用于实际安装，会修改本扩展注册并刷新 Finder；源码隔离验证不调用该流程。未通过真实安装验证的桌面行为见[工程验证状态](../README.md#verify)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
