# ProjectDependencyTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./ProjectDependencyTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./ProjectDependencyTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_source_is_pure`
- `test_android_uses_real_resolution_task_in_android_directory_and_preserves_failure`
- `test_pods_reuses_selected_command_and_install_lock_policy`
- `test_no_podfile_is_explicitly_inapplicable_without_installing_cocoapods`
- `test_spm_prefers_top_level_workspace_and_keeps_locked_versions`
- `test_spm_custom_project_lock_is_honored`
- `test_spm_multiple_workspaces_cancel_before_xcode_and_preserve_failure`
- `test_spm_older_flutter_uses_existing_project_without_config_only`
- `test_apple_configuration_selects_nondefault_entry_before_any_config_build`
- `test_spm_imported_cache_is_available_at_the_actual_flutter_cache_path`
- `test_spm_custom_build_directory_comes_from_selected_flutter_config`
- `test_existing_spm_cache_is_merged_and_preserved_before_linking`
- `test_existing_spm_cache_conflict_keeps_both_originals_and_never_builds`
- `test_legacy_flutter_uses_xcode_reported_derived_data_cache`
- `test_ohpm_and_fixed_hvigor_run_in_ohos_root_with_lock_unchanged`
- `test_ohpm_failure_does_not_start_hvigor_and_hvigor_failure_is_preserved`
- `test_web_npm_uses_ci_and_each_package_directory`
- `test_web_missing_or_ambiguous_lock_stops_without_guessing_install`
- `test_web_frozen_pnpm_and_yarn_generations`
- `test_web_failure_stops_before_the_next_package_directory`
- `test_no_js_manifest_adds_no_node_dependency`
- `test_native_build_uses_target_mapping_config_args_and_no_device_install`
- `test_native_configuration_cancel_invalid_target_and_build_failure`
- `test_native_android_build_keeps_selected_jdk_for_gradle_daemon`
- `test_one_click_dependency_failure_does_not_reach_native_build_or_success_event`
- `test_one_click_reuses_same_web_and_native_workers_in_order`
- `test_platform_selection_filters_absent_or_unsupported_targets_and_cancel`
- `test_real_diagnostic_obeys_explicit_command_directory_and_failure`
- `test_check_all_kinds_never_calls_tools_or_writes_logs`
- `test_independent_web_entry_runs_only_js_install_without_preparing_sdk_or_java`
- `test_check_rejects_invalid_project_and_unknown_kind_before_tools`
- `test_entry_cancel_and_noninteractive_call_never_prepare_anything`
- `test_precache_intro_explains_command_artifacts_and_boundary_before_confirmation`
- `test_native_intro_explains_composite_fetch_and_real_build_before_confirmation`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
