# <span id="前言">部署位置面板隔离验证</span>

![Jobs出品，必属精品](https://picsum.photos/1500/400)

<!-- jobs-toc:start -->
<!-- jobs-toc:source {"v":2,"token":"[toc]"} -->
<details>
<summary>📚 目录（点击展开 / 收起）</summary>

- [一、运行方式](#jobs-toc-heading-1)

</details>
<!-- jobs-toc:end -->

---

> [DeploymentLocationPanelTests.rb](./DeploymentLocationPanelTests.rb) 通过真实 [**AppKit**](https://developer.apple.com/documentation/appkit) 控件与临时假 worker，验证首次打开默认勾选「应用程序」联合 App 及安装成功后清理、显式构建目录选择、两种操作的参数传递及执行期间锁定，不调用真实安装器、不写入 `/Applications`、不登记或停用扩展。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在仓库根目录运行，依赖 [**Ruby**](https://www.ruby-lang.org/) 与已安装的 [**Xcode**](https://developer.apple.com/xcode/) 命令行工具；测试不会安装依赖。

```shell
ruby Tests/DeploymentLocationPanelTests.rb/DeploymentLocationPanelTests.rb
```

安装位置选择、自动清理复选框与独立红色清理按钮的几何断言核对同排、垂直居中和统一间隔；隐藏和恢复仍按原部署位置及操作条件验证。

覆盖亮色 / 暗色、完整清单 / 单功能范围、三种屏幕尺寸；切换位置清除旧目标的状态但保留功能选择及安装、卸载各自的计时历史。「应用程序」路线明确显示联合 App 名称 `Jobs自定义右键菜单.app` 和 `/Applications/Jobs自定义右键菜单.app` 位置。清理子复选框仅在该路线安装时出现，首次打开默认勾选且可手动取消；取消后刷新或切换语言不重新勾选，切换至卸载时隐藏但保留当前选择，返回安装时恢复；切回构建目录才清空，切回应用程序路线不恢复旧勾选，执行期间锁定。仅当前保持勾选时才向临时假 worker 传 `--cleanup-build-products`，测试自身不执行任何构建产物清理。独立“🧹 清除构建产物”按钮采用红底白字，在构建目录和「应用程序」路线均显示；构建目录模式禁用以保留正在使用的产物，「应用程序」路线的安装 / 卸载页签均可按当前选择执行独立清理；清理计时不覆盖安装或卸载历史。安装时原操作按钮可提交“停止安装”，测试验证请求文件权限、当前单元正常收尾、后续 `skipped` 不计失败或完成进度，以及无停止确认的异常退出仍报告失败。`JOBS_MANAGER_BLOCKED` 的 App 管理授权拒绝会单独呈现并保留后续未执行状态；测试通过替身验证“打开隐私与安全性设置”仅在点击后调用，不打开真实系统设置、不更改授权。所有 worker、参数记录、编译产物与会话日志在临时目录内使用并清理。

<!-- jobs-language-terminal-style-v1 -->

**终端配色保护：** `DeploymentLocationPanelTests.rb` 直接运行时，在可可靠保存与恢复配色的交互终端中临时使用黑底白字和统一强调色；正常退出、失败及可捕获中断后恢复进入前的配色，保留原业务清理和退出状态。导入本文件不接管终端；无法可靠保护、纯文本模式或无交互终端时按纯文本约定降级。运行中另行修改的颜色会保留并报告冲突，强制终止后可按运行提示使用独立恢复入口。 此实现保留原解释器选项和预载状态；无可用 fork、Windows 或预载多线程时不重启脚本，以纯文本继续。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
