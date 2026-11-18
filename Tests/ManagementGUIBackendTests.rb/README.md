# ManagementGUIBackendTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./ManagementGUIBackendTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

公开 App 入口检查同时覆盖全部 35 个 `Info.plist` 的 `LSUIElement=true`：启动壳从一开始作为后台 agent，Dock 图标只由后续实际原生管理面板持有。此处检查元数据、路径与转交协议，不操作用户正在执行的管理会话。

缓存面板参数／标准输出回归明确使用内部兼容模式；实际 GUI 的 LaunchServices 独立 PID、启动身份交接及联合快照等待由[原生宿主身份回归](../GUIHostIdentityTests.rb/README.md)验证，不再将兼容模式的 `exec` 输出测试作为单 Dock 身份证明。

独立卸载矩阵覆盖项目、桌面、Flutter、终端和 iOS 五包的全无需卸载、混合、App 缺失、失败码、缺配置兼容、损坏／链接／身份及另一位置保护；Flutter 平台缓存另外核对 GUI `flutter-flutter-precache` 与原生 `flutter-precache` 的双向映射，防止预检与结果事件使用不同标识。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./ManagementGUIBackendTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_root_emits_success_and_failure_for_each_leaf_and_continues_after_failure`
- `test_single_package_worker_reports_real_failure_exit_and_uses_gui_leaf_identifier`
- `test_all_functional_entrypoints_open_gui_and_never_dispatch_business_by_default`
- `test_standalone_packages_keep_identical_panel_source_and_launch_support`
- `test_app_bundles_are_text_only_launchers_with_executable_relative_entrypoints`
- `test_gui_bootstrap_executes_cached_panel_with_worker_scope`
- `test_actual_launchers_resolve_script_paths_inside_zsh_functions`
- `test_original_command_entries_only_open_the_full_gui`
- `test_app_retains_local_action_aliases_as_scoped_gui_selection`
- `test_bootstrap_compile_failure_uses_error_dialog_and_preserves_failure_status`
- `test_changed_panel_source_replaces_stale_cached_binary_without_opening_gui`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
