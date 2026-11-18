# FlutterRunnerAndroidTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./FlutterRunnerAndroidTests.rb)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
ruby "./FlutterRunnerAndroidTests.rb"
```

使用已有 Ruby 与文件声明的测试库，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_empty_avd_inventory_enters_creation_and_confirms_exact_model_and_image`
- `test_model_cancel_writes_no_avd`
- `test_image_back_returns_to_model_without_writing`
- `test_final_cancel_does_not_create_or_install`
- `test_install_failure_stops_before_creation`
- `test_collision_created_after_confirmation_is_preserved`
- `test_adb_matching_ignores_physical_phone_and_other_avd`
- `test_no_avds_enters_initialization_without_launch_on_cancel`
- `test_existing_running_avd_is_reused_without_creation`
- `test_running_target_waits_for_exact_flutter_id`
- `test_flutter_wait_revalidates_original_avd_identity_and_serial_before_handoff`
- `test_creation_timeout_prevents_late_avd_writes`
- `test_fzf_left_with_no_matching_rows_returns_parent`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
