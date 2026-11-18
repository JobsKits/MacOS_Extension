# ProjectEnvironmentSetupTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./ProjectEnvironmentSetupTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./ProjectEnvironmentSetupTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_source_is_pure_and_redacts_urls`
- `test_wrapper_fixed_version_and_java_matrix`
- `test_invalid_dynamic_duplicate_and_insecure_wrapper`
- `test_gradle_criteria_conflict_stops_before_network`
- `test_verified_official_fallback_and_cache_reuse`
- `test_bad_checksum_never_executes_archive`
- `test_official_checksum_required_when_wrapper_has_none`
- `test_cross_platform_environment_is_not_silently_applied`
- `test_environment_configuration_java_wins_over_old_jenv`
- `test_mode_back_navigation_and_cancel_do_not_write_project`
- `test_complete_system_mode_flow_preserves_existing_bindings_and_orders_stages`
- `test_pub_failure_stops_plugin_prewarm`
- `test_non_network_gradle_error_is_not_retried_or_marked_ready`
- `test_doctor_missing_toolchain_has_distinct_incomplete_status`
- `test_check_mode_is_read_only`
- `test_system_java_ignores_broken_jenv_declarations`
- `test_cross_platform_environment_can_be_reconfigured_with_backup`
- `test_full_web_flow_skips_broken_android_and_never_claims_actual_run`
- `test_missing_android_in_sdk_only_is_not_fatal`
- `test_no_java_environment_record_can_be_reused_without_installing_java`
- `test_fvm_manager_cancel_stops_even_when_old_sdk_is_healthy`
- `test_fzf_left_with_no_match_still_returns_previous_level`
- `test_ignoring_term_task_is_killed_after_timeout_grace`
- `test_event_version_is_optional_and_retained_at_stage_completion`
- `test_successful_sdk_flow_emits_actual_detected_versions`
- `test_sdk_bootstrap_progress_stays_separate_from_machine_version_and_events`
- `test_fvm_visible_version_comes_from_actual_manager_output`
- `test_tool_version_parser_ignores_other_component_warning_versions`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
