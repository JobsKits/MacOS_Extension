# InstallerRegistrationTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./InstallerRegistrationTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./InstallerRegistrationTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_helper_rejects_enabled_old_copy_and_keeps_refresh_marker`
- `test_helper_accepts_only_the_current_enabled_path_and_clears_marker`
- `test_helper_registration_failure_preserves_marker_and_stops_activation`
- `test_helper_activation_failure_preserves_marker_and_does_not_refresh`
- `test_helper_refresh_failure_preserves_marker`
- `test_independent_install_cleans_exact_old_host_and_extension_before_new_registration`
- `test_independent_install_registration_error_does_not_report_success`
- `test_independent_uninstall_removes_only_verified_app_and_keeps_ipa_file`
- `test_independent_install_rejects_noninteractive_input_before_any_mutation`
- `test_independent_install_nonempty_input_skips_before_any_mutation`
- `test_install_log_path_accepts_temporary_directory_with_or_without_trailing_slash`
- `test_uninstall_log_path_accepts_temporary_directory_with_or_without_trailing_slash`
- `test_independent_uninstall_skips_wrong_extension_identity`
- `test_independent_install_whitespace_input_skips_before_any_mutation`
- `test_build_phase_skip_does_not_run_system_commands`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
