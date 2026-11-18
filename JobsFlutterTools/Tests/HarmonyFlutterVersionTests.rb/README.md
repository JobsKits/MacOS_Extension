# HarmonyFlutterVersionTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./HarmonyFlutterVersionTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./HarmonyFlutterVersionTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_check_is_local_read_only_and_never_calls_tools`
- `test_intro_cancel_and_eof_do_not_query_or_install`
- `test_final_cancel_never_runs_fvm_brew_or_changes_project`
- `test_success_from_no_fvm_project_uses_custom_cache_and_preserves_ide`
- `test_chained_run_chooses_latest_stable_without_reading_another_confirmation`
- `test_chained_run_failed_download_preserves_original_binding`
- `test_chained_run_incompatible_candidate_cannot_publish_binding`
- `test_real_dart_constraint_parser_rejects_low_versions_and_unparseable_data`
- `test_verify_current_sdk_is_local_and_does_not_bind_or_query_remote`
- `test_single_acquisition_attempt_has_a_real_timeout`
- `test_success_preserves_unknown_config_and_existing_preferences`
- `test_missing_fvm_install_is_after_explicit_confirmation`
- `test_clone_and_sdk_failures_leave_original_binding_byte_identical`
- `test_fvm_failure_or_wrong_link_only_changes_shadow`
- `test_concurrent_project_edit_is_preserved_and_publish_is_cancelled`
- `test_existing_project_lock_stops_without_fvm_or_download`
- `test_cache_symlink_is_rejected_before_download`
- `test_offline_uses_recorded_local_cache_and_rejects_wrong_source`
- `test_parser_reuses_menu_detector_for_flow_yaml_and_rejects_comment_only`
- `test_symlinked_project_config_and_real_sdk_directory_are_preserved`
- `test_fzf_selects_first_row_and_escape_cancels_without_tools`
- `test_failed_publish_restores_original_file_identity`
- `test_rollback_conflict_preserves_external_file_and_backup`
- `test_control_character_path_is_rejected_without_changes`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
