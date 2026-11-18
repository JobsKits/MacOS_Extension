# RunAuthorizationCommandTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./RunAuthorizationCommandTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./RunAuthorizationCommandTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_help_is_readonly_and_needs_no_terminal`
- `test_check_is_readonly_and_reports_selected_file`
- `test_only_explicit_single_file_arguments_are_accepted`
- `test_directories_packages_links_missing_files_and_special_files_are_rejected`
- `test_noninteractive_input_cannot_authorize`
- `test_nonempty_confirmation_and_whitespace_cancel_without_writes`
- `test_eof_stops_without_authorization_or_logs`
- `test_confirmation_creates_private_distinct_logs_and_adds_execute_bits`
- `test_original_chmod_plus_x_umask_semantics_are_preserved`
- `test_special_path_is_one_literal_argument_and_target_is_never_executed`
- `test_quarantine_and_other_attributes_remain_unchanged`
- `test_target_replaced_while_confirming_is_not_authorized`
- `test_target_changed_to_symlink_while_confirming_is_not_authorized`
- `test_log_creation_failure_stops_before_chmod`
- `test_real_chmod_failure_is_reported_and_returned`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
