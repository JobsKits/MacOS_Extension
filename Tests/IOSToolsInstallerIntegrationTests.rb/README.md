# IOSToolsInstallerIntegrationTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./IOSToolsInstallerIntegrationTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./IOSToolsInstallerIntegrationTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_ios_options_are_unique_and_map_to_one_project`
- `test_codesnippets_can_be_installed_alone_without_disabling_existing_ios_tools`
- `test_pod_install_and_ios_build_cleanup_are_independent_ios_actions`
- `test_all_seven_git_actions_share_one_project_without_terminal_dependencies`
- `test_independent_install_and_uninstall_share_the_complete_fixed_action_list`
- `test_ios_project_identity_matches_install_and_uninstall`
- `test_installation_merges_valid_ios_selection_and_deduplicates_legacy_actions`
- `test_legacy_cache_selection_maps_to_the_single_build_cleanup_action`
- `test_first_install_or_empty_configuration_only_enables_selected_tools`
- `test_other_features_do_not_write_ios_configuration`
- `test_build_failure_does_not_persist_configuration_and_registration_reads_saved_selection`
- `test_ios_host_initialization_never_dispatches_a_tool`
- `test_ios_partial_uninstall_delegates_selected_actions_without_root_artifact_cleanup`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
