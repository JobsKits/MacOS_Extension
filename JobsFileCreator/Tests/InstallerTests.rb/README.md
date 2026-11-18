# InstallerTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./InstallerTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./InstallerTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_rejected_arguments_stop_before_system_commands`
- `test_help_is_read_only`
- `test_install_verifies_then_registers_exact_product`
- `test_skip_restart_leaves_refresh_to_outer_manager`
- `test_first_registration_can_be_rediscovered_once_after_a_successful_but_invisible_add`
- `test_second_registration_failure_keeps_its_exit_code_and_does_not_claim_success`
- `test_missing_disabled_and_old_path_records_never_turn_the_installation_green`
- `test_build_failure_stops_registration_and_releases_lock`
- `test_existing_lock_stops_before_system_commands`
- `test_uninstall_ignores_unowned_paths_and_keeps_app`
- `test_copied_package_opens_gui_with_only_file_create_scope`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
