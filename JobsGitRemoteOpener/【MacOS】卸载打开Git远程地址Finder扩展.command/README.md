# `【MacOS】卸载打开Git远程地址Finder扩展.command`

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [🔥 前言](#jobs-toc-heading-1)
- [一、适用场景](#jobs-toc-heading-2)
- [二、运行方式](#jobs-toc-heading-3)
- [三、影响范围](#jobs-toc-heading-4)
- [四、日志与排查](#jobs-toc-heading-5)

</details>
<!-- jobs-toc:end -->

---

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">🔥 <font id=前言>前言</font></span><!-- jobs-toc:heading-end -->

`【MacOS】卸载打开Git远程地址Finder扩展.command` 用来卸载 `JobsGitRemoteOpener` 的 Finder Sync Extension，移除 Finder 右键菜单里的 `打开 Git 远程地址` 入口，并清理旧 Automator 服务版残留。

## <span id="jobs-toc-heading-2" data-jobs-toc="v2">一、适用场景 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 不再需要 Finder 右键 `打开 Git 远程地址`。
- Finder 右键菜单中残留了旧扩展或旧 Automator 服务入口。
- 重新调试 `JobsGitRemoteOpener` 前，需要先清理旧注册状态和构建产物。

## <span id="jobs-toc-heading-3" data-jobs-toc="v2">二、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

1. 在 Finder 中双击 `./【MacOS】卸载打开Git远程地址Finder扩展.command`。
2. 终端会先展示脚本内置自述。
3. 确认影响范围后按回车继续；按 `Ctrl+C` 取消。
4. 脚本完成后会重启 Finder，用来刷新 Finder Sync Extension 菜单缓存。

也可以在终端中执行：

```shell
./【MacOS】卸载打开Git远程地址Finder扩展.command
```

## <span id="jobs-toc-heading-4" data-jobs-toc="v2">三、影响范围 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 禁用并注销 `com.jobs.JobsGitRemoteOpener.FinderSyncExtension`。
- 停止 `JobsGitRemoteOpener` 宿主 App 和 `JobsGitRemoteFinderSync` 扩展进程。
- 删除 [**Xcode**](https://developer.apple.com/xcode) DerivedData 中的 `JobsGitRemoteOpener.app` 构建产物。
- 删除本工程 `../work/JobsGitRemoteOpenerDerivedData` 旧构建产物。
- 删除系统临时目录中的 `JobsGitRemoteOpenerNeedsFinderRestart` 和 `JobsGitRemoteOpener.log`。
- 删除旧 Automator 服务 `打开Git远程地址.workflow` 和辅助脚本 `OpenGitRemoteInBrowser.zsh`。
- 刷新 macOS Services 缓存并重启 Finder。
- 不删除上一级 `JobsGitRemoteOpener` 工程源码。

## <span id="jobs-toc-heading-5" data-jobs-toc="v2">四、日志与排查 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

- 脚本日志写入系统临时目录中的 `【MacOS】卸载打开Git远程地址Finder扩展.log`。
- 如果脚本提示缺少命令，先确认当前系统是 macOS，并检查 `pluginkit`、`pkill`、`killall`、`find` 等系统命令是否可用。
- 如果菜单短时间仍显示，重新打开 Finder 窗口；必要时注销后重新登录。
- 以后重新运行 `JobsGitRemoteOpener.xcodeproj` 主 App 时，扩展会再次注册并启用。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
