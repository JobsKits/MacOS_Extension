# 永久删除 · 隔离验证

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

仅在原生 MacOS 上使用系统 Swift 编译器，夹具由测试在临时目录新建，清理仅限这些夹具。不会注册扩展、重启 Finder 或删除真实用户文件。原生窗口测试需要登录桌面会话，截图仅显示测试夹具。

| 测试 | 验证 |
| --- | --- |
| [PermanentDeleteBehaviorTests.swift](./PermanentDeleteBehaviorTests.swift/PermanentDeleteBehaviorTests.swift) | 20项：特殊路径、URL往返、空选／重复／重叠／关键根保护、文件／目录递归、符号链接不穿透、目标与父目录替换、失败后剩余内容还原和无暂存遗留 |
| [PermanentDeleteInterfaceTests.swift](./PermanentDeleteInterfaceTests.swift/PermanentDeleteInterfaceTests.swift) | 21项：真实原生控件、左红右蓝、默认取消、十语言表、点击取消、关闭、红按钮焦点下Return、Esc、显式确认和仅夹具截图；不调用删除服务 |
| [PermanentDeleteControllerTests.swift](./PermanentDeleteControllerTests.swift/PermanentDeleteControllerTests.swift) | 4项：完整确认→后台删除夹具→modal自动唤醒→结果，最终busy和删除状态；不需要补充输入唤醒 |

在功能包根目录执行，输出位于本包 `work/`：

```shell
mkdir -p work/tests
for name in PermanentDeleteBehaviorTests PermanentDeleteInterfaceTests PermanentDeleteControllerTests; do
  swiftc -parse-as-library -framework AppKit -framework FinderSync \
    Shared/**/*.swift JobsPermanentDeleter/PermanentDelete*/*.swift \
    "Tests/${name}.swift/${name}.swift" -o "work/tests/${name}" || break
  "work/tests/${name}" "$PWD/work/ConfirmationPreview.png" || break
done
```

确认框预览为 [work/ConfirmationPreview.png](../work/ConfirmationPreview.png)，只展示临时测试文件。真实 Finder 安装和右键点击尚未验证；强杀、断电与恶意同用户并发修改不在已验证恢复保证内。当前成品与源码摘要查看中央[资产盘点](../../../项目相关报告/永久删除资产盘点.md)。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
