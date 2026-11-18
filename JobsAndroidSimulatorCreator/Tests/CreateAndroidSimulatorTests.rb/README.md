# CreateAndroidSimulatorTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./CreateAndroidSimulatorTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./CreateAndroidSimulatorTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_finder_and_bundled_simulator_resources_have_the_same_core`
- `test_full_health_check_is_read_only`
- `test_check_never_executes_the_new_cli_download_launcher`
- `test_cli_launcher_does_not_hide_a_working_legacy_installation`
- `test_cli_launcher_is_preserved_and_compatible_tools_are_added_once`
- `test_metadata_without_the_compatible_package_stops_before_archive_download`
- `test_explicit_proxy_reaches_sdk_list_and_install`
- `test_network_uses_environment_and_system_static_proxy_without_writing_settings`
- `test_proxy_errors_do_not_leak_credentials_or_start_repairs`
- `test_no_proxy_is_respected_for_sdk_repository`
- `test_check_does_not_install_missing_emulator`
- `test_check_missing_sdk_stops_before_downstream`
- `test_check_multiple_missing_layers_has_no_download`
- `test_broken_sdk_tools_fail_health_check`
- `test_help_and_invalid_argument_do_not_probe_or_write`
- `test_noninteractive_write_mode_rejects_before_probe`
- `test_intro_cancellation_has_no_side_effect`
- `test_create_uses_current_arch_image_and_all_enter_defaults`
- `test_existing_name_and_orphan_directory_cannot_be_overwritten`
- `test_created_device_receipt_contains_exact_avd_after_launch`
- `test_cancelled_create_does_not_publish_device_receipt`
- `test_failed_emulator_launch_never_publishes_device_receipt`
- `test_device_receipt_rejects_missing_symlink_and_nonempty_files`
- `test_unsafe_name_is_rejected_before_create`
- `test_final_cancellation_does_not_create`
- `test_empty_avds_enters_creation_and_selection_cancel_is_safe`
- `test_existing_avd_launch_checks_entire_toolchain_without_installing`
- `test_emulator_missing_installs_once_and_rechecks`
- `test_emulator_install_failure_stops_downstream`
- `test_emulator_download_retries_twice_then_continues_without_confirmation`
- `test_remote_catalog_retries_twice_then_can_cancel_selection`
- `test_sdk_list_zero_exit_with_failed_source_lists_keeps_retrying`
- `test_component_metadata_only_zero_exit_retries_until_required_payload_is_ready`
- `test_emulator_zero_exit_without_files_retries_until_ready`
- `test_missing_image_automatically_reads_remote_list_and_can_cancel_selection`
- `test_remote_list_failure_does_not_create`
- `test_image_download_and_creation`
- `test_image_zero_exit_without_files_retries_until_ready_then_can_cancel`
- `test_avd_creation_failure_does_not_launch`
- `test_avd_success_without_metadata_is_not_announced_as_created`
- `test_wrong_arch_and_preview_images_are_excluded`
- `test_broken_fzf_falls_back_to_number_selection`
- `test_missing_command_tools_is_automatically_prepared_after_single_entry_confirmation`
- `test_official_bootstrap_adds_a_version_and_rechecks`
- `test_official_bootstrap_checksum_failure_leaves_sdk_untouched`
- `test_official_bootstrap_rejects_external_archive_url`
- `test_google_metadata_and_archive_retry_until_both_succeed`
- `test_official_bootstrap_local_download_error_stops_without_retries`
- `test_bootstrap_preserves_broken_existing_tools_and_stops_if_recheck_fails`
- `test_check_never_bootstraps_command_tools`
- `test_stable_minor_and_extension_api_images_are_supported`
- `test_registered_broken_emulator_repairs_once_and_stops_if_recheck_still_fails`
- `test_directory_publish_rejects_existing_destination_instead_of_nesting`
- `test_prepare_healthy_uses_only_the_entry_confirmation_and_never_queries_images`
- `test_prepare_recovers_missing_sdk_tools_and_emulator_without_extra_input`
- `test_invalid_sdk_root_is_preserved_and_failure_shows_stage_and_log`
- `test_registered_damaged_emulator_is_reinstalled_once_and_preserves_avds`
- `test_damaged_emulator_uninstall_failure_prevents_install_and_creation`
- `test_installation_and_remote_query_have_no_secondary_read_gates`
- `test_temurin_java_is_downloaded_verified_and_published_in_user_directory`
- `test_temurin_checksum_mismatch_does_not_publish`
- `test_temurin_metadata_and_archive_retry_until_both_succeed`
- `test_temurin_local_download_error_is_not_retried_or_published`
- `test_temurin_official_redirect_is_checked_and_signed_query_is_not_logged`
- `test_temurin_dangling_external_symlink_is_rejected`
- `test_temurin_internal_existing_symlink_is_allowed`
- `test_temurin_post_install_health_failure_stops_without_recursive_install`
- `test_new_command_tools_can_switch_java_after_first_post_install_class_error`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
