# 一键 Flutter 依赖迁移回归

在本目录运行：

```shell
dart ./FlutterDependencyMigrationTests.dart
```

需要已可运行的 Dart SDK 和 Git。测试只在系统临时目录创建工程、HOME、Pub、Gradle 与 Maven 缓存；不操作真实用户缓存，不安装依赖或访问私库。Git 夹具使用本机临时仓库准备真实 Pub Git 缓存，再移走原仓，以 `dart pub get --offline` 验证迁移后的缓存可独立解析。

覆盖改名缓存内容识别、原始缓存父目录、预览零写入、重复融合、凭据与执行配置排除、冲突整批拒绝、私库／全量过滤、Pods／SPM／OHPM／Web、包内链接物化、原生锁文件兼容、SHA-256 损坏拒绝，以及确认期间来源变更。测试默认在结束后清理自己的临时目录。

可设置 `JOBS_KEEP_FIXTURE=1` 保留隔离夹具供排查；测试打印 `FIXTURE=` 路径。测试不代表真实 Finder／Explorer 菜单、Windows 原生运行或完整 Flutter 离线构建已验收。
