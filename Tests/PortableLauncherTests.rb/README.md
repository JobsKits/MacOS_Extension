# PortableLauncherTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./PortableLauncherTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./PortableLauncherTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_every_package_works_after_copy_rename_and_unrelated_working_directory`
- `test_runtime_package_root_works_when_every_app_is_detached_from_its_scripts`
- `test_command_passes_its_package_root_through_open_to_a_detached_app`
- `test_direct_app_accepts_a_user_selected_valid_package_for_root_and_single_feature`
- `test_cancel_and_picker_failure_never_execute_a_worker`
- `test_wrong_package_and_a_directory_in_place_of_a_worker_are_rejected_with_actual_path`
- `test_diagnosis_reports_resolved_paths_without_ui_or_business_for_success_and_failure`
- `test_all_shipping_launchers_have_no_developer_machine_path_fallback`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
