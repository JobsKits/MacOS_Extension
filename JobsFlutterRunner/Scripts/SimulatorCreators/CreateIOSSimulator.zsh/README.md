# 随包新建 iOS 模拟器

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

> [创建脚本](./CreateIOSSimulator.zsh) 与[桌面创建内核](../../../../JobsIOSSimulatorCreator/Scripts/CreateIOSSimulator.zsh)保持逐字节一致，使用本机已安装的 [**Xcode**](https://developer.apple.com/xcode/) 和可用 [**iOS**](https://developer.apple.com/ios/) Runtime。

## 一、<span id="usage">运行与影响</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
/bin/zsh ./CreateIOSSimulator.zsh
/bin/zsh ./CreateIOSSimulator.zsh --check
/bin/zsh ./CreateIOSSimulator.zsh --help
```

- 交互入口先显示自述，回车继续，非空输入取消。使用 [**fzf**](https://github.com/junegunn/fzf) 选择完整机型和匹配的已装系统；系统选择时 `←` 返回型号，`Esc` / `Ctrl+C` 取消，最终确认后新建唯一名称的设备。
- 创建后启动设备、打开系统模拟器界面，并有界等待 `simctl bootstatus`。不删除、关闭或重置已有设备，不安装工具或 Runtime。
- `--check` 只读体检工具链和可用组合，`--help` 只显示帮助。交互日志位于系统临时目录，实际位置显示在终端；失败保留已创建的设备并显示可追踪的 UDID。
- 从运行器调用后返回设备选择层，重新查询设备。脚本成功退出也可能表示用户取消，不能据此自动选择其它设备。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
