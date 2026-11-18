# FlutterRunnerJSONTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./FlutterRunnerJSONTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./FlutterRunnerJSONTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_flutter_devices_keep_real_supported_ids_and_two_columns`
- `test_empty_device_array_is_distinct_from_malformed_response`
- `test_physical_and_other_groups_do_not_mislabel_running_simulators`
- `test_project_platform_directories_filter_known_devices_but_preserve_custom_platforms`
- `test_emulator_array_uses_official_daemon_fields_and_only_lists_android`
- `test_simulators_only_use_available_ios_runtimes_and_devices`
- `test_runtime_choices_are_available_ios_versions_newest_first`
- `test_duplicate_available_runtime_builds_only_offer_one_version_name`
- `test_device_type_choices_exclude_ipad_watch_and_tv`
- `test_preferred_types_put_models_with_available_runtime_first`
- `test_preferred_types_rank_by_current_architecture_only`
- `test_compatible_runtimes_hide_unsupported_versions_and_mark_unknown`
- `test_compatible_runtimes_respect_version_bounds_without_whitelist`
- `test_compatible_runtimes_reject_unknown_model`
- `test_combination_modes_reject_malformed_simctl_response`
- `test_simctl_missing_structure_is_a_parse_failure`
- `test_common_pubspec_block_and_flow_forms_are_accepted`
- `test_misleading_descriptions_wrong_keys_and_ambiguous_yaml_are_rejected`
- `test_validator_rejects_root_and_pubspec_symlinks_large_files_and_packages`
- `test_plist_preserves_argument_boundaries_and_only_selected_environment`
- `test_plist_rejects_invalid_label_and_linked_destination_without_writes`
- `test_emulator_plist_owns_native_emulator_process_with_exact_avd_argument`
- `test_emulator_plist_rejects_bad_binary_label_id_or_session`
- `test_daemon_controls_use_latest_app_start_and_flutter_array_protocol`
- `test_daemon_control_refuses_missing_app_id_unknown_action_and_bad_arguments`
- `test_fvm_version_reads_both_config_layouts`
- `test_universal_ready_reuses_complete_cache_without_executing_or_writing_sdk`
- `test_universal_ready_rejects_missing_package_or_patched_directory_even_with_valid_stamps`
- `test_universal_ready_rejects_mismatched_engine_artifact_and_version_stamps`
- `test_universal_ready_rejects_missing_or_nonexecutable_required_tools`
- `test_universal_ready_validates_pub_roots_and_rejects_network_uris_or_invalid_configs`
- `test_universal_ready_rejects_unknown_layout_or_engine_metadata`
- `test_fvm_version_rejects_missing_or_unsafe_values`
- `test_unique_simulator_name_appends_suffix_for_existing_names`
- `test_unique_simulator_name_rejects_empty_base_or_malformed_devices`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
