# FlutterInstallerIntegrationTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./FlutterInstallerIntegrationTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./FlutterInstallerIntegrationTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_every_registered_project_has_one_public_management_entry`
- `test_selector_all_and_checkbox_identifiers_stay_in_the_same_order`
- `test_private_dependency_export_and_import_remain_independent_leaf_routes`
- `test_retired_sourcetree_is_not_selectable_but_legacy_uninstall_mapping_remains`
- `test_flutter_leaf_selection_replaces_previous_actions_and_builds_one_package`
- `test_flutter_selection_is_independent_and_terminal_actions_are_deduplicated`
- `test_bundled_management_panels_and_independent_scope_include_all_flutter_leaves`
- `test_regrouped_labels_preserve_leaf_identifiers_and_match_installer_catalog`
- `test_setup_and_gradle_actions_are_individually_selectable_in_the_shared_package`
- `test_dependency_categories_are_individual_leaves_in_the_same_package`
- `test_native_archive_pairs_are_individually_selectable`
- `test_dependency_import_maps_to_the_same_package_and_retains_extraction`
- `test_build_clean_selection_maps_to_terminal_without_enabling_other_actions`
- `test_unknown_selection_stops_and_flutter_uninstall_has_the_same_identity`
- `test_flutter_packaging_mapping_selects_one_independent_project`
- `test_doctor_and_codegen_are_independent_in_install_and_uninstall`
- `test_missing_flutter_project_stops_with_complete_repository_guidance`
- `test_complete_repository_projects_pass_without_other_actions`
- `test_empty_project_package_stops_with_its_missing_configuration_path`
- `test_all_missing_project_paths_are_reported`
- `test_git_pull_selection_and_uninstall_identity_are_independent`
- `test_missing_git_pull_project_stops_with_complete_repository_guidance`
- `test_extraction_selection_and_uninstall_use_the_independent_project`
- `test_missing_extraction_project_stops_with_complete_repository_guidance`
- `test_flutter_run_is_independent_and_uninstall_has_matching_identity`
- `test_missing_flutter_run_project_stops_with_complete_repository_guidance`
- `test_simulator_selection_uses_aggregate_and_retains_legacy_cleanup_identity`
- `test_simulator_uninstall_selection_uses_the_matching_process_and_paths`
- `test_simulator_fallback_host_launch_requires_explicit_initialization`
- `test_git_proxy_selection_uses_project_tools_and_retains_legacy_identity_for_cleanup`
- `test_git_proxy_uninstall_mapping_preserves_the_independent_identity`
- `test_git_proxy_registration_launch_only_initializes_the_extension`
- `test_missing_git_menu_project_stops_before_any_registration`
- `test_registration_cleanup_finds_explicit_and_legacy_host_identifiers`
- `test_missing_simulator_project_stops_with_complete_repository_guidance`
- `test_run_authorization_selection_uses_one_independent_project`
- `test_run_authorization_uninstall_uses_the_matching_process_and_paths`
- `test_run_authorization_registration_only_initializes_the_host`
- `test_missing_run_authorization_project_stops_with_complete_repository_guidance`
- `test_registration_activation_requires_the_exact_current_extension_path`
- `test_flutter_selection_is_saved_only_after_build_and_registration_succeed`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
