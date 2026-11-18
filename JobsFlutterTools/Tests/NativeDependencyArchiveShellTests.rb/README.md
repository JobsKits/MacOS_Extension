# NativeDependencyArchiveShellTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./NativeDependencyArchiveShellTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./NativeDependencyArchiveShellTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_export_uses_real_dart_and_produces_independently_verified_payload`
- `test_precache_wrapper_round_trip_restores_web_sdk_and_only_paired_stamps`
- `test_import_in_real_terminal_checks_then_requires_exact_yes_and_applies`
- `test_same_content_import_can_repeat_without_overwriting_or_losing_unrelated_files`
- `test_snapshot_changed_while_waiting_for_yes_is_checked_again_before_writing`
- `test_cancel_lowercase_empty_and_eof_never_apply_the_validated_snapshot`
- `test_existing_conflict_blocks_every_write_before_confirmation`
- `test_different_tool_version_is_rejected_before_yes_or_target_creation`
- `test_different_host_is_rejected_before_confirmation`
- `test_changed_project_lock_and_tampered_payload_each_block_before_apply`
- `test_export_missing_source_reports_precondition_without_running_dart`
- `test_cli_check_for_all_categories_and_modes_never_runs_tools_or_writes_logs`
- `test_invalid_cli_kind_and_duplicate_parameters_stop_before_business`
- `test_dispatch_preserves_all_fourteen_archive_actions_and_literal_project_path`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
