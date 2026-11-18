# PackagingShellTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./PackagingShellTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./PackagingShellTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_check_accepts_block_and_flow_flutter_manifests_without_writes`
- `test_check_rejects_dart_nested_test_only_and_duplicate_dependencies`
- `test_actual_nul_in_manifest_is_rejected`
- `test_project_and_manifest_symlinks_are_rejected`
- `test_check_does_not_search_parent_or_child_for_a_project`
- `test_oversize_manifest_and_control_character_paths_are_rejected`
- `test_invalid_arguments_stop_before_logs_or_commands`
- `test_noninteractive_entry_does_not_create_logs_or_build`
- `test_help_is_readonly_without_a_project_or_terminal`
- `test_fzf_selects_each_android_output_type`
- `test_fzf_selects_ios_without_android_artifact_menu`
- `test_fzf_defaults_are_removed_only_from_child_process`
- `test_fzf_missing_or_unhealthy_stops_before_flutter`
- `test_fzf_invalid_result_is_an_error`
- `test_fzf_cancel_exit_codes_survive_pipe_fail_and_main_stops_cleanly`
- `test_android_artifact_menu_cancel_stops_before_pub_get`
- `test_project_fvm_sdk_has_priority_over_global_flutter`
- `test_pinned_fvm_never_falls_back_to_global_flutter`
- `test_fvm_wrapper_is_used_for_a_pinned_project`
- `test_java17_is_checked_and_exported`
- `test_wrong_java_and_failed_java_health_check_are_rejected`
- `test_android_missing_gradlew_stops_before_pub_get`
- `test_ios_checks_xcode_and_requires_pod_only_for_a_podfile`
- `test_failed_xcode_check_preserves_failure_and_stops_before_flutter`
- `test_pub_failure_propagates_through_tee_and_prevents_build`
- `test_build_failure_propagates_and_does_not_continue_to_second_target`
- `test_android_full_main_uses_literal_special_paths_and_flavor_arguments`
- `test_ios_full_main_builds_and_reports_ipa`
- `test_build_success_without_output_is_failure`
- `test_empty_output_is_not_reported_as_a_successful_package`
- `test_report_rejects_other_modes_and_empty_files`
- `test_report_rejects_another_flavor_and_accepts_only_the_selected_flavor`
- `test_old_ipa_is_preserved_but_not_counted_as_a_new_export`
- `test_android_cached_output_is_accepted_with_an_explicit_reuse_log`
- `test_harmony_menu_contains_all_platforms_and_each_ohos_output_type`
- `test_harmony_artifact_menu_cancel_and_invalid_choice_do_not_run_flutter`
- `test_harmony_target_override_skips_only_the_secondary_menu`
- `test_harmony_environment_target_is_accepted_and_invalid_arguments_are_readonly`
- `test_harmony_full_main_builds_selected_hap_app_and_all_with_literal_paths`
- `test_harmony_full_main_reports_module_outputs`
- `test_harmony_explicit_sdk_takes_priority_over_environment_and_project_sdk`
- `test_harmony_environment_sdk_is_used_and_missing_override_does_not_fall_back`
- `test_harmony_pinned_fvm_without_local_sdk_does_not_call_fvm_or_global_flutter`
- `test_harmony_rejects_flavor_before_pub_get`
- `test_harmony_project_metadata_is_required_before_flutter`
- `test_harmony_sdk_environment_must_exist_and_supports_hos_fallback`
- `test_harmony_required_tools_are_health_checked_and_fail_before_pub_get`
- `test_harmony_unhealthy_flutter_or_unsupported_package_kind_is_rejected`
- `test_harmony_failure_stops_before_second_target_and_preserves_exit_code`
- `test_harmony_success_without_nonempty_outputs_is_failure`
- `test_harmony_cached_outputs_are_preserved_and_explicitly_reported`
- `test_harmony_missing_commands_and_invalid_java_fail_before_flutter`
- `test_harmony_generic_successful_help_is_not_accepted_as_package_capability`
- `test_harmony_report_excludes_intermediates_dependencies_wrong_types_and_empty_files`
- `test_harmony_sdk_override_does_not_change_android_or_ios_resolution`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
