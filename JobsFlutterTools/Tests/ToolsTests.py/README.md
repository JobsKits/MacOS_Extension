# ToolsTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./ToolsTests.py)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
python3 -B "./ToolsTests.py"
```

使用已有 Python 3 与标准库/源码声明的测试依赖，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_missing_fvm_never_runs_global`
- `test_namespace_only_resolved_plugins_and_backup_collisions`
- `test_namespace_cancel_and_preview_do_not_write`
- `test_imports_only_real_directives_and_keep_encoded_delimiters`
- `test_backup_symlink_refused`
- `test_harmony_requires_base_and_adaptation_together`
- `test_maintenance_blank_and_failed_clean_do_not_upgrade`
- `test_cache_ancestor_link_is_rejected_before_deletion`
- `test_android_repair_honors_project_sdk_and_pinned_build_tools`
- `test_menu_migration_requires_enabled_group_and_preserves_other_choices`
- `test_namespace_preserves_bom_and_exact_backup_bytes`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
