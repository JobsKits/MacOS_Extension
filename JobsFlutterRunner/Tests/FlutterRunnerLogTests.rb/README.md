# FlutterRunnerLogTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./FlutterRunnerLogTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./FlutterRunnerLogTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_log_labels_have_icons_and_preserve_source_urls`
- `test_terminal_errors_are_red_and_urls_restore_the_error_color`
- `test_terminal_plain_modes_keep_urls_and_error_body_without_ansi`
- `test_success_and_warnings_are_distinct_from_machine_noise`
- `test_build_start_does_not_claim_success_and_errors_survive`
- `test_spm_warning_preserves_plugin_names_and_explanation`
- `test_known_macos_shortcuts_index_diagnostics_are_folded_once`
- `test_unknown_and_real_build_errors_survive_system_index_filter`
- `test_machine_app_errors_with_system_index_text_are_never_folded`
- `test_stream_preserves_split_utf8_partial_lines_and_failure_exit`
- `test_sdk_download_carriage_returns_are_visible_before_worker_exit`
- `test_replay_and_machine_logs_keep_all_sdk_progress_frames`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
