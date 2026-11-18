# CreateIOSSimulatorCommandTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./CreateIOSSimulatorCommandTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./CreateIOSSimulatorCommandTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_self_contained_entries_embed_identical_core_bytes`
- `test_runtime_rows_deduplicate_and_filter_availability_platform_and_architecture`
- `test_duo_only_latest_runtime_does_not_hide_traditional_device_types`
- `test_preferred_device_types_prioritize_supported_then_unknown_without_hiding_models`
- `test_duo_only_installed_runtime_makes_duo_default_and_retains_all_models`
- `test_catalog_summary_counts_matched_models_and_runtime_support`
- `test_compatible_runtimes_prioritize_known_support_and_exclude_known_incompatibility`
- `test_unconfirmed_runtime_warns_before_final_confirmation`
- `test_missing_empty_and_malformed_support_metadata_preserve_unknown_runtimes`
- `test_valid_support_identifier_whitelist_accepts_supported_and_rejects_other_models`
- `test_explicit_runtime_whitelist_takes_priority_over_device_version_bounds`
- `test_device_version_bounds_include_endpoints_and_exclude_outside_versions`
- `test_invalid_or_contradictory_version_bounds_do_not_hide_runtimes`
- `test_runtime_support_metadata_and_version_bounds_do_not_hide_device_types`
- `test_device_types_use_names_across_family_schema_changes_and_deduplicate_identifiers`
- `test_duplicate_runtime_identifier_does_not_break_selection`
- `test_malformed_json_and_control_characters_are_rejected`
- `test_unique_name_checks_all_existing_devices`
- `test_unknown_fzf_row_stops_without_numeric_fallback`
- `test_missing_fzf_stops_without_numeric_fallback`
- `test_cancel_and_no_matches_never_select_or_create`
- `test_fzf_health_failure_and_cancellation`
- `test_interactive_entry_propagates_missing_fzf_before_catalog_and_creation`
- `test_read_only_check_without_fzf_remains_available`
- `test_healthy_fzf_returns_a_catalog_row`
- `test_check_entry_reads_catalog_and_cleans_snapshots_without_mutation`
- `test_check_entry_reports_compatible_enter_default_without_mutation`
- `test_help_and_invalid_arguments_do_not_run_legacy_wrapper_or_probe_environment`
- `test_complete_script_copied_to_special_character_path_runs_help_independently`
- `test_initialization_wrapper_preserves_legacy_preflight_order`
- `test_initialization_wrapper_propagates_preflight_and_creation_failures`
- `test_initialization_wrapper_read_only_modes_bypass_legacy_preflight`
- `test_missing_runtime_and_list_failure_stop_before_creation`
- `test_missing_runtime_stops_enter_only_flow_before_selection_and_creation`
- `test_device_with_no_compatible_installed_runtime_stops_before_creation`
- `test_model_without_runtime_returns_to_selection_only_after_explicit_retry`
- `test_check_entry_reports_matched_model_counts_and_runtime_support`
- `test_empty_device_catalog_stops_check_and_selection_before_creation`
- `test_interactive_entry_rejects_non_tty_before_any_business`
- `test_create_and_boot_pass_arguments_without_shell_evaluation`
- `test_created_device_receipt_is_published_after_bootstatus`
- `test_failed_start_and_cancel_never_publish_device_receipt`
- `test_device_receipt_rejects_missing_symlink_and_nonempty_files`
- `test_create_failure_only_retries_explicit_incompatibility`
- `test_invalid_udid_stops_before_boot`
- `test_boot_failure_preserves_created_device_and_reports_udid`
- `test_gui_and_bootstatus_failures_do_not_claim_completed_startup`
- `test_device_hub_new_xcode_layout_and_bundle_validation`
- `test_final_confirmation_cancels_nonempty_and_eof`
- `test_complete_selection_flow_creates_once_with_process_suffix`
- `test_complete_healthy_fzf_flow_selects_each_list_once_and_creates_once`
- `test_enter_only_flow_selects_traditional_iphone_with_compatible_older_runtime`
- `test_enter_only_flow_defaults_to_duo_when_it_is_the_only_supported_model`
- `test_healthy_fzf_defaults_to_compatible_runtime_for_traditional_iphone`
- `test_fzf_user_defaults_cannot_change_enter_default_or_mutate_parent_environment`
- `test_complete_selection_flow_cancels_before_mutation`
- `test_incompatible_create_stops_without_explicit_retry`
- `test_incompatible_create_returns_to_selection_only_after_explicit_retry`
- `test_incompatible_create_with_fzf_and_enter_stops_after_one_selection_round`
- `test_generic_create_error_stops_without_reselection`
- `test_generic_create_error_does_not_offer_retry`
- `test_command_timeout_is_bounded`
- `test_runtime_left_returns_to_model_before_any_creation`
- `test_cancel_after_runtime_left_does_not_create`
- `test_runtime_left_with_no_matches_returns_instead_of_cancelling`
- `test_fzf_failure_propagates_without_creation`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
