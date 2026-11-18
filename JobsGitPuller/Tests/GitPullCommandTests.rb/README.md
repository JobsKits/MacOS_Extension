# GitPullCommandTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./GitPullCommandTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./GitPullCommandTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_non_git_folder_is_a_noop`
- `test_clean_fast_forward`
- `test_dirty_non_conflicting_changes_keep_index_and_untracked`
- `test_cancel_dirty_does_not_fetch_or_change_files`
- `test_conflict_option_one_restores_exact_original_and_existing_stash`
- `test_conflict_option_two_requires_yes_and_updates_after_discard`
- `test_discard_retry_fetches_remote_commits_created_during_confirmation`
- `test_declining_discard_restores_original`
- `test_option_three_accepts_empty_message_and_second_rollback_keeps_commit`
- `test_committed_conflict_can_rollback_without_losing_local_commit`
- `test_commit_retry_does_not_revive_changes_discarded_in_previous_attempt`
- `test_fetch_failure_preserves_dirty_state`
- `test_user_no_commit_merge_option_cannot_report_false_success`
- `test_failed_diff_probe_stops_before_any_transaction`
- `test_failed_untracked_probe_stops_before_any_transaction`
- `test_declining_discard_after_external_edit_keeps_new_edit_and_conflict_scene`
- `test_ignored_file_is_not_overwritten_by_remote_tracked_file`
- `test_missing_upstream_stops_before_fetch`
- `test_existing_merge_conflict_is_preserved`
- `test_user_squash_merge_option_cannot_report_false_success`
- `test_linked_worktrees_share_the_session_lock`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
