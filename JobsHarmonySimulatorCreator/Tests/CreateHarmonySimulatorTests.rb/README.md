# CreateHarmonySimulatorTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./CreateHarmonySimulatorTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./CreateHarmonySimulatorTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_help_is_readonly_and_names_do_not_execute_shell`
- `test_tools_only_reuses_sdk_without_requiring_emulator_or_images`
- `test_tools_only_installs_missing_clt_then_requests_personal_license_without_images`
- `test_tools_only_and_readonly_mode_are_mutually_exclusive`
- `test_tools_only_package_install_does_not_require_emulator_create_capability`
- `test_clt_creation_binds_bundled_sdk_only_to_new_instance`
- `test_clt_preserves_native_sdk_setting`
- `test_clt_replaces_empty_legacy_sdk_field`
- `test_check_with_clt_sdk_is_still_readonly`
- `test_check_calls_only_readonly_official_commands_and_filters_images`
- `test_noninteractive_create_stops_before_tool_calls`
- `test_intel_mac_stops_before_emulator_calls`
- `test_rosetta_prompt_requests_a_native_terminal_instead_of_rejecting_apple_silicon`
- `test_explicit_bad_binary_or_sdk_does_not_fall_back`
- `test_explicit_deveco_and_clt_layouts_resolve_their_own_tool`
- `test_android_emulator_help_and_unhealthy_help_are_rejected`
- `test_android_in_path_cannot_hide_a_compatible_deveco_app`
- `test_later_path_entries_are_checked_and_duplicates_are_deduplicated`
- `test_only_android_installs_sdl_tools_and_saves_early_diagnostics`
- `test_prepare_healthy_does_not_create_start_or_open_anything`
- `test_prepare_accepts_a_literal_tool_path_without_executing_shell_content`
- `test_download_handoff_keeps_terminal_and_rechecks_newly_installed_app`
- `test_enter_only_downloads_default_phone_reviews_license_and_continues_creation`
- `test_image_install_failure_or_zero_exit_without_image_never_creates_or_loops`
- `test_image_download_retries_then_continues_without_reasking_license`
- `test_sdl_download_retries_then_installs_without_reasking`
- `test_catalog_zero_exit_with_network_text_retries_without_polluting_json`
- `test_image_zero_exit_without_ready_image_retries_until_locally_verified`
- `test_download_and_license_cancellation_never_installs`
- `test_online_image_options_and_invalid_selector_cannot_become_commands`
- `test_available_catalog_prefers_phone_and_numeric_newest_version_and_supports_2in1`
- `test_failed_browser_open_and_bad_path_leave_recovery_available`
- `test_check_never_enters_preparation_or_opens_a_browser`
- `test_sdl_install_is_reused_without_network_and_preserves_existing_versions`
- `test_sdl_local_archive_is_validated_without_download`
- `test_sdl_corrupt_archive_never_extracts_or_executes_and_cleans_stage`
- `test_sdl_download_failure_stops_and_does_not_open_login_page`
- `test_missing_tools_check_is_readonly_and_explicit_bad_path_requires_choice`
- `test_initial_cancel_never_installs_or_creates_logs`
- `test_sdl_incompatible_tool_is_not_published`
- `test_sdl_publish_never_overwrites_or_nests_into_existing_directory`
- `test_incompatible_app_does_not_count_toward_ambiguity`
- `test_two_compatible_installations_require_an_explicit_choice`
- `test_explicit_incompatible_emulator_never_falls_back_to_a_good_app`
- `test_similar_option_names_are_not_creation_capabilities`
- `test_real_emulator_help_accepts_brackets_and_colon_delimiters`
- `test_real_emulator_empty_responses_are_readonly_empty_lists`
- `test_invalid_images_and_instance_containers_fail_without_mutations`
- `test_single_instance_object_and_object_prototype_names_are_valid`
- `test_duplicate_instance_names_or_control_characters_are_rejected`
- `test_flat_and_nested_os_version_fields_are_supported_but_conflicts_stop`
- `test_missing_images_can_cancel_download_selection`
- `test_numbered_selection_creates_and_verifies_an_exact_unique_name`
- `test_default_name_is_generated_and_verified`
- `test_creator_without_start_leaves_receipt_empty`
- `test_created_device_receipt_requires_exact_hdc_target_from_instance_sdk`
- `test_receipt_never_uses_another_hdc_target_or_unconfirmed_metadata`
- `test_connection_metadata_accepts_flat_and_nested_port_and_rejects_conflicts`
- `test_receipt_uses_same_instance_config_sdk_and_refuses_conflicting_metadata`
- `test_harmony_receipt_rejects_missing_symlink_and_nonempty_files`
- `test_name_policy_rejects_native_invalid_names_before_querying_or_creating`
- `test_default_name_sanitizes_device_type_and_collision_suffix`
- `test_healthy_fzf_uses_the_first_rows_without_inheriting_user_filters`
- `test_existing_name_is_preserved_and_never_created_again`
- `test_case_insensitive_existing_name_is_never_overwritten`
- `test_confirmation_time_race_is_rechecked_before_create`
- `test_failed_readonly_queries_preserve_failure_codes`
- `test_canceling_create_keeps_all_existing_state`
- `test_creation_failure_and_missing_or_mismatched_verification_stop_start`
- `test_start_keeps_the_official_license_prompt_and_failure_code`
- `test_control_names_and_unknown_parameters_are_readonly_errors`
- `test_selected_rows_are_exact_members_even_with_a_hostile_fzf`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
