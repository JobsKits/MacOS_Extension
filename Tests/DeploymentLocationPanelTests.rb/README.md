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

> [DeploymentLocationPanelTests.rb](./DeploymentLocationPanelTests.rb) 通过真实 [**AppKit**](https://developer.apple.com/documentation/appkit) 控件与临时假 worker，验证默认构建目录与「应用程序」文件夹的选择、两种操作的参数传递及执行期间锁定，不调用真实安装器、不写入 `/Applications`、不登记或停用扩展。

## <span id="jobs-toc-heading-1" data-jobs-toc="v2">一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a></span><!-- jobs-toc:heading-end -->

在仓库根目录运行，依赖 [**Ruby**](https://www.ruby-lang.org/) 与已安装的 [**Xcode**](https://developer.apple.com/xcode/) 命令行工具；测试不会安装依赖。

```shell
ruby Tests/DeploymentLocationPanelTests.rb/DeploymentLocationPanelTests.rb
```

安装位置选择、自动清理复选框与独立红色清理按钮的几何断言核对同排、垂直居中和统一间隔；隐藏和恢复仍按原部署位置及操作条件验证。

覆盖亮色 / 暗色、完整清单 / 单功能范围、三种屏幕尺寸；切换位置清除旧目标的状态但保留功能选择及安装、卸载各自的计时历史。「应用程序」路线明确显示联合 App 名称 `Jobs自定义右键菜单.app` 和 `/Applications/Jobs自定义右键菜单.app` 位置。清理子复选框仅在该路线安装时出现且默认不勾选；切回构建目录或卸载即清空，执行期间锁定。仅明确勾选后才向临时假 worker 传 `--cleanup-build-products`，测试自身不执行任何构建产物清理。独立“🧹 清除构建产物”按钮采用红底白字，仅在「应用程序」路线显示，安装 / 卸载页签都能按当前选择执行独立清理；清理计时不覆盖安装或卸载历史。安装时原操作按钮可提交“停止安装”，测试验证请求文件权限、当前单元正常收尾、后续 `skipped` 不计失败或完成进度，以及无停止确认的异常退出仍报告失败。`JOBS_MANAGER_BLOCKED` 的 App 管理授权拒绝会单独呈现并保留后续未执行状态；测试通过替身验证“打开隐私与安全性设置”仅在点击后调用，不打开真实系统设置、不更改授权。所有 worker、参数记录、编译产物与会话日志在临时目录内使用并清理。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
