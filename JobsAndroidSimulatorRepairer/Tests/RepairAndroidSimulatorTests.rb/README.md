# RepairAndroidSimulatorTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./RepairAndroidSimulatorTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./RepairAndroidSimulatorTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_check_queries_only_emulators_and_creates_no_tool_log`
- `test_check_low_space_and_wrong_location_report_nonzero`
- `test_bad_df_is_diagnostic_failure`
- `test_physical_serial_unknown_flags_and_auto_yes_are_rejected_before_adb`
- `test_missing_explicit_adb_does_not_install_or_fallback`
- `test_noninteractive_repair_stops_before_initializing_log`
- `test_install_location_requires_nonempty_confirmation_and_readback`
- `test_shell_error_with_zero_exit_cannot_report_install_success`
- `test_compile_reset_requires_yes_and_refuses_error_text`
- `test_uninstall_rejects_injection_prefix_and_builtin_packages`
- `test_uninstall_exact_third_party_package_requires_yes_and_success`
- `test_size_parser_supports_byte_k_m_g_and_rejects_unknown_values`
- `test_avd_root_environment_and_descriptor_paths_are_used`
- `test_avd_outside_root_symlink_and_wrong_identity_are_rejected`
- `test_capacity_refuses_custom_userdata_unknown_process_shrink_and_duplicate_key`
- `test_target_must_exceed_filesystem_and_image_logical_size`
- `test_duplicate_descriptor_and_avd_identity_are_rejected`
- `test_cold_boot_does_not_pass_without_actual_capacity_growth`
- `test_backup_space_failure_preserves_config`
- `test_stop_failure_or_residual_lock_preserves_config_without_backup`
- `test_successful_config_change_has_full_backup_and_remains_pending_without_cold_boot`
- `test_backup_failure_prevents_config_write`
- `test_config_change_during_stop_is_not_overwritten`
- `test_menu_preserves_failed_action_exit_status`
- `test_log_control_sequences_are_removed`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
