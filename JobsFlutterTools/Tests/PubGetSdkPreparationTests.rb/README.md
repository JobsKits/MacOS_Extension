# PubGetSdkPreparationTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./PubGetSdkPreparationTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./PubGetSdkPreparationTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_unbound_project_prepares_sdk_then_checks_health_before_pub_get`
- `test_healthy_pinned_sdk_is_reused_without_manager_or_global_sdk`
- `test_legacy_fvm_config_with_healthy_sdk_is_reused`
- `test_explicit_system_sdk_record_wins_over_old_fvm_and_global_flutter`
- `test_system_sdk_record_check_is_read_only_and_needs_no_jdk`
- `test_broken_explicit_sdk_does_not_switch_to_fvm`
- `test_foreign_or_malformed_or_linked_environment_stops_before_sdk`
- `test_declaration_with_broken_link_enters_sdk_preparation`
- `test_executable_but_broken_flutter_is_repaired_once`
- `test_executable_but_broken_dart_is_repaired_once`
- `test_missing_actual_dart_runtime_is_not_hidden_by_bin_dart_shim`
- `test_manager_failure_preserves_exit_code_and_stops_dependency_pull`
- `test_manager_cancellation_stops_even_if_an_sdk_has_become_healthy`
- `test_manager_success_without_binding_fails_recheck_without_retry`
- `test_manager_success_with_broken_flutter_fails_recheck_without_retry`
- `test_manager_success_with_broken_dart_fails_recheck_without_retry`
- `test_pub_get_failure_is_not_masked_or_retried`
- `test_parent_sdk_and_global_sdk_cannot_replace_target_binding`
- `test_non_tty_refuses_before_sdk_manager_or_log_writes`
- `test_confirmation_eof_stops_before_sdk_preparation`
- `test_read_only_check_with_missing_sdk_never_starts_preparation`
- `test_read_only_check_does_not_invoke_even_a_broken_executable_sdk`
- `test_other_actions_still_stop_at_existing_fvm_gate`
- `test_real_manager_cancellation_paths_distinguish_standalone_and_chained_calls`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
