# BuildArtifactDispatchTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./BuildArtifactDispatchTests.py)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
python3 -B "./BuildArtifactDispatchTests.py"
```

使用已有 Python 3 与标准库/源码声明的测试依赖，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_cancel_and_eof_keep_project_without_fvm`
- `test_block_flow_and_quoted_flutter_declarations_work_without_fvm`
- `test_misleading_and_duplicate_yaml_declarations_are_rejected`
- `test_project_without_lib_accepts_flow_and_quoted_dependencies`
- `test_oversized_invalid_utf8_and_linked_manifests_are_rejected`
- `test_packaged_cleaner_keeps_native_platform_scope_and_protected_files`
- `test_non_flutter_root_is_rejected_before_cleanup`
- `test_linked_target_rejects_entire_plan_before_deleting`
- `test_linked_project_is_rejected_before_canonicalization`
- `test_sdk_maintenance_keeps_fvm_requirement`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
