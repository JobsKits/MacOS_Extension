# SetupFlutterRunTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./SetupFlutterRunTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./SetupFlutterRunTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_jsonc_keeps_url_and_does_not_execute_tasks_or_substitution`
- `test_xml_run_configuration_reads_quoted_flavor_and_rejects_entities`
- `test_unknown_flags_and_control_values_not_forwarded`
- `test_device_list_filters_target_platform_and_preserves_real_ids`
- `test_started_requires_real_event_matching_app_start_and_device`
- `test_target_and_define_file_cannot_escape_project`
- `test_valid_start_detaches_and_marks_actual_run_verified`
- `test_preflight_failure_and_timeout_never_open_run_channel_or_start_flutter`
- `test_final_confirmation_cancel_does_not_check_health_or_start_flutter`
- `test_preflight_adapter_preserves_selected_environment_output_and_timeout`
- `test_preflight_adapter_requires_complete_packaged_module`
- `test_app_start_only_is_not_launch_success`
- `test_build_failure_preserves_real_exit_code`
- `test_fixed_bundler_healthy_reuse_passes_locked_selector`
- `test_missing_fixed_bundler_installs_user_gem_and_rechecks`
- `test_android_simulator_entry_executes_core_with_real_tty`
- `test_bundler_26_rejects_old_path_ruby_and_reuses_compatible_brew_ruby`
- `test_real_ruby_gate_checks_version_not_just_executability`
- `test_large_raw_log_keeps_streamed_start_state_without_size_limit_false_negative`
- `test_sr_event_forwards_visible_version_and_retains_it_for_same_node`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
