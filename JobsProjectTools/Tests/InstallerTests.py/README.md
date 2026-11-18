# InstallerTests 回归入口

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

[实际测试脚本](./InstallerTests.py)验证同包功能的接口和边界；保留原回归协议，不增加重复确认。

## 一、运行方式 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

在当前脚本包目录运行，保留完整功能目录以定位被测源码：

```shell
python3 -B "./InstallerTests.py"
```

使用已有 Python 3 与标准库/源码声明的测试依赖，不因目录包装安装或升级环境。各平台、GUI、SDK和网络分支的依赖及取消条件以用例声明为准；未满足的条件不能当作测试通过。

## 二、覆盖项与结果 <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

- `test_relocated_wrapped_and_flat_entries_resolve_their_own_resources`：保留真实入口初始化，覆盖源码同名包装与发布平铺、中文空格搬移目录、无关工作目录及严格模式；使用临时 HOME 和部署库替身，不触碰真实安装。
- `test_retired_sourcetree_does_not_keep_an_uninstalled_package_alive`：九项现行功能卸载后，旧退役标识不再保留临时 App；再次卸载不调用系统工具。
- `test_unknown_configuration_is_preserved_and_never_treated_as_uninstalled`：异常配置必须保留并返回失败，不能归为无需卸载。
- `test_migration_partial_uninstall_reinstall_and_full_uninstall`
- `test_failure_after_configuration_publication_restores_exact_prior_files`
- `test_build_and_registration_failures_keep_legacy_and_configuration`
- `test_clean_install_does_not_enable_unselected_features`
- `test_retired_sourcetree_rejects_install_and_legacy_uninstall_preserves_siblings`
- `test_unknown_feature_has_no_side_effects`
- `test_legacy_uninstall_does_not_create_group_configuration`
- `test_existing_group_migrates_once_and_preserves_other_terminal_entries`
- `test_uninstalling_ide_before_migration_preserves_legacy_git_choice`
- `test_explicit_empty_commit_uninstall_only_removes_its_legacy_menu`
- `test_rollback_migrates_once_then_respects_uninstall`
- `test_rollback_uninstall_preserves_unrelated_legacy_menus`
- `test_rollback_entries_and_bundle_use_the_shared_implementation`
- `test_all_entry_points_route_to_the_group`

终端输出通过、失败和跳过；非零退出表示失败。临时夹具、日志及子进程按用例输出定位。目录迁移与语法检查不代表真实安装、设备、GUI或目标系统业务已验收。

[返回测试目录](../README.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
