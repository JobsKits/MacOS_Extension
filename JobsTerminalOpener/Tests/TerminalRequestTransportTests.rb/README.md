# TerminalRequestTransportTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./TerminalRequestTransportTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./TerminalRequestTransportTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_every_action_produces_one_terminal_line_even_with_quotes_and_newlines_in_target`
- `test_pod_is_a_direct_install_command_without_a_private_payload_or_workspace`
- `test_build_clean_payload_identifies_target_and_cleans_its_own_carrier`
- `test_complex_actions_keep_private_unique_payloads_and_target_out_of_terminal_input`
- `test_applescript_keeps_complex_payload_after_dispatch_success`
- `test_failed_applescript_request_cleans_its_complex_payload_immediately`
- `test_complex_request_cleanup_is_idempotent_and_cannot_delete_another_request`
- `test_missing_podfile_or_xcodeproj_dispatches_no_terminal_request`
- `test_pod_command_runs_install_once_in_the_literal_directory_without_confirmation`
- `test_direct_pod_command_preserves_its_exit_status`
- `test_failed_cd_never_executes_pod`
- `test_native_ruby_pod_prompt_is_visible_before_input_and_keeps_all_three_ttys`
- `test_real_control_c_during_native_pod_input_leaves_no_pod_process`
- `test_complex_payload_eof_cleans_request_without_running_tools`
- `test_interrupt_cleans_only_its_complex_payload`
- `test_hangup_cleans_complex_payload_without_running_tools`
- `test_termination_keeps_its_signal_status_and_cleans_complex_payload`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
