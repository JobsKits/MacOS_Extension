# FlutterVersionCommandTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./FlutterVersionCommandTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./FlutterVersionCommandTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_common_yaml_forms_are_accepted_and_misleading_text_is_rejected`
- `test_official_release_rows_mark_current_latest_cache_and_deduplicate_architectures`
- `test_malformed_latest_pointer_and_uninitialized_cache_are_not_advertised`
- `test_intel_history_retains_hotfix_versions_and_current_architecture_is_enforced`
- `test_configuration_merge_preserves_fields_and_only_pins_the_target`
- `test_network_failure_offers_healthy_cache_or_keeps_querying_until_cancelled`
- `test_healthy_chain_is_reused_without_package_installation`
- `test_missing_terminal_tools_are_installed_once_and_rechecked`
- `test_multiple_missing_layers_are_prepared_in_order`
- `test_install_failure_and_failed_recheck_stop_before_downstream_sdk_changes`
- `test_escape_leaves_project_untouched`
- `test_final_nonempty_confirmation_cancels_before_project_changes`
- `test_final_enter_continues_to_install_and_verify_the_selected_version`
- `test_final_confirmation_eof_stops_without_project_changes`
- `test_explicit_target_config_does_not_overwrite_ancestor_or_other_fields`
- `test_success_requires_both_project_link_and_real_sdk_version_to_match`
- `test_fvm_config_serialization_does_not_discard_existing_custom_fields`
- `test_configuration_changed_during_selection_is_preserved_and_rejected`
- `test_cli_rejects_symbolic_link_and_application_package_before_canonicalization`
- `test_fvm_metadata_symlinks_are_rejected_without_writing_their_targets`
- `test_sdk_mismatch_and_fvm_failure_report_partial_changes_truthfully`
- `test_noninteractive_real_entry_stops_without_logs_or_project_writes`
- `test_failed_use_restores_previous_config_when_sdk_link_is_untouched`
- `test_failed_use_removes_the_config_created_by_this_run`
- `test_verification_failure_leaves_an_already_consistent_config_untouched`
- `test_failed_verification_aligns_config_to_the_real_link_version`
- `test_confirmation_reports_whether_the_selected_version_is_cached`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
