# 随包新建 Harmony 模拟器

![Jobs出品，必属精品](https://picsum.photos/1500/400)

[toc]

---

## 🔥 <span id="前言">前言</span>

> [创建脚本](./CreateHarmonySimulator.zsh) 与[桌面创建内核](../../../../JobsHarmonySimulatorCreator/Scripts/CreateHarmonySimulator.zsh)保持逐字节一致，复用 [**HarmonyOS**](https://developer.huawei.com/consumer/cn/) 官方模拟器流程。

## 一、<span id="usage">运行与影响</span> <a href="#前言" style="font-size:17px; color:green;"><b>🔼</b></a> <a href="#🔚" style="font-size:17px; color:green;"><b>🔽</b></a>

```shell
/bin/zsh ./CreateHarmonySimulator.zsh --create
/bin/zsh ./CreateHarmonySimulator.zsh --prepare
/bin/zsh ./CreateHarmonySimulator.zsh --check
```

- 交互首屏回车继续，非空输入 / `Ctrl+C` 取消；按设备类型、已下载 Release 镜像、唯一名称选择并最终确认，新建后核验唯一实例再交给官方工具启动，不覆盖或删除既有实例。
- 缺工具时沿原流程准备命令行工具，缺镜像沿官方获取流程补齐并复检。SDK 获取显示真实进度并持续重试至就绪或主动结束；许可和额外账号授权仍由本人完成。`--prepare` 只准备工具和镜像，不创建设备；`--check` / `--help` 只读。
- `HARMONY_EMULATOR_BIN` 可显式指定官方工具；`DEVECO_STUDIO_HOME` / `TOOL_HOME` 指定已有工具根目录；`--name 名称` 指定新名称，`--no-start` 只创建不启动。日志显示系统临时目录中的实际路径。
- 官方启动命令返回不等于系统已完成开机；运行器返回设备选择层重新查询设备，必要时等待后重新加载。用户取消不视为创建成功。

**终端配色保护：** 独立运行时，在支持完整保存与恢复配色的交互终端中临时使用黑底白字及统一强调色；正常结束、失败或可捕获中断后恢复进入前的配色，不修改终端全局偏好或 Shell 启动配置。不支持完整保护、无交互终端、`NO_COLOR`、既有纯文本模式和 Sourcetree 场景不切换配色，并沿用纯文本输出约定。强制终止（如 `kill -9`）无法由脚本自身保证恢复，请使用运行时显示的独立恢复入口。

<a id="🔚" href="#前言" style="font-size:17px; color:green; font-weight:bold;">我是有底线的➤点我回到首页</a>
