# PackageImportDispatchTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./PackageImportDispatchTests.py)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
python3 -B "./PackageImportDispatchTests.py"
```

使用已有 Python 3 与标准库/源码声明的测试依赖，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_packaged_resource_matches_standalone_source`
- `test_option_like_project_names_cannot_bypass_terminal_confirmation`
- `test_dispatch_resolves_imports_from_each_file_without_sdk`
- `test_legal_flutter_manifests_supported_by_the_menu_can_be_repaired`
- `test_test_and_nested_imports_are_resolved_from_their_own_directory`
- `test_conditional_imports_preserve_conditions_and_suffixes`
- `test_package_dart_export_part_comments_and_strings_are_preserved`
- `test_missing_and_outside_lib_targets_are_preserved`
- `test_generated_third_party_and_other_authors_are_preserved`
- `test_linked_files_directories_and_targets_are_preserved`
- `test_cancel_and_eof_leave_project_unchanged`
- `test_check_and_dry_run_are_noninteractive_and_leave_no_artifacts`
- `test_piped_confirmation_cannot_bypass_terminal_requirement`
- `test_success_creates_exact_original_backup_and_a_log_outside_project`
- `test_ordinary_dart_parent_and_platform_directories_are_rejected`
- `test_direct_check_rejects_dev_dependency_only_projects`
- `test_symbolic_link_project_is_rejected_before_canonicalization`
- `test_repeated_execution_is_idempotent`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
