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

- `test_prepare_context_resolves_wrapped_and_published_manager_paths`：真实部署库的路径初始化，覆盖包装／平铺布局、中文空格搬移目录、无关工作目录、`LC_ALL=C` 与严格模式；只加载定义和解析上下文，不执行安装或卸载。
- `test_first_install_migrates_only_enabled_legacy_leaves`
- `test_existing_selection_is_preserved_without_remigrating_closed_leaves`
- `test_failed_retirement_restores_original_configuration`
- `test_registration_failure_publishes_nothing_and_keeps_legacy_state`
- `test_failure_after_migration_marker_publication_restores_both_files`
- `test_external_configuration_edit_is_preserved`
- `test_partial_uninstall_keeps_other_leaf_and_last_uninstall_disables_aggregate`
- `test_malformed_configuration_never_becomes_default_all`
- `test_temporary_root_accepts_both_trailing_slash_forms`
- `test_bundled_sources_match_manifest_and_canonical_sources`
- `test_total_installer_deduplicates_six_leaves_into_one_project`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
