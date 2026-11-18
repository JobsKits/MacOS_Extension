# FileContentViewerTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./FileContentViewerTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./FileContentViewerTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_small_unicode_text_is_shown_and_filename_is_literal`
- `test_empty_file_has_a_complete_readout`
- `test_control_characters_are_not_executed_by_the_terminal`
- `test_threshold_is_strictly_greater_and_invalid_values_stop`
- `test_default_one_mib_gate_happens_before_sample_and_content`
- `test_utf8_split_at_sampling_boundary_remains_text`
- `test_invalid_utf8_at_real_eof_requests_hex_confirmation`
- `test_missing_directory_symlink_fifo_and_multiple_targets_are_rejected`
- `test_yes_in_a_pipe_is_not_interactive_approval`
- `test_terminal_confirmation_accepts_only_exact_yes`
- `test_large_binary_requires_two_confirmations_and_safe_hex`
- `test_ctrl_c_and_eof_cancel_before_content`
- `test_file_growth_after_confirmation_does_not_exceed_initial_length`
- `test_private_carrier_executes_literal_target_and_cleans_itself`
- `test_independent_manager_preserves_sibling_features_when_installing_and_removing_one_leaf`
- `test_old_installation_without_metadata_does_not_invent_a_new_enabled_leaf`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
