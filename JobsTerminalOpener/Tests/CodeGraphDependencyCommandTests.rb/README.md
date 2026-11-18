# CodeGraphDependencyCommandTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./CodeGraphDependencyCommandTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./CodeGraphDependencyCommandTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_real_embedded_script_has_valid_zsh_syntax`
- `test_actual_node_probe_rejects_unsupported_runtime_versions`
- `test_healthy_cli_creates_only_the_selected_map_without_tool_updates`
- `test_healthy_standalone_cli_reports_missing_installation_upstream_without_installing_it`
- `test_healthy_cli_still_reports_broken_node_npm_brew_and_download_tools`
- `test_healthy_cli_runs_brew_doctor_and_reports_its_warning_without_upgrading`
- `test_existing_map_is_checked_then_synced_without_reinitializing_or_deleting`
- `test_noninteractive_input_stops_before_logs_or_tool_execution`
- `test_waiting_for_the_first_confirmation_does_not_write_or_probe_tools`
- `test_cancelling_missing_cli_installation_does_not_run_installation_tools_or_build_map`
- `test_missing_cli_uses_official_npm_package_and_user_prefix_after_confirmation`
- `test_broken_cli_and_broken_help_are_replaced_once_in_the_user_prefix`
- `test_missing_node_npm_are_installed_by_brew_and_rechecked_before_cli_installation`
- `test_registered_broken_node_npm_are_reinstalled_once`
- `test_missing_brew_can_choose_system_location_without_touching_profiles`
- `test_missing_brew_can_choose_user_location_without_sudo_or_profile_changes`
- `test_missing_or_broken_curl_stops_before_brew_or_npm`
- `test_unavailable_clt_requests_system_installation_then_stops_downstream`
- `test_missing_xcrun_and_broken_clang_do_not_reach_brew`
- `test_broken_brew_configuration_stops_before_node_or_cli_installation`
- `test_brew_doctor_warning_does_not_reinstall_a_healthy_package_manager`
- `test_failed_brew_installation_stops_without_switching_locations`
- `test_brew_installation_success_without_healthy_result_stops`
- `test_failed_node_installation_does_not_install_cli_or_retry`
- `test_node_installation_success_with_broken_result_stops_after_one_attempt`
- `test_registry_failure_does_not_install_cli_or_build_map`
- `test_failed_cli_installation_does_not_build_map_or_retry`
- `test_cli_installation_success_with_broken_result_stops_before_map`
- `test_map_command_and_status_failures_preserve_the_external_exit_code`
- `test_existing_map_belonging_to_another_project_is_not_synced`
- `test_invalid_or_incomplete_status_is_not_reported_as_success`
- `test_published_1_6_2_status_and_optional_new_fields_are_both_supported`
- `test_map_directory_without_database_is_initialized_without_deleting_other_content`
- `test_symlink_or_regular_file_map_is_rejected_without_running_cli`
- `test_database_or_sidecar_symlinks_cannot_redirect_writes_to_another_project`
- `test_invalid_or_incomplete_database_stops_before_status_can_fall_back_to_parent`
- `test_successful_map_command_without_local_schema_does_not_read_status_or_claim_success`
- `test_sqlite_health_and_schema_checks_do_not_load_user_sqliterc`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
